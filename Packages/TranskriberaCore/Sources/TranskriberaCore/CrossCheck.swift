import Foundation

/// Experiment "Korskolla med KB Large": hela ljudet transkriberas också med KB Large, och där
/// modellerna hörde olika ord får Pianissimos ord en prickad understrykning. Klickar man på
/// ordet väljer man mellan de två tolkningarna (beslut Nicklas 2026-11-13: en liten meny med
/// två val och Lyssna, inget mer).
///
/// Bakgrund: på mötet 2026-11-12 hade båda modellerna fel som ändrade innebörden ("bör" i
/// stället för "behöver", ett "inte" som saknades), men sällan på samma ställe. Fem av sex
/// sådana fel syntes som en skillnad mellan modellerna.
///
/// Bara skillnader där ett ord som ändrar innebörden ("inte", "bör", "måste" …) skiljer sig
/// markeras (beslut Nicklas 2026-11-13). Mätt på mötet med Klang som facit: regeln "innebördsord
/// eller ord som låter helt olika" gav en markering var 22:a sekund, den här en per 1,5 minut och
/// fångade nästan lika många innebördsfel (19 mot 21 av 37). Stavning, böjningar, ord som bara
/// låter olika, skiljetecken och utfyllnadsord ("eh") markeras inte.
public enum CrossCheck {
    /// Ord som ändrar innebörden även när resten är likt.
    static let meaningWords: Set<String> = [
        "inte", "ej", "aldrig", "alltid", "bör", "behöver", "måste", "ska", "skulle", "kan", "kunde",
        "får", "fick", "ingen", "inget", "inga", "bara", "nog", "vill", "ville"
    ]
    /// Utfyllnad som KB Large ordagrann skriver ut men Pianissimo inte gör.
    static let fillers: Set<String> = ["eh", "öh", "äh", "ehm", "öhm", "ähm", "hm", "hmm", "mm", "mhm", "mmm"]
    /// Korta svar som bara den ena hörde. Hör till "Fånga korta svar", inte hit.
    static let shortAnswers: Set<String> = ["ja", "nej", "jo", "precis", "okej", "ok", "aa", "jaa", "japp"]
    /// Längre skillnader är oftast ett parti som den ena tappade; det går inte att välja i en meny.
    static let longestSpan = 6

    /// Ett ord i jämförelsen.
    struct Token {
        var segment: Int
        var word: Int
        var raw: String
        var key: String
    }

    /// Sätter `alternative` på Pianissimos ord där `other` (den andra körningen) hörde något annat.
    /// Ger segmenten och hur många ställen som markerades.
    public static func mark(_ segments: [SegmentData], against other: [WordTimingData]) -> (segments: [SegmentData], marked: Int) {
        var result = segments
        // Tidigare markeringar gäller inte längre.
        for s in result.indices {
            for w in result[s].words.indices {
                result[s].words[w].alternative = nil
                result[s].words[w].alternativeLength = nil
            }
        }
        var mine: [Token] = []
        for (s, segment) in result.enumerated() {
            for (w, word) in segment.words.enumerated() {
                let key = normalized(word.word)
                guard !key.isEmpty, !fillers.contains(key) else { continue }
                mine.append(Token(segment: s, word: w, raw: word.word, key: key))
            }
        }
        let theirs: [String] = other.map(\.word).filter {
            let key = normalized($0)
            return !key.isEmpty && !fillers.contains(key)
        }
        let theirKeys = theirs.map(normalized)

        var marked = 0
        for change in changes(old: theirKeys, new: mine.map(\.key)) {
            guard let found = proposal(change, mine: mine, theirs: theirs, theirKeys: theirKeys) else { continue }
            let (span, text) = found
            let segment = mine[span.lowerBound].segment
            guard mine[span.upperBound - 1].segment == segment else { continue }
            let first = mine[span.lowerBound].word
            let last = mine[span.upperBound - 1].word
            guard !result[segment].words[first...last].contains(where: { $0.alternative != nil }) else { continue }
            let current = result[segment].words[first...last].map(\.word)
            let alternative = adapted(text, to: current)
            guard normalized(alternative) != normalized(current.joined()) else { continue }
            result[segment].words[first].alternative = alternative
            result[segment].words[first].alternativeLength = last - first + 1
            marked += 1
        }
        return (result, marked)
    }

    /// Ett ställe där modellerna skiljer sig: index i den andras ord och i Pianissimos.
    struct Change: Equatable {
        var old: Range<Int>
        var new: Range<Int>
    }

    /// Skillnaderna mellan två ordföljder, som sammanhängande ställen.
    static func changes(old: [String], new: [String]) -> [Change] {
        let difference = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [Change] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, j < new.count, !removed.contains(i), !inserted.contains(j) {
                i += 1; j += 1
                continue
            }
            let (i0, j0) = (i, j)
            while (i < old.count && removed.contains(i)) || (j < new.count && inserted.contains(j)) {
                while i < old.count, removed.contains(i) { i += 1 }
                while j < new.count, inserted.contains(j) { j += 1 }
            }
            if i == i0 && j == j0 { break }
            result.append(Change(old: i0..<i, new: j0..<j))
        }
        return result
    }

    /// Vilka av Pianissimos ord som ska markeras och vad den andra modellen hörde där, eller
    /// `nil` om skillnaden inte är värd att visa.
    static func proposal(_ change: Change, mine: [Token], theirs: [String], theirKeys: [String]) -> (Range<Int>, String)? {
        let mineKeys = mine[change.new].map(\.key)
        let otherKeys = Array(theirKeys[change.old])
        let otherText = theirs[change.old].map(trimmed)
        guard mineKeys.count <= longestSpan, otherKeys.count <= longestSpan else { return nil }
        guard changesMeaning(mineKeys, otherKeys) else { return nil }

        if !mineKeys.isEmpty, !otherKeys.isEmpty {
            // Ord mot ord.
            return (change.new, otherText.joined(separator: " "))
        }
        if !otherKeys.isEmpty {
            // Den andra hörde ord som saknas här. Grannordet markeras, så att menyn visar
            // "bara" mot "inte bara" och inte ett tomt val.
            guard !otherKeys.allSatisfy(shortAnswers.contains) else { return nil }
            let at = change.new.lowerBound
            let next = at < mine.count ? at : nil
            let previous = at > 0 ? at - 1 : nil
            if let next, previous.map({ mine[$0].segment == mine[next].segment }) ?? true {
                return (next..<next + 1, (otherText + [trimmed(mine[next].raw)]).joined(separator: " "))
            }
            if let previous {
                return (previous..<previous + 1, ([trimmed(mine[previous].raw)] + otherText).joined(separator: " "))
            }
            return nil
        }
        // Ord som bara finns här ("inte").
        guard !mineKeys.isEmpty else { return nil }
        let end = change.new.upperBound
        if end < mine.count, mine[end].segment == mine[change.new.lowerBound].segment {
            return (change.new.lowerBound..<end + 1, trimmed(mine[end].raw))
        }
        let start = change.new.lowerBound
        if start > 0, mine[start - 1].segment == mine[start].segment {
            return (start - 1..<change.new.upperBound, trimmed(mine[start - 1].raw))
        }
        return nil
    }

    /// Sant när ett ord som ändrar innebörden finns hos den ena men inte den andra. Det är
    /// regeln för vad som markeras.
    static func changesMeaning(_ mine: [String], _ other: [String]) -> Bool {
        !Set(mine).symmetricDifference(other).isDisjoint(with: meaningWords)
    }

    /// Den andras ord med samma stor bokstav och skiljetecken som orden de ersätter, så att
    /// meningen ser likadan ut vilket man än väljer.
    static func adapted(_ text: String, to current: [String]) -> String {
        var words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty, let firstCurrent = current.first.map(trimmed), let lastCurrent = current.last.map(trimmed) else { return text }
        // Skiljetecken sist kommer från texten som står.
        while let last = words.last?.last, isPunctuation(last) {
            words[words.count - 1].removeLast()
            if words[words.count - 1].isEmpty { words.removeLast() }
            if words.isEmpty { return text }
        }
        words[words.count - 1] += String(lastCurrent.reversed().prefix(while: isPunctuation).reversed())
        if let initial = firstCurrent.first, let head = words[0].first, initial.isLetter, head.isLetter {
            let fixed = initial.isUppercase ? String(head).uppercased() : String(head).lowercased()
            words[0] = fixed + words[0].dropFirst()
        }
        return words.joined(separator: " ")
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        ".,?!…;:".contains(character)
    }

    private static func trimmed(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Länken som ett markerat ord får i texten: segmentets och ordets nummer.
    public static let linkScheme = "transkribera-korskoll"

    public static func link(segment: Int, word: Int) -> URL? {
        URL(string: "\(linkScheme)://ord/\(segment)/\(word)")
    }

    /// Segmentets och ordets nummer ur en länk från `link`, annars `nil`.
    public static func parse(_ url: URL) -> (segment: Int, word: Int)? {
        guard url.scheme == linkScheme else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let segment = Int(parts[0]), let word = Int(parts[1]) else { return nil }
        return (segment, word)
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Lista för Testlabbet

    /// Ett markerat ställe, för listan som Testlabbet sparar.
    public struct Mark: Equatable, Sendable {
        public var time: Double
        public var speaker: String?
        /// Orden som står i texten.
        public var heard: String
        /// Vad den andra modellen hörde.
        public var other: String
        public var before: String
        public var after: String
    }

    /// Alla markeringar i ordning, med `context` ord före och efter inom samma stycke.
    public static func marks(in segments: [SegmentData], context: Int = 6) -> [Mark] {
        var result: [Mark] = []
        for segment in segments {
            let words = segment.words
            for (index, word) in words.enumerated() {
                guard let other = word.alternative else { continue }
                let end = min(words.count, index + max(1, word.alternativeLength ?? 1))
                func text(_ range: Range<Int>) -> String {
                    words[range].map { trimmed($0.word) }.filter { !$0.isEmpty }.joined(separator: " ")
                }
                result.append(Mark(
                    time: word.start,
                    speaker: segment.speaker,
                    heard: text(index..<end),
                    other: other,
                    before: text(max(0, index - context)..<index),
                    after: text(end..<min(words.count, end + context))
                ))
            }
        }
        return result
    }

    /// Listan som text: en rad per ställe, att gå igenom med ljudet bredvid.
    /// `anonymize` körs på varje rad när anonymiseringen är på.
    public static func report(_ marks: [Mark], other: String, minutes: Double,
                              anonymize: (String) -> String = { $0 }) -> String {
        let rate = minutes > 0 ? String(format: "%.0f", Double(marks.count) / minutes * 60) : "–"
        var out = """
        Korskoll med \(other): \(marks.count) \(marks.count == 1 ? "ställe" : "ställen") (\(rate) per timme).
        Varje rad: tid, talare, texten med Pianissimos ord inom [ ], och vad \(other) hörde.
        Lyssna på tiden och skriv P om Pianissimo hade rätt, K om \(other) hade rätt, B om båda fel.


        """
        for mark in marks {
            let line = "\(mark.before) [\(mark.heard)] \(mark.after)".trimmingCharacters(in: .whitespaces)
            out += "\(TimeFormatting.short(mark.time))  \(mark.speaker ?? "–")  …\(line)…  →  \(other): \(mark.other)\n"
        }
        return anonymize(out)
    }

    // MARK: - Välja i menyn

    /// Användaren valde den andra tolkningen för ordet `index`: orden byts ut och markeringen
    /// försvinner. Texten ändras bara där orden står, så att resten av segmentet är orört.
    public static func choose(alternativeAt index: Int, in segment: SegmentData) -> SegmentData {
        guard segment.words.indices.contains(index), let alternative = segment.words[index].alternative else { return segment }
        let length = max(1, min(segment.words[index].alternativeLength ?? 1, segment.words.count - index))
        let span = index..<index + length
        var result = segment
        let ranges = wordRanges(segment.words, in: segment.text)
        if let lower = ranges[span.lowerBound]?.lowerBound, let upper = ranges[span.upperBound - 1]?.upperBound {
            result.text.replaceSubrange(lower..<upper, with: alternative)
        } else {
            var replaced = segment.words.map(\.word)
            replaced.replaceSubrange(span, with: [" " + alternative])
            result.text = TextCleaning.clean(replaced.joined())
        }
        // Nya ord med tiderna jämnt fördelade över de gamla ordens tid.
        let parts = alternative.split(separator: " ").map(String.init)
        let start = segment.words[span.lowerBound].start
        let end = segment.words[span.upperBound - 1].end
        let step = (end - start) / Double(max(1, parts.count))
        let uncertain: Bool? = segment.words[span].contains { $0.uncertainSpeaker == true } ? true : nil
        let words = parts.enumerated().map { offset, part in
            WordTimingData(word: " " + part, start: start + Double(offset) * step, end: start + Double(offset + 1) * step,
                           probability: 1, uncertainSpeaker: uncertain)
        }
        result.words.replaceSubrange(span, with: words)
        return result
    }

    /// Användaren behöll ordet som står: markeringen försvinner.
    public static func keep(at index: Int, in segment: SegmentData) -> SegmentData {
        guard segment.words.indices.contains(index) else { return segment }
        var result = segment
        result.words[index].alternative = nil
        result.words[index].alternativeLength = nil
        return result
    }

    /// Orden från `index` som markeringen gäller, och tiden att spela upp: två ord före och två efter.
    public static func listeningRange(at index: Int, in words: [WordTimingData], context: Int = 2) -> ClosedRange<Double>? {
        guard words.indices.contains(index) else { return nil }
        let length = max(1, min(words[index].alternativeLength ?? 1, words.count - index))
        let first = max(0, index - context)
        let last = min(words.count - 1, index + length - 1 + context)
        return words[first].start...max(words[first].start, words[last].end)
    }

    /// Var varje ord står i texten, hittat genom att söka orden i tur och ordning. `nil` för
    /// ord som inte hittas (t.ex. när texten har rättats).
    public static func wordRanges(_ words: [WordTimingData], in text: String) -> [Range<String.Index>?] {
        var cursor = text.startIndex
        return words.map { word in
            let needle = trimmed(word.word)
            guard !needle.isEmpty, let range = text.range(of: needle, range: cursor..<text.endIndex) else { return nil }
            cursor = range.upperBound
            return range
        }
    }
}

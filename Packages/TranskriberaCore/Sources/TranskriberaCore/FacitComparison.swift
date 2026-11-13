import Foundation

/// Testlabbet jämför en körning med ett facit, till exempel Klangs text för samma inspelning
/// (2026-11-13, Nicklas: "bygg in testerna i Testlabbet"). Det som räknas:
///
/// - hur stor del av facitets ord som körningen har (ordträff),
/// - ställen där körningen och facit skiljer sig i ett ord som ändrar innebörden ("inte", "bör" …),
/// - för körningar med "Markera ord att lyssna på": hur många markeringar som gällde ett riktigt fel
///   och hur många av innebördsfelen som blev markerade.
///
/// Facit är också en transkribering och har egna fel, så siffrorna är ungefärliga.
public enum FacitComparison {
    public struct Difference: Equatable, Sendable {
        public var time: Double
        /// Körningens ord på stället (tomt om körningen saknar orden).
        public var heard: String
        /// Facitets ord på stället (tomt om facit saknar orden).
        public var facit: String
        public var before: String
    }

    public struct MarkResult: Equatable, Sendable {
        public var mark: CrossCheck.Mark
        /// Sant när körningens ord skiljer sig från facit där markeringen sitter.
        public var isError: Bool
        /// Facitets ord på samma ställe.
        public var facit: String
    }

    public struct Result: Equatable, Sendable {
        public var words: Int
        public var facitWords: Int
        /// Andel av facitets ord som finns i körningen, i samma ordning (0–1).
        public var wordMatch: Double
        public var meaningErrors: [Difference]
        public var marks: [MarkResult]
        /// Innebördsfel som har en markering på sig.
        public var caught: Int
        /// Innebördsfel utan markering.
        public var missed: [Difference]
    }

    /// Orden i en facittext. Rader som bara är talare och tid ("Talare 2 - 0:04") hoppas över.
    public static func facitWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .filter { !isHeader(String($0)) }
            .flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
    }

    static func isHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .range(of: #"^.{1,60} - \d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil
    }

    public static func compare(_ segments: [SegmentData], facit: String) -> Result {
        // Körningens ord med tid och plats.
        struct Token { var segment: Int; var word: Int; var raw: String; var key: String; var time: Double }
        var mine: [Token] = []
        for (s, segment) in segments.enumerated() {
            // Utan ordtider (t.ex. Whisper utan talare) räknas texten, med styckets tid.
            let words = segment.words.isEmpty
                ? segment.text.split(whereSeparator: \.isWhitespace).map {
                    WordTimingData(word: String($0), start: segment.start, end: segment.end, probability: 1)
                }
                : segment.words
            for (w, word) in words.enumerated() {
                let key = CrossCheck.normalized(word.word)
                guard !key.isEmpty, !CrossCheck.fillers.contains(key) else { continue }
                mine.append(Token(segment: s, word: w, raw: word.word.trimmingCharacters(in: .whitespaces), key: key, time: word.start))
            }
        }
        let theirs = facitWords(facit).filter {
            let key = CrossCheck.normalized($0)
            return !key.isEmpty && !CrossCheck.fillers.contains(key)
        }
        let theirKeys = theirs.map(CrossCheck.normalized)
        let changes = CrossCheck.changes(old: theirKeys, new: mine.map(\.key))

        // Vilka av körningens ord som skiljer sig från facit. Saknas ord i körningen räknas
        // grannorden, så att en markering på grannordet (så som korskollen gör) träffar.
        var wrong = [Bool](repeating: false, count: mine.count)
        var errorSpans: [(span: Range<Int>, difference: Difference)] = []
        var changed = 0
        for change in changes {
            changed += change.old.count
            let span = neighbourhood(change.new, count: mine.count)
            for i in span { wrong[i] = true }
            let mineKeys = mine[change.new].map(\.key)
            let otherKeys = Array(theirKeys[change.old])
            guard CrossCheck.changesMeaning(mineKeys, otherKeys), !span.isEmpty else { continue }
            errorSpans.append((span, Difference(
                time: mine[span.lowerBound].time,
                heard: mine[change.new].map(\.raw).joined(separator: " "),
                facit: theirs[change.old].joined(separator: " "),
                before: mine[max(0, change.new.lowerBound - 6)..<change.new.lowerBound].map(\.raw).joined(separator: " ")
            )))
        }

        // Facitets ord som hör till körningens ord i, via orden som är lika runt omkring.
        var facitIndex = [Int?](repeating: nil, count: mine.count)
        do {
            var i = 0, j = 0
            for change in changes {
                while j < change.new.lowerBound { facitIndex[j] = i; i += 1; j += 1 }
                i = change.old.upperBound; j = change.new.upperBound
            }
            while j < mine.count, i < theirs.count { facitIndex[j] = i; i += 1; j += 1 }
        }
        func facitText(for span: Range<Int>) -> String {
            var lower = 0
            var k = span.lowerBound - 1
            while k >= 0 { if let f = facitIndex[k] { lower = f + 1; break }; k -= 1 }
            var upper = theirs.count
            k = span.upperBound
            while k < mine.count { if let f = facitIndex[k] { upper = f; break }; k += 1 }
            let inside = span.compactMap { facitIndex[$0] }
            if let first = inside.first { lower = min(lower, first) }
            if let last = inside.last { upper = max(upper, last + 1) }
            guard lower < upper else { return "" }
            return theirs[lower..<upper].joined(separator: " ")
        }

        // Markeringarna, som platser i körningens ordlista.
        var tokenAt: [[Int: Int]] = Array(repeating: [:], count: segments.count)
        for (index, token) in mine.enumerated() { tokenAt[token.segment][token.word] = index }
        var markSpans: [Range<Int>] = []
        var marks: [MarkResult] = []
        let listed = CrossCheck.marks(in: segments)
        var listedIndex = 0
        for (s, segment) in segments.enumerated() {
            for (w, word) in segment.words.enumerated() where word.alternative != nil {
                let length = max(1, word.alternativeLength ?? 1)
                // Samma ordning som `CrossCheck.marks`: en post per markerat ord.
                guard listedIndex < listed.count else { continue }
                let mark = listed[listedIndex]
                listedIndex += 1
                let indices = (w..<min(segment.words.count, w + length)).compactMap { tokenAt[s][$0] }
                guard let first = indices.min(), let last = indices.max() else {
                    marks.append(MarkResult(mark: mark, isError: false, facit: ""))
                    continue
                }
                let span = first..<last + 1
                markSpans.append(span)
                marks.append(MarkResult(mark: mark, isError: span.contains { wrong[$0] }, facit: facitText(for: span)))
            }
        }

        var missed: [Difference] = []
        var caught = 0
        for (span, difference) in errorSpans {
            if markSpans.contains(where: { $0.overlaps(span) }) { caught += 1 } else { missed.append(difference) }
        }
        let matched = theirKeys.count - changed
        return Result(
            words: mine.count,
            facitWords: theirKeys.count,
            wordMatch: theirKeys.isEmpty ? 0 : Double(max(0, matched)) / Double(theirKeys.count),
            meaningErrors: errorSpans.map { $0.difference },
            marks: marks,
            caught: caught,
            missed: missed
        )
    }

    /// Orden som ändringen gäller, eller grannorden när körningen saknar orden.
    private static func neighbourhood(_ span: Range<Int>, count: Int) -> Range<Int> {
        guard span.isEmpty else { return span }
        let lower = max(0, span.lowerBound - 1)
        let upper = min(count, span.lowerBound + 1)
        return lower..<max(lower, upper)
    }

    // MARK: - Text

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f", value * 100).replacingOccurrences(of: ".", with: ",") + " %"
    }

    /// Raden i den gemensamma sammanfattningen.
    public static func summaryLine(_ result: Result, title: String, minutes: Double) -> String {
        var line = "\(title): ordträff \(percent(result.wordMatch)), \(result.meaningErrors.count) innebördsfel"
        if !result.marks.isEmpty || result.caught > 0 {
            let right = result.marks.filter(\.isError).count
            let perHour = minutes > 0 ? Int((Double(result.marks.count) / minutes * 60).rounded()) : 0
            line += ", \(result.marks.count) markeringar (\(perHour) per timme), varav \(right) riktiga fel"
            line += ", \(result.caught) av \(result.meaningErrors.count) innebördsfel markerade"
        }
        return line
    }

    /// Hela jämförelsen för en körning: siffrorna, varje markering och de innebördsfel som inte markerades.
    public static func report(_ result: Result, title: String, facitName: String, minutes: Double,
                              anonymize: (String) -> String = { $0 }) -> String {
        var out = """
        Jämförelse med facit (\(facitName))
        \(summaryLine(result, title: title, minutes: minutes))
        Körningen har \(result.words) ord, facit \(result.facitWords). Facit har också fel, så siffrorna är ungefärliga.

        """
        if !result.marks.isEmpty {
            out += "\nMarkeringar (FEL = körningen skiljer sig från facit här, RÄTT = körningen och facit är lika):\n"
            for item in result.marks {
                let mark = item.mark
                out += "\(TimeFormatting.short(mark.time))  \(item.isError ? "FEL " : "RÄTT")  …\(mark.before) [\(mark.heard)] \(mark.after)…  markerat: \(mark.other)  facit: \(item.facit)\n"
            }
        }
        let list = result.marks.isEmpty && result.caught == 0 ? result.meaningErrors : result.missed
        if !list.isEmpty {
            out += result.marks.isEmpty && result.caught == 0
                ? "\nInnebördsfel (körningens ord inom [ ], facit efter):\n"
                : "\nInnebördsfel som inte markerades (körningens ord inom [ ], facit efter):\n"
            for difference in list {
                out += "\(TimeFormatting.short(difference.time))  …\(difference.before) [\(difference.heard)]  facit: \(difference.facit)\n"
            }
        }
        return anonymize(out)
    }
}

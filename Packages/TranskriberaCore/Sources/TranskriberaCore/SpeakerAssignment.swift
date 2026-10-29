import Foundation

/// En sammanhängande tid då en talare hörs, från talaridentifieringen.
public struct SpeakerTurn: Hashable, Sendable {
    public var start: Double
    public var end: Double
    /// Talarens nummer från talaridentifieringen (0, 1, 2 …).
    public var speaker: Int

    public init(start: Double, end: Double, speaker: Int) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// Kopplar ihop transkriberingens ord med talaridentifieringens turer.
///
/// Varje ord får den talare vars tur överlappar ordet mest, och segmenten delas där
/// talaren byts. Det gör att ett kort svar direkt efter en fråga ("Varje dag.") hamnar
/// hos rätt talare även när det inte finns någon paus mellan replikerna.
public enum SpeakerAssignment {
    /// En talarbit på högst så här många ord får bara stå för sig själv vid ett meningsslut
    /// eller en paus. Annars hör den till grannen: ordtiderna och talarturerna är sällan
    /// exakt i synk, så de sista orden i en replik hamnade ofta hos nästa talare.
    static let shortRunWords = 2
    /// Så lång tystnad mellan två ord räcker för ett talarbyte mitt i en mening.
    static let boundaryPause = 0.3
    /// En replik där mindre än så här stor del av ordens tid ligger i talarens egna turer
    /// markeras som osäker.
    static let minimumCoverage = 0.5
    /// Så länge (sekunder) måste två talares turer gå omlott under ett ord för att det ska
    /// räknas som att de pratar samtidigt.
    static let overlappingSpeech = 0.15

    /// Talare per ord och replik, med ⚠ (`uncertainSpeaker`) där tilldelningen är osäker:
    /// - talaren byts mitt i ett segment från taligenkänningen,
    /// - ett ord har flyttats till en annan talare än den vars tur det låg i (utjämningen),
    /// - mindre än hälften av replikens ord ligger i talarens egna turer (t.ex. i en lucka),
    /// - två talare hörs samtidigt.

    public static func assign(_ segments: [SegmentData], turns: [SpeakerTurn]) -> [SegmentData] {
        let turns = turns.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !turns.isEmpty else { return segments }

        var names: [Int: String] = [:]
        func name(for speaker: Int?) -> String? {
            guard let speaker else { return nil }
            if let existing = names[speaker] { return existing }
            let new = "Talare \(names.count + 1)"
            names[speaker] = new
            return new
        }

        // Talare per ord, segment för segment.
        let segments = segments.sorted(by: { $0.start < $1.start })
        var wordSpeakers: [[Int?]] = []
        /// Talaren enligt turerna, innan utjämningen.
        var rawSpeakers: [[Int?]] = []
        var segmentSpeakers: [Int?] = []
        for segment in segments {
            guard !segment.words.isEmpty else {
                segmentSpeakers.append(bestSpeaker(start: segment.start, end: segment.end, turns: turns))
                wordSpeakers.append([])
                rawSpeakers.append([])
                continue
            }

            let measured = segment.words.map { bestSpeaker(start: $0.start, end: $0.end, turns: turns) }
            rawSpeakers.append(measured)
            var speakers = measured
            // Ett ensamt ord mitt i en annan talares mening beror nästan alltid på
            // ungefärliga ordtider, inte på ett talarbyte.
            if speakers.count >= 3 {
                for index in 1..<(speakers.count - 1)
                where speakers[index - 1] == speakers[index + 1] && speakers[index] != speakers[index - 1] {
                    speakers[index] = speakers[index - 1]
                }
            }
            segmentSpeakers.append(nil)
            wordSpeakers.append(speakers)
        }

        // Korta talarbitar följer grannen över hela ordflödet, inte bara inom ett segment:
        // en mening som fortsätter i nästa segment ("Det står Claude / hos dig.") ska inte
        // delas mellan två talare.
        let snapped = snapToBoundaries(segments.flatMap(\.words), wordSpeakers.flatMap { $0 })
        var offset = 0
        for index in wordSpeakers.indices {
            let count = wordSpeakers[index].count
            wordSpeakers[index] = Array(snapped[offset..<(offset + count)])
            offset += count
        }

        var result: [SegmentData] = []
        for (position, segment) in segments.enumerated() {
            guard !segment.words.isEmpty else {
                var output = segment
                output.speaker = name(for: segmentSpeakers[position])
                if let speaker = segmentSpeakers[position] {
                    output.uncertainSpeaker = coverage(start: segment.start, end: segment.end, speaker: speaker, turns: turns)
                        < minimumCoverage
                }
                result.append(output)
                continue
            }
            let speakers = wordSpeakers[position]
            let measured = rawSpeakers[position]

            // Dela segmentet där talaren byts.
            var startIndex = 0
            for index in 1...segment.words.count {
                let isEnd = index == segment.words.count
                guard isEnd || speakers[index] != speakers[startIndex] else { continue }
                var words = Array(segment.words[startIndex..<index])
                let text = TextCleaning.clean(words.map(\.word).joined())
                if !text.isEmpty {
                    let isWhole = startIndex == 0 && isEnd
                    let speaker = speakers[startIndex]
                    let uncertain = !isWhole
                        || (startIndex..<index).contains { measured[$0] != speakers[$0] }
                        || isPoorlyCovered(words, speaker: speaker, turns: turns)
                        || words.contains { hasOverlappingSpeech(start: $0.start, end: $0.end, turns: turns) }
                    if uncertain {
                        for word in words.indices { words[word].uncertainSpeaker = true }
                    }
                    result.append(SegmentData(
                        start: isWhole ? segment.start : words[0].start,
                        end: isWhole ? segment.end : words[words.count - 1].end,
                        text: isWhole ? segment.text : text,
                        speaker: name(for: speaker),
                        words: words,
                        uncertainSpeaker: uncertain
                    ))
                }
                startIndex = index
            }
        }
        return result
    }

    /// Flyttar korta talarbitar (högst `shortRunWords` ord) till grannen när bytet inte
    /// sker vid ett meningsslut eller en paus, t.ex. "…siffror helt / enkelt." eller
    /// "Överkurs / för mig.".
    static func snapToBoundaries(_ words: [WordTimingData], _ speakers: [Int?]) -> [Int?] {
        var speakers = speakers
        while true {
            let runs = runs(of: speakers, words: words)
            guard runs.count > 1 else { return speakers }
            var merged = false
            for (index, run) in runs.enumerated() where run.count <= shortRunWords {
                let previous = index > 0 && !isBoundary(words, before: run.lowerBound) ? runs[index - 1] : nil
                let next = index < runs.count - 1 && !isBoundary(words, before: run.upperBound) ? runs[index + 1] : nil
                let target: Range<Int>?
                if let previous, let next {
                    target = previous.count >= next.count ? previous : next
                } else {
                    target = previous ?? next
                }
                guard let target else { continue }
                let speaker = speakers[target.lowerBound]
                for position in run { speakers[position] = speaker }
                merged = true
                break
            }
            if !merged { return speakers }
        }
    }

    /// Följder av ord med samma talare. En följd bryts också vid meningsslut och pauser, så
    /// att "Okej? / Jag skulle" inte räknas som en lång bit bara för att talaren är densamma.
    static func runs(of speakers: [Int?], words: [WordTimingData]) -> [Range<Int>] {
        guard !speakers.isEmpty else { return [] }
        var runs: [Range<Int>] = []
        var start = 0
        for index in 1...speakers.count
        where index == speakers.count || speakers[index] != speakers[start] || isBoundary(words, before: index) {
            runs.append(start..<index)
            start = index
        }
        return runs
    }

    /// Sant om ett talarbyte före ordet på `index` är rimligt: föregående ord avslutar en
    /// mening eller det är en paus emellan.
    static func isBoundary(_ words: [WordTimingData], before index: Int) -> Bool {
        guard index > 0, index < words.count else { return true }
        let previous = words[index - 1].word.trimmingCharacters(in: .whitespaces)
        if let last = previous.last, ".?!…".contains(last) { return true }
        return words[index].start - words[index - 1].end >= boundaryPause
    }

    /// Andel av tiden mellan `start` och `end` som ligger i talarens egna turer.
    static func coverage(start: Double, end: Double, speaker: Int, turns: [SpeakerTurn]) -> Double {
        guard end > start else { return 1 }
        let covered = turns.lazy.filter { $0.speaker == speaker }
            .map { max(0, min(end, $0.end) - max(start, $0.start)) }
            .reduce(0, +)
        return min(1, covered / (end - start))
    }

    static func isPoorlyCovered(_ words: [WordTimingData], speaker: Int?, turns: [SpeakerTurn]) -> Bool {
        guard let speaker else { return true }
        let total = words.reduce(0) { $0 + max(0, $1.end - $1.start) }
        guard total > 0 else { return false }
        let covered = words.reduce(0) { sum, word in
            sum + coverage(start: word.start, end: word.end, speaker: speaker, turns: turns) * max(0, word.end - word.start)
        }
        return covered / total < minimumCoverage
    }

    /// Sant om två talares turer går omlott under ordet. Händer bara när
    /// talaridentifieringen tillåter samtidigt tal.
    static func hasOverlappingSpeech(start: Double, end: Double, turns: [SpeakerTurn]) -> Bool {
        let active = turns.filter { $0.start < end && $0.end > start }
        for (index, first) in active.enumerated() {
            for second in active[(index + 1)...] where second.speaker != first.speaker {
                let shared = min(end, first.end, second.end) - max(start, first.start, second.start)
                if shared >= min(overlappingSpeech, (end - start) * 0.5) && shared > 0 { return true }
            }
        }
        return false
    }

    /// Talaren med störst överlapp, eller närmaste tur om inget överlappar.
    ///
    /// Ett ord i en lucka mellan två turer får alltid närmaste tur. Tidigare fick ord långt
    /// från alla turer föregående ords talare, och efter en fråga är det intervjuaren: ett
    /// kort svar som diariseringen missat hamnade då hos den som frågade.
    static func bestSpeaker(start: Double, end: Double, turns: [SpeakerTurn]) -> Int? {
        var overlap: [Int: Double] = [:]
        for turn in turns {
            if turn.start >= end { break }
            let shared = min(end, turn.end) - max(start, turn.start)
            if shared > 0 { overlap[turn.speaker, default: 0] += shared }
        }
        if let best = overlap.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) {
            return best.key
        }

        let middle = (start + end) / 2
        return turns.min { distance(middle, $0) < distance(middle, $1) }?.speaker
    }

    private static func distance(_ time: Double, _ turn: SpeakerTurn) -> Double {
        if time < turn.start { return turn.start - time }
        if time > turn.end { return time - turn.end }
        return 0
    }
}

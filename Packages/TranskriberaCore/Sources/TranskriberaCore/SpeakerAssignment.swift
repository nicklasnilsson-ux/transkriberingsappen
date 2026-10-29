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
    /// Ord utan överlapp får närmaste tur inom så här många sekunder, annars föregående ords talare.
    static let nearestTurnTolerance = 0.5
    /// En talarbit på högst så här många ord får bara stå för sig själv vid ett meningsslut
    /// eller en paus. Annars hör den till grannen: ordtiderna och talarturerna är sällan
    /// exakt i synk, så de sista orden i en replik hamnade ofta hos nästa talare.
    static let shortRunWords = 2
    /// Så lång tystnad mellan två ord räcker för ett talarbyte mitt i en mening.
    static let boundaryPause = 0.3

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

        var previous: Int?
        var result: [SegmentData] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            guard !segment.words.isEmpty else {
                let speaker = bestSpeaker(start: segment.start, end: segment.end, turns: turns) ?? previous
                previous = speaker
                var output = segment
                output.speaker = name(for: speaker)
                result.append(output)
                continue
            }

            // Talare per ord.
            var speakers: [Int?] = []
            for word in segment.words {
                let speaker = bestSpeaker(start: word.start, end: word.end, turns: turns) ?? previous
                speakers.append(speaker)
                previous = speaker
            }
            // Ett ensamt ord mitt i en annan talares mening beror nästan alltid på
            // ungefärliga ordtider, inte på ett talarbyte.
            if speakers.count >= 3 {
                for index in 1..<(speakers.count - 1)
                where speakers[index - 1] == speakers[index + 1] && speakers[index] != speakers[index - 1] {
                    speakers[index] = speakers[index - 1]
                }
            }

            speakers = snapToBoundaries(segment.words, speakers)

            // Dela segmentet där talaren byts.
            var startIndex = 0
            for index in 1...segment.words.count {
                let isEnd = index == segment.words.count
                guard isEnd || speakers[index] != speakers[startIndex] else { continue }
                let words = Array(segment.words[startIndex..<index])
                let text = TextCleaning.clean(words.map(\.word).joined())
                if !text.isEmpty {
                    let isWhole = startIndex == 0 && isEnd
                    result.append(SegmentData(
                        start: isWhole ? segment.start : words[0].start,
                        end: isWhole ? segment.end : words[words.count - 1].end,
                        text: isWhole ? segment.text : text,
                        speaker: name(for: speakers[startIndex]),
                        words: words
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
            let runs = runs(of: speakers)
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

    /// Följder av ord med samma talare.
    static func runs(of speakers: [Int?]) -> [Range<Int>] {
        guard !speakers.isEmpty else { return [] }
        var runs: [Range<Int>] = []
        var start = 0
        for index in 1...speakers.count where index == speakers.count || speakers[index] != speakers[start] {
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

    /// Talaren med störst överlapp, eller närmaste tur om inget överlappar.
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
        let nearest = turns.min { distance(middle, $0) < distance(middle, $1) }
        guard let nearest, distance(middle, nearest) <= nearestTurnTolerance else { return nil }
        return nearest.speaker
    }

    private static func distance(_ time: Double, _ turn: SpeakerTurn) -> Double {
        if time < turn.start { return turn.start - time }
        if time > turn.end { return time - turn.end }
        return 0
    }
}

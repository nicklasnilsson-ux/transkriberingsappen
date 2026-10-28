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

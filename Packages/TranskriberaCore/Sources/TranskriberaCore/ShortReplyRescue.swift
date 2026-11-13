import Foundation

/// Experiment "Fånga korta svar": hela ljudet transkriberas som vanligt, och efteråt letas
/// korta turer upp där talaridentifieringen hör någon, men där texten saknar den personens ord
/// ("Ja.", "Mm.", "Tack."). Bara de bitarna transkriberas för sig och läggs in som egna
/// repliker.
///
/// Bakgrund: på mötet 2026-11-12 hade Pianissimo 9 korta svar mot Klangs 44. "Talare först"
/// (varje replik för sig) gav fler korta svar men klippte meningar mellan talare och gav nya
/// hörfel, eftersom modellen fick för lite sammanhang. Här rörs den vanliga texten inte;
/// den får bara nya korta repliker insatta.
public enum ShortReplyRescue {
    /// Turer kortare än så här är oftast brus, längre är inte korta svar.
    static let shortestTurn = 0.2
    static let longestTurn = 2.5
    /// Ett räddat svar med fler ord än så här har troligen fått med grannens tal.
    static let mostWords = 5
    /// Så mycket ljud (sekunder) tas med före och efter turen när den transkriberas.
    public static let margin = 0.15
    /// Ord i texten inom så här många sekunder från turen räknas som "redan där".
    static let nearby = 1.0
    /// Högst så många bitar transkriberas om, så att ett mycket långt möte inte drar iväg.
    public static let mostCandidates = 400

    /// En kort tur vars ord saknas i texten.
    public struct Candidate: Hashable, Sendable {
        public var turn: SpeakerTurn
        public var clipStart: Double
        public var clipEnd: Double
    }

    /// Korta turer där turens talare inte har några ord i `segments`. `segments` ska ha
    /// talare från `SpeakerAssignment.assign` med samma `turns`.
    public static func candidates(segments: [SegmentData], turns: [SpeakerTurn], duration: Double) -> [Candidate] {
        let turns = turns.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        let names = speakerNames(segments: segments, turns: turns)
        var result: [Candidate] = []
        for turn in turns {
            let length = turn.end - turn.start
            guard length >= shortestTurn, length <= longestTurn else { continue }
            let own = names[turn.speaker]
            let hasOwnWords = segments.contains { segment in
                own != nil && segment.speaker == own && segment.words.contains { word in
                    let middle = (word.start + word.end) / 2
                    return middle >= turn.start - 0.1 && middle <= turn.end + 0.1
                }
            }
            guard !hasOwnWords else { continue }
            result.append(Candidate(
                turn: turn,
                clipStart: max(0, turn.start - margin),
                clipEnd: min(duration, turn.end + margin)
            ))
        }
        return Array(result.prefix(mostCandidates))
    }

    /// Lägger in de räddade svaren. `rescued` är orden som kom ur varje kandidats bit, med
    /// tider från början av ljudet. Ett svar läggs in efter meningen det hördes i, så att
    /// den som pratade inte klipps mitt i en mening. Svar som redan står i texten, är tomma
    /// eller är för långa hoppas över.
    public static func insert(
        _ rescued: [(turn: SpeakerTurn, words: [WordTimingData])],
        into segments: [SegmentData],
        turns: [SpeakerTurn]
    ) -> [SegmentData] {
        insertCounting(rescued, into: segments, turns: turns).segments
    }

    /// Som `insert`, och hur många svar som lades in.
    public static func insertCounting(
        _ rescued: [(turn: SpeakerTurn, words: [WordTimingData])],
        into segments: [SegmentData],
        turns: [SpeakerTurn]
    ) -> (segments: [SegmentData], added: Int) {
        var added = 0
        let sortedTurns = turns.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var names = speakerNames(segments: segments, turns: sortedTurns)
        var used = Set(segments.compactMap(\.speaker))
        var result = segments
        for (turn, words) in rescued.sorted(by: { $0.turn.start < $1.turn.start }) {
            let inside = words
                .filter { !TextCleaning.clean($0.word).isEmpty }
                .filter {
                    let middle = ($0.start + $0.end) / 2
                    return middle >= turn.start - margin - 0.1 && middle <= turn.end + margin + 0.1
                }
                .sorted { $0.start < $1.start }
            guard !inside.isEmpty, inside.count <= mostWords else { continue }
            let text = TextCleaning.clean(inside.map(\.word).joined())
            guard !text.isEmpty, !TextCleaning.isNonSpeechMarker(text) else { continue }

            // Står orden redan i texten nära turen är det troligen grannens ord: hoppa över.
            let existing = Set(result.flatMap(\.words).filter {
                $0.end >= turn.start - nearby && $0.start <= turn.end + nearby
            }.map { normalized($0.word) })
            if inside.allSatisfy({ existing.contains(normalized($0.word)) }) { continue }

            let name: String
            if let known = names[turn.speaker] {
                name = known
            } else {
                var number = used.count + 1
                while used.contains("Talare \(number)") { number += 1 }
                name = "Talare \(number)"
                names[turn.speaker] = name
            }
            used.insert(name)

            var reply = SegmentData(
                start: inside[0].start,
                end: inside[inside.count - 1].end,
                text: text,
                speaker: name,
                words: inside,
                uncertainSpeaker: SpeakerAssignment.hasOverlappingSpeech(start: turn.start, end: turn.end, turns: sortedTurns)
            )
            if reply.uncertainSpeaker {
                for index in reply.words.indices { reply.words[index].uncertainSpeaker = true }
            }
            insertReply(reply, into: &result)
            added += 1
        }
        return (result, added)
    }

    /// Lägger `reply` efter meningen som pågår när svaret börjar. Pågår ingen mening läggs
    /// svaret in i tidsordning.
    static func insertReply(_ reply: SegmentData, into segments: inout [SegmentData]) {
        guard let host = segments.lastIndex(where: { $0.start <= reply.start }) else {
            segments.insert(reply, at: 0)
            return
        }
        let words = segments[host].words
        // Meningen slutar vid första ord efter svaret som avslutar en mening, eller före
        // en paus. Finns inget sådant ord står svaret efter hela segmentet.
        if let cut = words.indices.first(where: { index in
            words[index].end >= reply.start && endsSentence(words, at: index)
        }), cut < words.count - 1 {
            var first = segments[host]
            var second = segments[host]
            first.words = Array(words[...cut])
            second.words = Array(words[(cut + 1)...])
            first.text = TextCleaning.clean(first.words.map(\.word).joined())
            second.text = TextCleaning.clean(second.words.map(\.word).joined())
            first.end = first.words[first.words.count - 1].end
            second.start = second.words[0].start
            var after = reply
            // Starttiderna ska fortsätta vara i ordning.
            after.start = min(reply.start, second.start)
            segments.replaceSubrange(host...host, with: [first, after, second])
        } else {
            segments.insert(reply, at: host + 1)
        }
    }

    static func endsSentence(_ words: [WordTimingData], at index: Int) -> Bool {
        let trimmed = words[index].word.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, ".?!…".contains(last) { return true }
        return index + 1 < words.count && words[index + 1].start - words[index].end >= 0.3
    }

    /// Vilket namn ("Talare 1" …) varje talarnummer fick, efter hur orden fördelades.
    static func speakerNames(segments: [SegmentData], turns: [SpeakerTurn]) -> [Int: String] {
        var votes: [Int: [String: Int]] = [:]
        for segment in segments {
            guard let name = segment.speaker else { continue }
            for word in segment.words {
                guard let speaker = SpeakerAssignment.bestSpeaker(start: word.start, end: word.end, turns: turns) else { continue }
                votes[speaker, default: [:]][name, default: 0] += 1
            }
        }
        let pairs = votes.flatMap { speaker, names in names.map { (speaker, $0.key, $0.value) } }
            .sorted { ($0.2, $1.0, $1.1) > ($1.2, $0.0, $0.1) }
        var result: [Int: String] = [:]
        var taken = Set<String>()
        for (speaker, name, _) in pairs where result[speaker] == nil && !taken.contains(name) {
            result[speaker] = name
            taken.insert(name)
        }
        return result
    }

    static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

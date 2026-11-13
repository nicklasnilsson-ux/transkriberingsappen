import Foundation

/// Ett stycke av ljudet som transkriberas för sig, med talaren som hörs där.
public struct ReplyPiece: Hashable, Sendable {
    public var start: Double
    public var end: Double
    /// Talaren enligt talaridentifieringen, eller `nil` när ingen talare hördes (en lucka
    /// som ändå transkriberas, så att inget tal tappas).
    public var speaker: Int?
    /// Sant när två talare hördes samtidigt någonstans i stycket.
    public var overlapped: Bool

    public init(start: Double, end: Double, speaker: Int?, overlapped: Bool = false) {
        self.start = start
        self.end = end
        self.speaker = speaker
        self.overlapped = overlapped
    }

    public var duration: Double { end - start }
}

/// Ljudet delas i repliker efter talaridentifieringen, så att varje replik kan transkriberas
/// för sig. En mening som fortsätter över en bitgräns klipps där.
///
/// Används av experimentet "Korskolla" (`CrossCheck`): Pianissimo lyssnar en gång till på
/// ljudet i repliker. Som egen text var det sämre ("Talare först", mötet 2026-11-12: fler
/// talarbyten mitt i meningar), men eftersom bitarna skiljer sig från den vanliga körningen
/// skiljer sig också felen, och där körningarna inte är överens finns ofta ett fel.
public enum ReplyPlan {
    /// Två bitar av samma talare med kortare tystnad än så här emellan blir en replik.
    static let mergeGap = 1.0
    /// Kortare luckor utan talare delas mellan grannarna i stället för att bli egna bitar.
    static let shortestGap = 0.5
    /// Kortare talarbitar än så här (oftast skärvor av samtidigt tal) går till grannen.
    static let shortestPiece = 0.15
    /// Så långt (sekunder) måste en annan talares tur fortsätta på båda sidor om ett inpass
    /// för att inpasset ska räknas som inbäddat i den repliken.
    static let embeddedMargin = 0.5

    /// Repliker som täcker hela ljudet (0 till `duration`) utan glapp och utan överlapp,
    /// i tidsordning.
    ///
    /// När två talare hörs samtidigt vid ett talarbyte får den kortare turen tiden, så att ett
    /// kort svar direkt efter en fråga får egen plats. Ett inpass mitt i någon annans replik
    /// stannar i den repliken.
    public static func pieces(turns: [SpeakerTurn], duration: Double) -> [ReplyPiece] {
        guard duration > 0 else { return [] }
        let turns = turns
            .map { SpeakerTurn(start: max(0, $0.start), end: min(duration, $0.end), speaker: $0.speaker) }
            .filter { $0.end > $0.start }
        guard !turns.isEmpty else { return [ReplyPiece(start: 0, end: duration, speaker: nil)] }

        // 1. Dela tidslinjen vid varje turs start och slut, och välj talare per del.
        let cuts = Array(Set([0, duration] + turns.flatMap { [$0.start, $0.end] })).sorted()
        var pieces: [ReplyPiece] = []
        for (start, end) in zip(cuts, cuts.dropFirst()) where end > start {
            let active = turns.filter { $0.start < end && $0.end > start }
            // Ett inpass som ligger helt inne i någon annans replik delar den inte: då skulle
            // repliken klippas mitt i en mening. Inpasset hörs ändå i den långa biten.
            let candidates = active.filter { turn in
                !active.contains { other in
                    other.speaker != turn.speaker
                        && other.start <= turn.start - embeddedMargin
                        && other.end >= turn.end + embeddedMargin
                }
            }
            let contenders = candidates.isEmpty ? active : candidates
            let winner = contenders.min {
                ($0.end - $0.start, $0.speaker) < ($1.end - $1.start, $1.speaker)
            }
            // Ett inbäddat inpass gör inte den långa repliken osäker.
            let overlapped = Set(contenders.map(\.speaker)).count > 1
            pieces.append(ReplyPiece(start: start, end: end, speaker: winner?.speaker, overlapped: overlapped))
        }

        // 2. Slå ihop och städa tills inget ändras.
        var changed = true
        while changed {
            changed = false
            pieces = mergeNeighbours(pieces)
            if let merged = bridgeShortSilence(pieces) { pieces = merged; changed = true; continue }
            if let merged = absorbShortGaps(pieces) { pieces = merged; changed = true; continue }
            if let merged = absorbSlivers(pieces) { pieces = merged; changed = true; continue }
        }
        return pieces
    }

    /// Grannar med samma talare (eller båda utan talare) blir en bit.
    static func mergeNeighbours(_ pieces: [ReplyPiece]) -> [ReplyPiece] {
        var result: [ReplyPiece] = []
        for piece in pieces {
            if var last = result.last, last.speaker == piece.speaker {
                last.end = piece.end
                last.overlapped = last.overlapped || piece.overlapped
                result[result.count - 1] = last
            } else {
                result.append(piece)
            }
        }
        return result
    }

    /// Talare A, kort tystnad, talare A blir en replik.
    static func bridgeShortSilence(_ pieces: [ReplyPiece]) -> [ReplyPiece]? {
        guard pieces.count >= 3 else { return nil }
        for index in 1..<(pieces.count - 1) {
            let gap = pieces[index]
            guard gap.speaker == nil, gap.duration < mergeGap,
                  let speaker = pieces[index - 1].speaker, pieces[index + 1].speaker == speaker else { continue }
            var result = pieces
            result[index].speaker = speaker
            return mergeNeighbours(result)
        }
        return nil
    }

    /// En kort lucka utan talare delas mitt itu mellan grannarna (eller går helt till den
    /// enda grannen i början och slutet).
    static func absorbShortGaps(_ pieces: [ReplyPiece]) -> [ReplyPiece]? {
        guard pieces.count >= 2 else { return nil }
        for (index, gap) in pieces.enumerated() where gap.speaker == nil && gap.duration < shortestGap {
            var result = pieces
            let hasPrevious = index > 0, hasNext = index < pieces.count - 1
            if hasPrevious && hasNext {
                let middle = (gap.start + gap.end) / 2
                result[index - 1].end = middle
                result[index + 1].start = middle
            } else if hasPrevious {
                result[index - 1].end = gap.end
            } else {
                result[index + 1].start = gap.start
            }
            result.remove(at: index)
            return result
        }
        return nil
    }

    /// En mycket kort talarbit går till den längre grannen och markeras som osäker.
    static func absorbSlivers(_ pieces: [ReplyPiece]) -> [ReplyPiece]? {
        guard pieces.count >= 2 else { return nil }
        for (index, piece) in pieces.enumerated() where piece.speaker != nil && piece.duration < shortestPiece {
            var result = pieces
            let previous = index > 0 ? pieces[index - 1] : nil
            let next = index < pieces.count - 1 ? pieces[index + 1] : nil
            let toPrevious: Bool
            switch (previous, next) {
            case let (previous?, next?): toPrevious = previous.duration >= next.duration
            case (_?, nil): toPrevious = true
            default: toPrevious = false
            }
            if toPrevious {
                result[index - 1].end = piece.end
                result[index - 1].overlapped = true
            } else {
                result[index + 1].start = piece.start
                result[index + 1].overlapped = true
            }
            result.remove(at: index)
            return result
        }
        return nil
    }

    /// Segment med talare av varje bits ord. `words[i]` är orden i `pieces[i]`, med tider
    /// från början av ljudet. Talarna numreras ("Talare 1", "Talare 2" …) i den ordning de
    /// först säger något, som i `SpeakerAssignment`.
    ///
    /// En bit utan talare får närmaste turs talare och ⚠, liksom en bit där två talare hördes
    /// samtidigt.
    public static func segments(pieces: [ReplyPiece], words: [[WordTimingData]], turns: [SpeakerTurn]) -> [SegmentData] {
        let turns = turns.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var names: [Int: String] = [:]
        var result: [SegmentData] = []
        for (piece, pieceWords) in zip(pieces, words) {
            let inside = pieceWords
                .filter { ($0.start + $0.end) / 2 >= piece.start - 0.05 && ($0.start + $0.end) / 2 <= piece.end + 0.05 }
                .sorted { $0.start < $1.start }
            guard !inside.isEmpty else { continue }
            let speaker = piece.speaker
                ?? SpeakerAssignment.bestSpeaker(start: inside[0].start, end: inside[inside.count - 1].end, turns: turns)
            let uncertain = piece.speaker == nil || piece.overlapped
            var name: String?
            if let speaker {
                if names[speaker] == nil { names[speaker] = "Talare \(names.count + 1)" }
                name = names[speaker]
            }
            for var segment in SentenceSegmenter.segments(from: inside) {
                segment.speaker = name
                segment.uncertainSpeaker = uncertain
                if uncertain {
                    for index in segment.words.indices { segment.words[index].uncertainSpeaker = true }
                }
                result.append(segment)
            }
        }
        return result
    }
}

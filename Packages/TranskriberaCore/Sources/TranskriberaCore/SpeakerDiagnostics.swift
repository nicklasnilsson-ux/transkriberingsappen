import Foundation

/// Talaridentifierarens turer och vad appen gjorde av dem, för felsökning. Filen innehåller
/// bara tider och talarnummer, inte ett enda ord ur samtalet, så den går att skicka vidare.
public struct SpeakerDiagnostics: Codable, Equatable, Sendable {
    public struct Turn: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var speaker: Int
    }

    /// En replik efter tilldelningen: vem som fick den och när varje ord sägs.
    public struct Piece: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var speaker: String?
        public var uncertain: Bool
        /// Start och slut för varje ord, utan orden.
        public var words: [[Double]]
    }

    public var diarizer: String
    public var speakers: String
    public var turns: [Turn]
    public var pieces: [Piece]

    public init(diarizer: String, speakers: String, turns: [SpeakerTurn], segments: [SegmentData]) {
        self.diarizer = diarizer
        self.speakers = speakers
        self.turns = turns.sorted { $0.start < $1.start }
            .map { Turn(start: Self.rounded($0.start), end: Self.rounded($0.end), speaker: $0.speaker) }
        self.pieces = segments.map { segment in
            Piece(
                start: Self.rounded(segment.start),
                end: Self.rounded(segment.end),
                speaker: segment.speaker,
                uncertain: segment.uncertainSpeaker,
                words: segment.words.map { [Self.rounded($0.start), Self.rounded($0.end)] }
            )
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    private static func rounded(_ seconds: Double) -> Double {
        (seconds * 100).rounded() / 100
    }
}

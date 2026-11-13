import Foundation

/// Ett ord med tidsstämpel (sekunder från början av mediet).
public struct WordTimingData: Codable, Hashable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double
    public var probability: Double
    /// Sant när det är osäkert vem som sa ordet (se `SpeakerAssignment`). Sparas med
    /// ordtiderna; saknas i äldre transkriberingar.
    public var uncertainSpeaker: Bool?
    /// Experiment "Korskolla med KB Large" (`CrossCheck`): vad den andra modellen hörde här.
    /// Gäller det här ordet och `alternativeLength - 1` ord till. Saknas oftast.
    public var alternative: String?
    public var alternativeLength: Int?

    public init(
        word: String, start: Double, end: Double, probability: Double, uncertainSpeaker: Bool? = nil,
        alternative: String? = nil, alternativeLength: Int? = nil
    ) {
        self.word = word
        self.start = start
        self.end = end
        self.probability = probability
        self.uncertainSpeaker = uncertainSpeaker
        self.alternative = alternative
        self.alternativeLength = alternativeLength
    }
}

extension WordTimingData {
    /// Sant om JSON-kodade ord (som de sparas i databasen) har ett ord med osäker talare.
    /// Snabbare än att avkoda orden, så att listan kan visa ⚠ utan att bli trög.
    public static func hasUncertainSpeaker(inEncoded data: Data) -> Bool {
        data.range(of: Data(#""uncertainSpeaker":true"#.utf8)) != nil
    }

    /// Hur många ord i JSON-kodade ord (som de sparas) som har en annan tolkning (`CrossCheck`).
    /// Snabbare än att avkoda orden, så att listan bara avkodar segment som har några.
    public static func alternativeCount(inEncoded data: Data) -> Int {
        let needle = Data(#""alternative":"#.utf8)
        var count = 0
        var start = data.startIndex
        while let range = data.range(of: needle, in: start..<data.endIndex) {
            count += 1
            start = range.upperBound
        }
        return count
    }
}

/// Värdetyp för ett segment, oberoende av lagringen (SwiftData) i appen.
public struct SegmentData: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    public var words: [WordTimingData]
    /// Sant när det är osäkert vem som sa repliken. Visas som ⚠ så att ett korrekturpass
    /// vet var det ska titta. Ligger kvar även när anonymiseringen tar bort ordtiderna.
    public var uncertainSpeaker: Bool

    public init(
        start: Double,
        end: Double,
        text: String,
        speaker: String? = nil,
        words: [WordTimingData] = [],
        uncertainSpeaker: Bool = false
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.words = words
        self.uncertainSpeaker = uncertainSpeaker
    }
}

/// Metadata som följer med vid export.
public struct TranscriptMetadata: Sendable {
    public var title: String
    public var createdAt: Date
    public var duration: Double
    public var language: String?
    public var model: String?

    public init(title: String, createdAt: Date, duration: Double, language: String? = nil, model: String? = nil) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.language = language
        self.model = model
    }
}

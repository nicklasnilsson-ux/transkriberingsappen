import Foundation

/// Ett ord med tidsstämpel (sekunder från början av mediet).
public struct WordTimingData: Codable, Hashable, Sendable {
    public var word: String
    public var start: Double
    public var end: Double
    public var probability: Double

    public init(word: String, start: Double, end: Double, probability: Double) {
        self.word = word
        self.start = start
        self.end = end
        self.probability = probability
    }
}

/// Värdetyp för ett segment, oberoende av lagringen (SwiftData) i appen.
public struct SegmentData: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    public var words: [WordTimingData]

    public init(start: Double, end: Double, text: String, speaker: String? = nil, words: [WordTimingData] = []) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.words = words
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

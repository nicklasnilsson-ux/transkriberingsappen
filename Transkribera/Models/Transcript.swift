import Foundation
import SwiftData
import TranskriberaCore

enum TranscriptStatus: String, Codable {
    case queued
    case transcribing
    case completed
    case failed
}

/// En transkribering av en ljud- eller videofil.
@Model
final class Transcript {
    var id: UUID
    var title: String
    var createdAt: Date
    /// Filnamn inuti appens mediamapp (se `MediaStore`).
    var mediaFileName: String
    var originalFileName: String
    var isVideo: Bool
    var duration: Double
    /// Språkkod som Whisper använde/upptäckte, t.ex. "sv".
    var language: String?
    var modelName: String
    var statusRaw: String
    var errorMessage: String?
    var isRecording: Bool

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.transcript)
    var segments: [TranscriptSegment] = []

    init(
        title: String,
        mediaFileName: String,
        originalFileName: String,
        isVideo: Bool,
        duration: Double,
        modelName: String,
        isRecording: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.mediaFileName = mediaFileName
        self.originalFileName = originalFileName
        self.isVideo = isVideo
        self.duration = duration
        self.modelName = modelName
        self.statusRaw = TranscriptStatus.queued.rawValue
        self.isRecording = isRecording
    }

    var status: TranscriptStatus {
        get { TranscriptStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var mediaURL: URL { MediaStore.url(for: mediaFileName) }

    var sortedSegments: [TranscriptSegment] {
        segments.sorted { $0.index < $1.index }
    }

    var segmentData: [SegmentData] {
        sortedSegments.map(\.data)
    }

    var metadata: TranscriptMetadata {
        TranscriptMetadata(
            title: title,
            createdAt: createdAt,
            duration: duration,
            language: language.map(Language.displayName(for:)),
            model: modelName
        )
    }

    var fullText: String {
        TranscriptExporter.fullText(segmentData)
    }

    /// Alla unika talare i ordning de först förekommer.
    var speakers: [String] {
        var seen = Set<String>()
        return sortedSegments.compactMap(\.speaker).filter { seen.insert($0).inserted }
    }

    /// Ersätter alla segment med nya.
    func replaceSegments(with data: [SegmentData], in context: ModelContext) {
        for segment in segments {
            context.delete(segment)
        }
        segments = data.enumerated().map { index, item in
            let segment = TranscriptSegment(index: index, data: item)
            context.insert(segment)
            return segment
        }
    }

    func renameSpeaker(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for segment in segments where segment.speaker == oldName {
            segment.speaker = trimmed
        }
    }
}

/// Ett segment (ungefär en mening) med tidsstämplar och ev. talare.
@Model
final class TranscriptSegment {
    var index: Int
    var start: Double
    var end: Double
    var text: String
    var speaker: String?
    /// Ordtidsstämplar, JSON-kodade (stabilare i SwiftData än arrayer av structar).
    var wordsData: Data?
    var transcript: Transcript?

    init(index: Int, data: SegmentData) {
        self.index = index
        self.start = data.start
        self.end = data.end
        self.text = data.text
        self.speaker = data.speaker
        self.wordsData = data.words.isEmpty ? nil : try? JSONEncoder().encode(data.words)
    }

    var words: [WordTimingData] {
        guard let wordsData else { return [] }
        return (try? JSONDecoder().decode([WordTimingData].self, from: wordsData)) ?? []
    }

    var data: SegmentData {
        SegmentData(start: start, end: end, text: text, speaker: speaker, words: words)
    }

    /// Uppdaterar texten. Ordtidsstämplarna slängs eftersom de inte längre stämmer.
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        wordsData = nil
    }

    func contains(time: Double) -> Bool {
        time >= start && time < end
    }
}

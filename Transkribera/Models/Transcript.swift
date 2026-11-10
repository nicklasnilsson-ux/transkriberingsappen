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

    /// När texten som visas blev klar. `nil` för filer som skapades före sparade versioner;
    /// då gäller `createdAt`. Se `liveVersionDate`.
    var versionDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.transcript)
    var segments: [TranscriptSegment] = []

    /// Sparade versioner av texten. Texten som visas ligger i `segments`; här ligger de andra.
    @Relationship(deleteRule: .cascade, inverse: \TranscriptVersion.transcript)
    var versions: [TranscriptVersion] = []

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
        // Varje segments index läses en gång. Att sortera på `$0.index < $1.index` läser det
        // n·log n gånger, och varje läsning går via SwiftData/Core Data (mätt på M1 Air 0.9.32).
        segments.map { ($0.index, $0) }.sorted { $0.0 < $1.0 }.map(\.1)
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

    /// Segment för kopiering och export: anonymiserade när inställningen är på
    /// (se `AnonymizationSettings`). Originaltexten i databasen ändras aldrig.
    func outputSegments(options: AnonymizationOptions? = AnonymizationSettings.options()) -> [SegmentData] {
        let data = segmentData
        guard let options else { return data }
        return Anonymizer.anonymize(data, options: options).segments
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

    /// Byter flera talares namn på en gång, t.ex. till roller ("Intervjuare", "Intervjuare 2").
    func applySpeakerNames(_ names: [String: String]) {
        for segment in segments {
            if let speaker = segment.speaker, let name = names[speaker] {
                segment.speaker = name
            }
        }
    }

    /// Talarna per segment i läsordning, så att ett rollval går att ångra.
    var speakerSnapshot: [String?] { sortedSegments.map(\.speaker) }

    /// Återställer talarna från `speakerSnapshot`. Görs inget om antalet segment ändrats.
    func restoreSpeakers(_ snapshot: [String?]) {
        let sorted = sortedSegments
        guard sorted.count == snapshot.count else { return }
        for (segment, speaker) in zip(sorted, snapshot) where segment.speaker != speaker {
            segment.speaker = speaker
        }
    }

    /// Gör `speaker` till intervjuare. Övriga talare heter "Talare N".
    func setInterviewer(_ speaker: String) {
        applySpeakerNames(SpeakerRoles.names(for: speakers, interviewer: speaker))
    }

    /// Lägger till eller tar bort `speaker` som intervjuare utan att ändra de andra rollerna.
    /// Flera intervjuare numreras ("Intervjuare 1", "Intervjuare 2"), övriga heter "Talare N".
    func setInterviewer(_ speaker: String, to isInterviewer: Bool) {
        var interviewers = Set(speakers.filter(SpeakerRoles.isInterviewer))
        if isInterviewer { interviewers.insert(speaker) } else { interviewers.remove(speaker) }
        applySpeakerNames(SpeakerRoles.names(for: speakers, interviewers: interviewers))
    }

    /// Flyttar bara de här segmenten (ett stycke eller en rad) till en annan talare, t.ex. när
    /// talaridentifieringen lagt en replik hos fel person. ⚠ tas bort: användaren har själv bestämt.
    /// Ger läget före bytet, så att det går att ångra; `nil` om ingenting ändrades.
    func moveSegments(_ indices: Set<Int>, to speaker: String) -> SpeakerMove.Undo? {
        let name = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var entries: [SpeakerMove.Undo.Entry] = []
        for segment in sortedSegments where indices.contains(segment.index) {
            let words = SpeakerMove.clearingUncertainty(segment.wordsData)
            guard segment.speaker != name || words != segment.wordsData else { continue }
            entries.append(.init(index: segment.index, speaker: segment.speaker, wordsData: segment.wordsData))
            segment.speaker = name
            segment.wordsData = words
        }
        return entries.isEmpty ? nil : SpeakerMove.Undo(entries: entries, speaker: name)
    }

    /// Sant så länge bytet går att ångra (talaren har inte bytt namn eller fått en roll sedan dess).
    func canUndo(_ move: SpeakerMove.Undo) -> Bool {
        let wanted = Set(move.entries.map(\.index))
        var current: [Int: String?] = [:]
        for segment in segments where wanted.contains(segment.index) {
            current[segment.index] = .some(segment.speaker)
        }
        return move.canUndo(currentSpeakers: current)
    }

    /// Ger segmenten tillbaka talaren och ⚠ som de hade före bytet.
    func undo(_ move: SpeakerMove.Undo) {
        guard canUndo(move) else { return }
        for entry in move.entries {
            guard let segment = segments.first(where: { $0.index == entry.index }) else { continue }
            segment.speaker = entry.speaker
            segment.wordsData = entry.wordsData
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
        let words = words
        return SegmentData(
            start: start, end: end, text: text, speaker: speaker, words: words,
            uncertainSpeaker: words.contains { $0.uncertainSpeaker == true }
        )
    }

    /// Osäkert vem som sa det här (⚠). Följer med ordtiderna och försvinner när texten rättas.
    var isSpeakerUncertain: Bool {
        wordsData.map(WordTimingData.hasUncertainSpeaker(inEncoded:)) ?? false
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

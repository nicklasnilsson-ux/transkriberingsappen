import Foundation
import Observation
import SpeakerKit
import TranskriberaCore
import WhisperKit

/// Resultatet av en transkribering, oberoende av lagringen.
struct TranscriptionOutput {
    var segments: [SegmentData]
    var language: String?
}

enum TranscriberError: LocalizedError {
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .emptyAudio: return "Filen innehåller inget ljud som går att transkribera."
        }
    }
}

/// Sköter nedladdning/laddning av Whisper-modellen och körningen av själva
/// transkriberingen. Allt körs lokalt på datorn med WhisperKit (CoreML).
@MainActor
@Observable
final class TranscriberService {
    enum Phase: Equatable {
        case idle
        case downloadingModel(fraction: Double)
        case loadingModel
        case preparingAudio
        case transcribing(fraction: Double)
        case identifyingSpeakers
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var loadedModel: WhisperModel?
    /// Senast upptäckta text, visas live medan transkriberingen pågår.
    private(set) var liveText: String = ""

    @ObservationIgnored private var whisperKit: WhisperKit?
    @ObservationIgnored private var speakerKit: SpeakerKit?

    var isBusy: Bool {
        switch phase {
        case .idle, .failed: return false
        default: return true
        }
    }

    var statusText: String {
        switch phase {
        case .idle: return loadedModel.map { "\($0.displayName) är redo" } ?? "Redo"
        case .downloadingModel(let fraction): return "Laddar ner modell… \(Int(fraction * 100)) %"
        case .loadingModel: return "Laddar modell (första gången kan ta några minuter)…"
        case .preparingAudio: return "Förbereder ljud…"
        case .transcribing(let fraction): return "Transkriberar… \(Int(fraction * 100)) %"
        case .identifyingSpeakers: return "Identifierar talare…"
        case .failed(let message): return "Fel: \(message)"
        }
    }

    /// Framsteg 0–1, eller `nil` om det inte går att uppskatta.
    var fraction: Double? {
        switch phase {
        case .downloadingModel(let fraction), .transcribing(let fraction): return fraction
        default: return nil
        }
    }

    // MARK: - Modeller

    static func localFolder(for model: WhisperModel) -> URL {
        AppPaths.modelsDirectory
            .appending(path: "models/argmaxinc/whisperkit-coreml/openai_whisper-\(model.variant)", directoryHint: .isDirectory)
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        let folder = Self.localFolder(for: model)
        return ["AudioEncoder", "TextDecoder", "MelSpectrogram"].allSatisfy { name in
            FileManager.default.fileExists(atPath: folder.appending(path: "\(name).mlmodelc").path)
        }
    }

    func deleteDownloadedModel(_ model: WhisperModel) {
        if loadedModel == model {
            whisperKit = nil
            loadedModel = nil
        }
        try? FileManager.default.removeItem(at: Self.localFolder(for: model))
    }

    /// Laddar ner (vid behov) och laddar in modellen i minnet.
    @discardableResult
    func prepare(model: WhisperModel) async throws -> WhisperKit {
        if let whisperKit, loadedModel == model {
            return whisperKit
        }
        if let previous = whisperKit {
            await previous.unloadModels()
        }
        whisperKit = nil
        loadedModel = nil

        do {
            let folder: URL
            if isDownloaded(model) {
                folder = Self.localFolder(for: model)
            } else {
                phase = .downloadingModel(fraction: 0)
                folder = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: AppPaths.modelsDirectory,
                    progressCallback: { [weak self] progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            guard let self, case .downloadingModel = self.phase else { return }
                            self.phase = .downloadingModel(fraction: fraction)
                        }
                    }
                )
            }

            phase = .loadingModel
            let config = WhisperKitConfig(
                model: model.variant,
                downloadBase: AppPaths.modelsDirectory,
                modelFolder: folder.path,
                tokenizerFolder: AppPaths.modelsDirectory,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            whisperKit = kit
            loadedModel = model
            phase = .idle
            return kit
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Transkribering

    /// Transkriberar en mediefil. `onSegments` anropas löpande med de segment som hittats hittills.
    func transcribe(
        fileURL: URL,
        duration: Double,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        liveText = ""
        do {
            let kit = try await prepare(model: options.model)

            phase = .preparingAudio
            let samples = try await AudioLoader.loadSamples(from: fileURL)
            guard !samples.isEmpty else { throw TranscriberError.emptyAudio }
            let totalSeconds = max(duration, Double(samples.count) / AudioLoader.sampleRate)

            phase = .transcribing(fraction: 0)
            let decodeOptions = DecodingOptions(
                task: options.translateToEnglish ? .translate : .transcribe,
                language: options.languageCode,
                temperatureFallbackCount: 3,
                usePrefillPrompt: true,
                detectLanguage: options.languageCode == nil,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                wordTimestamps: options.wordTimestamps || options.identifySpeakers,
                chunkingStrategy: .vad
            )

            let results = try await kit.transcribe(
                audioArray: samples,
                decodeOptions: decodeOptions,
                callback: nil,
                segmentCallback: { [weak self] segments in
                    guard let last = segments.last else { return }
                    let fraction = min(1, Double(last.end) / totalSeconds)
                    let text = TextCleaning.clean(last.text)
                    Task { @MainActor in
                        guard let self else { return }
                        if case .transcribing(let current) = self.phase, fraction > current {
                            self.phase = .transcribing(fraction: fraction)
                        }
                        if !text.isEmpty { self.liveText = text }
                    }
                }
            )

            var segments: [SegmentData]
            if options.identifySpeakers {
                phase = .identifyingSpeakers
                segments = try await diarizedSegments(samples: samples, results: results)
            } else {
                segments = Self.segments(from: results)
            }
            segments = segments.filter { !TextCleaning.isNonSpeechMarker($0.text) }

            phase = .idle
            liveText = ""
            return TranscriptionOutput(segments: segments, language: options.languageCode ?? results.first?.language)
        } catch {
            if error is CancellationError {
                phase = .idle
            } else {
                phase = .failed(error.localizedDescription)
            }
            liveText = ""
            throw error
        }
    }

    // MARK: - Konvertering

    static func segments(from results: [TranscriptionResult]) -> [SegmentData] {
        results
            .flatMap(\.segments)
            .sorted { $0.start < $1.start }
            .compactMap { segment in
                let text = TextCleaning.clean(segment.text)
                guard !text.isEmpty else { return nil }
                return SegmentData(
                    start: Double(segment.start),
                    end: Double(segment.end),
                    text: text,
                    words: (segment.words ?? []).map(Self.word(from:))
                )
            }
    }

    static func word(from timing: WordTiming) -> WordTimingData {
        WordTimingData(
            word: timing.word,
            start: Double(timing.start),
            end: Double(timing.end),
            probability: Double(timing.probability)
        )
    }

    // MARK: - Talaridentifiering (SpeakerKit)

    private func diarizedSegments(samples: [Float], results: [TranscriptionResult]) async throws -> [SegmentData] {
        let kit: SpeakerKit
        if let speakerKit {
            kit = speakerKit
        } else {
            let config = PyannoteConfig(
                downloadBase: AppPaths.modelsDirectory.path,
                verbose: false,
                logLevel: .error
            )
            kit = try await SpeakerKit(config)
            speakerKit = kit
        }

        let diarization = try await kit.diarize(audioArray: samples)
        let speakerSegments = diarization.addSpeakerInfo(to: results, strategy: .subsegment)

        // Numrera talarna i den ordning de först hörs: "Talare 1", "Talare 2" …
        var speakerNames: [Int: String] = [:]
        func name(for info: SpeakerInfo) -> String? {
            guard let id = info.speakerId else { return nil }
            if let existing = speakerNames[id] { return existing }
            let new = "Talare \(speakerNames.count + 1)"
            speakerNames[id] = new
            return new
        }

        let segments: [SegmentData] = speakerSegments
            .flatMap { $0 }
            .sorted { $0.startTime < $1.startTime }
            .compactMap { segment in
                let text = TextCleaning.clean(segment.text)
                guard !text.isEmpty else { return nil }
                return SegmentData(
                    start: Double(segment.startTime),
                    end: Double(segment.endTime),
                    text: text,
                    speaker: name(for: segment.speaker),
                    words: segment.speakerWords.map { Self.word(from: $0.wordTiming) }
                )
            }

        // Om diariseringen inte gav något (t.ex. inga ordtidsstämplar) – fall tillbaka.
        return segments.isEmpty ? Self.segments(from: results) : segments
    }
}

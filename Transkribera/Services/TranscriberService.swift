import Foundation
import Observation
import SpeakerKit
import TranskriberaCore
import TranskriberaSpeakers
import TranskriberaWhisper
import WhisperKit

/// Resultatet av en transkribering, oberoende av lagringen.
struct TranscriptionOutput {
    var segments: [SegmentData]
    var language: String?
}

enum TranscriberError: LocalizedError {
    case emptyAudio
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .emptyAudio: return "Filen innehåller inget ljud som går att transkribera."
        case .modelNotLoaded: return "Modellen kunde inte läsas in. Försök igen."
        }
    }
}

/// Sköter nedladdning/laddning av modellen och körningen av själva transkriberingen.
/// Allt körs lokalt på datorn: Whisper-modellerna med WhisperKit och Pianissimo med
/// FluidAudio (båda CoreML).
@MainActor
@Observable
final class TranscriberService {
    enum Phase: Equatable {
        case idle
        case downloadingModel(fraction: Double)
        case loadingModel
        case preparingAudio
        /// `nil` tills modellen har rapporterat något förlopp: då visas ett obestämt förlopp
        /// i stället för en nolla som ser ut att ha fastnat.
        case transcribing(fraction: Double?)
        case recheckingGaps(fraction: Double)
        case identifyingSpeakers
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var loadedModel: WhisperModel?
    /// Senast upptäckta text, visas live medan transkriberingen pågår.
    private(set) var liveText: String = ""
    /// Stegen i den pågående transkriberingen, för "Steg 2 av 4". Tom utanför en transkribering.
    private(set) var steps: [TranscriptionStep] = []

    @ObservationIgnored private var whisperKit: WhisperKit?
    @ObservationIgnored private var speakerKit: SpeakerKit?
    @ObservationIgnored private let communityDiarizer = CommunityDiarizer(
        modelsDirectory: AppPaths.modelsDirectory.appending(path: "speaker-diarization", directoryHint: .isDirectory)
    )
    @ObservationIgnored private let shortReplyDiarizer = ShortReplyDiarizer()
    @ObservationIgnored private let parakeet = ParakeetTranscriber()

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
        case .loadingModel: return "Förbereder modellen (första gången kan ta några minuter)…"
        case .preparingAudio: return "Läser in ljudet…"
        case .transcribing(.none): return "Transkriberar…"
        case .transcribing(let fraction?): return "Transkriberar… \(Int(fraction * 100)) %"
        case .recheckingGaps(let fraction): return "Kontrollerar att inget tal saknas… \(Int(fraction * 100)) %"
        case .identifyingSpeakers: return "Identifierar talare…"
        case .failed(let message): return "Fel: \(message)"
        }
    }

    /// "Steg 2 av 4" under en transkribering, annars `nil`.
    var stepText: String? {
        let step: TranscriptionStep
        switch phase {
        case .downloadingModel, .loadingModel: step = .model
        case .preparingAudio: step = .audio
        case .transcribing: step = .transcribe
        case .recheckingGaps: step = .gapCheck
        case .identifyingSpeakers: step = .speakers
        case .idle, .failed: return nil
        }
        return TranscriptionStep.label(for: step, in: steps)
    }

    /// Framsteg 0–1, eller `nil` om det inte går att uppskatta.
    var fraction: Double? {
        switch phase {
        case .downloadingModel(let fraction), .recheckingGaps(let fraction): return fraction
        case .transcribing(let fraction): return fraction
        default: return nil
        }
    }

    // MARK: - Modeller

    static func localFolder(for model: WhisperModel) -> URL {
        switch model.source {
        case .whisperKit(let variant):
            return AppPaths.modelsDirectory
                .appending(path: "models/argmaxinc/whisperkit-coreml/openai_whisper-\(variant)", directoryHint: .isDirectory)
        case .kbRelease:
            return AppPaths.modelsDirectory
                .appending(path: "kb-whisper/\(model.rawValue)", directoryHint: .isDirectory)
        case .pianissimoRelease:
            return AppPaths.modelsDirectory
                .appending(path: "pianissimo/\(model.rawValue)", directoryHint: .isDirectory)
        }
    }

    func isDownloaded(_ model: WhisperModel) -> Bool {
        let folder = Self.localFolder(for: model)
        let files = model.usesParakeet
            ? ParakeetTranscriber.requiredFiles
            : ["AudioEncoder", "TextDecoder", "MelSpectrogram"].map { "\($0).mlmodelc" }
        return files.allSatisfy { name in
            FileManager.default.fileExists(atPath: folder.appending(path: name).path)
        }
    }

    func deleteDownloadedModel(_ model: WhisperModel) {
        if loadedModel == model {
            whisperKit = nil
            loadedModel = nil
            let parakeet = parakeet
            Task { await parakeet.unload() }
        }
        try? FileManager.default.removeItem(at: Self.localFolder(for: model))
    }

    /// Laddar ner (vid behov) och laddar in modellen i minnet.
    func prepare(model: WhisperModel) async throws {
        if loadedModel == model, model.usesParakeet || whisperKit != nil { return }
        if let previous = whisperKit {
            await previous.unloadModels()
        }
        whisperKit = nil
        await parakeet.unload()
        loadedModel = nil

        do {
            let folder = try await downloadIfNeeded(model)
            phase = .loadingModel
            if model.usesParakeet {
                try await parakeet.load(folder: folder)
            } else {
                let config = WhisperKitConfig(
                    model: model.rawValue,
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
                // Annars kan en ordlista få WhisperKit att avkoda samma fönster i all evighet.
                WhisperLoopGuard.install(on: kit)
                whisperKit = kit
            }
            loadedModel = model
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    private func downloadIfNeeded(_ model: WhisperModel) async throws -> URL {
        if isDownloaded(model) { return Self.localFolder(for: model) }

        phase = .downloadingModel(fraction: 0)
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloadingModel = self.phase else { return }
                self.phase = .downloadingModel(fraction: fraction)
            }
        }
        switch model.source {
        case .whisperKit(let variant):
            return try await WhisperKit.download(
                variant: variant,
                downloadBase: AppPaths.modelsDirectory,
                progressCallback: { progress in report(progress.fractionCompleted) }
            )
        case .kbRelease(let asset):
            let folder = Self.localFolder(for: model)
            try await ModelDownloader.download(asset: asset, to: folder, progress: report)
            return folder
        case .pianissimoRelease(let asset):
            let folder = Self.localFolder(for: model)
            try await ModelDownloader.download(
                asset: asset, release: ModelDownloader.pianissimoRelease, to: folder, progress: report
            )
            return folder
        }
    }

    // MARK: - Transkribering

    /// Transkriberar en mediefil. Texten som hittats hittills visas löpande i `liveText`.
    func transcribe(
        fileURL: URL,
        duration: Double,
        options: TranscriptionOptions
    ) async throws -> TranscriptionOutput {
        liveText = ""
        let modelReady = loadedModel == options.model && (options.model.usesParakeet || whisperKit != nil)
        steps = TranscriptionStep.plan(
            needsModel: !modelReady,
            checksGaps: !options.model.usesParakeet,
            identifiesSpeakers: options.identifySpeakers
        )
        defer { steps = [] }
        do {
            try await prepare(model: options.model)

            phase = .preparingAudio
            let samples = try await AudioLoader.loadSamples(from: fileURL)
            guard !samples.isEmpty else { throw TranscriberError.emptyAudio }

            phase = .transcribing(fraction: nil)
            // Talaridentifieringen får originalljudet; bara modellen får det utjämnade.
            let input = options.appliesLevelVolume ? VolumeLeveler.level(samples, sampleRate: AudioLoader.sampleRate) : samples
            var segments: [SegmentData]
            let language: String?
            if options.model.usesParakeet {
                segments = try await parakeet.transcribe(samples: input, carefulSeams: options.carefulSeams) { [weak self] fraction, text in
                    let text = TextCleaning.clean(text)
                    Task { @MainActor in
                        guard let self else { return }
                        self.advanceTranscribing(to: fraction)
                        if !text.isEmpty { self.liveText = text }
                    }
                }
                language = "sv"
            } else {
                guard let kit = whisperKit else { throw TranscriberError.modelNotLoaded }
                let results = try await whisperTranscribe(kit: kit, samples: input, options: options)
                segments = Self.segments(from: results)
                segments = try await repairGaps(kit: kit, samples: input, segments: segments, options: options)
                language = options.languageCode ?? results.first?.language
            }
            // Namn ur ordlistan som hörts nästan rätt. Pianissimo kan inte få ordlistan som
            // ledtråd, och Whisper stavar ibland fel trots den.
            segments = VocabularyCorrection.apply(segments, vocabulary: TextCleaning.wordList(options.vocabulary))

            if options.identifySpeakers {
                phase = .identifyingSpeakers
                segments = try await diarizedSegments(samples: samples, segments: segments, options: options)
            }
            segments = segments.filter { !TextCleaning.isNonSpeechMarker($0.text) }

            phase = .idle
            liveText = ""
            return TranscriptionOutput(segments: segments, language: language)
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

    private func whisperTranscribe(
        kit: WhisperKit,
        samples: [Float],
        options: TranscriptionOptions
    ) async throws -> [TranscriptionResult] {
        let decodeOptions = DecodingOptions(
            task: options.translateToEnglish ? .translate : .transcribe,
            language: options.languageCode,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: options.languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: options.wordTimestamps || options.identifySpeakers,
            promptTokens: Self.promptTokens(for: options.vocabulary, tokenizer: kit.tokenizer),
            // Tystnad klipps redan bort av VAD-uppdelningen. Spärrarna nedan kastar annars
            // bort hela 30-sekundersfönster när en svag röst gör modellen osäker.
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: nil,
            chunkingStrategy: .vad
        )

        // WhisperKit skickar inte vidare en egen segmentCallback när ljudet delas upp med
        // VAD, så förlopp och text hämtas via TranskriberaWhisper (testat mot en riktig modell).
        return try await WhisperProgress.transcribe(
            kit: kit,
            audioArray: samples,
            decodeOptions: decodeOptions,
            onProgress: { [weak self] fraction in
                Task { @MainActor in self?.advanceTranscribing(to: fraction) }
            },
            onText: { [weak self] text in
                let text = TextCleaning.clean(text)
                guard !text.isEmpty else { return }
                Task { @MainActor in self?.liveText = text }
            }
        )
    }

    /// Förloppet går bara framåt, även om rapporterna kommer i fel ordning.
    private func advanceTranscribing(to fraction: Double) {
        guard case .transcribing(let current) = phase, fraction > (current ?? 0) else { return }
        phase = .transcribing(fraction: min(1, fraction))
    }

    /// Whisper avslutar ibland ett fönster i förtid och hoppar över resten, så att hela
    /// partier av ett samtal saknas utan att det syns. Tal som saknar text transkriberas
    /// därför om för sig, utan ordlista (en ledtråd kan själv få modellen att sluta).
    private func repairGaps(
        kit: WhisperKit,
        samples: [Float],
        segments: [SegmentData],
        options: TranscriptionOptions
    ) async throws -> [SegmentData] {
        phase = .recheckingGaps(fraction: 0)
        let rate = AudioLoader.sampleRate
        let speech = SpeechCoverage.speechRegions(in: samples, sampleRate: rate)
        let gaps = SpeechCoverage.uncovered(speech: speech, segments: segments)
        guard !gaps.isEmpty else { return segments }

        let decodeOptions = DecodingOptions(
            task: options.translateToEnglish ? .translate : .transcribe,
            language: options.languageCode,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: options.languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: options.wordTimestamps || options.identifySpeakers,
            firstTokenLogProbThreshold: nil,
            noSpeechThreshold: nil,
            chunkingStrategy: .vad
        )

        var repaired = segments
        for (index, gap) in gaps.enumerated() {
            try Task.checkCancellation()
            phase = .recheckingGaps(fraction: Double(index) / Double(gaps.count))
            let start = max(0, Int((gap.start - 0.5) * rate))
            let end = min(samples.count, Int((gap.end + 0.5) * rate))
            guard end > start else { continue }
            let results = try await kit.transcribe(audioArray: Array(samples[start..<end]), decodeOptions: decodeOptions)
            let offset = Double(start) / rate
            let found = Self.segments(from: results)
                .map { $0.shifted(by: offset) }
                .filter { (gap.start...gap.end).contains(($0.start + $0.end) / 2) }
            repaired += found
        }
        return repaired.sorted { $0.start < $1.start }
    }

    // MARK: - Ordlista

    /// Whisper kan få en text "före" ljudet som ledtråd. Står namn och fackord där
    /// stavas de oftare rätt, t.ex. "TG", "bruttovinst" eller "Fortnox".
    static func promptTokens(for vocabulary: String, tokenizer: WhisperTokenizer?) -> [Int]? {
        let words = TextCleaning.wordList(vocabulary)
        guard let tokenizer, !words.isEmpty else { return nil }
        let tokens = tokenizer.encode(text: " " + words.joined(separator: ", ") + ".")
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
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
                        .filter { !TextCleaning.clean($0.word).isEmpty }
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

    // MARK: - Talaridentifiering (SpeakerKit eller community-1)

    private func diarizedSegments(samples: [Float], segments: [SegmentData], options: TranscriptionOptions) async throws -> [SegmentData] {
        let turns: [SpeakerTurn]
        let diarizerName: String
        if options.sortformerDiarization {
            turns = try await shortReplyDiarizer.turns(samples: samples)
            diarizerName = "Sortformer"
        } else if options.communityDiarization {
            turns = try await communityDiarizer.turns(samples: samples, speakers: options.speakerCount)
            diarizerName = "community-1"
        } else {
            turns = try await speakerKitTurns(samples: samples, speakers: options.speakerCount)
            diarizerName = "SpeakerKit"
        }

        // Talare sätts per ord, så att repliker utan paus emellan ändå delas upp rätt.
        let assigned = SpeakerAssignment.assign(segments, turns: turns)
        saveSpeakerTurns(
            SpeakerDiagnostics(
                diarizer: diarizerName,
                speakers: options.speakerCount.label,
                turns: turns,
                segments: assigned
            )
        )

        // Om diariseringen inte gav något – behåll segmenten utan talare.
        return assigned.contains { $0.speaker != nil } ? assigned : segments
    }

    /// Sparar turerna så att fel i talartilldelningen går att söka efter utan att dela texten.
    /// De 20 senaste filerna behålls. Misslyckas det är det ingen som märker det.
    private func saveSpeakerTurns(_ diagnostics: SpeakerDiagnostics) {
        let folder = AppPaths.speakerTurnsDirectory
        let stamp = Int(Date().timeIntervalSince1970)
        guard let data = try? diagnostics.encoded() else { return }
        try? data.write(to: folder.appending(path: "talarturer-\(stamp).json"))
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for old in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropLast(20) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Dagens talaridentifiering. SpeakerKit tar bara emot ett exakt antal talare, så ett
    /// spann eller "minst 2" räknas ut automatiskt.
    private func speakerKitTurns(samples: [Float], speakers: SpeakerCount) async throws -> [SpeakerTurn] {
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

        let diarizationOptions = PyannoteDiarizationOptions(numberOfSpeakers: speakers.exact)
        let diarization = try await kit.diarize(audioArray: samples, options: diarizationOptions)
        return diarization.segments.compactMap { segment -> SpeakerTurn? in
            guard let id = segment.speaker.speakerId else { return nil }
            return SpeakerTurn(start: Double(segment.startTime), end: Double(segment.endTime), speaker: id)
        }
    }
}

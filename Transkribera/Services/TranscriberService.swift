import CoreML
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
    var diagnostics = TranscriptionDiagnostics()
    /// Sätts när något i körningen inte gick som tänkt men texten ändå blev klar
    /// (t.ex. talarna kunde inte identifieras). Visas för användaren.
    var notice: String?
}

/// Tider och mått från en körning, för Testlabbet. Ingen text.
struct TranscriptionDiagnostics {
    var transcriptionSeconds: Double = 0
    var gapCheckSeconds: Double = 0
    var gaps: TestLabReport.Gaps?
    var whisperSegments: [TestLabReport.WhisperSegment]?
    var pianissimoConfidence: Double?
    /// Talaridentifieringen inne i körningen (0 när talarna kom utifrån eller var av).
    var speakersSeconds: Double = 0
    var diarizer: String?
}

/// Ett fel med steget det hände i och en begriplig förklaring (se `FailureExplainer`).
/// Texten sparas på transkriberingen, så den finns kvar och går att kopiera.
struct TranscriptionFailure: LocalizedError {
    let step: FailureStep
    let technical: String
    let message: String

    var errorDescription: String? { message }
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
        /// Experiment "Korskolla": ljudet transkriberas en gång till och jämförs.
        case crossChecking(fraction: Double?)
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
    @ObservationIgnored private let shortReplyDiarizer = ShortReplyDiarizer()
    /// Nemotron 3 har hängt sig i den här körningen av appen. Dess aktör är då upptagen, så nästa
    /// anrop skulle bara stå i kö bakom det hängda; hoppa över den tills appen startats om.
    @ObservationIgnored private var nemotronStalled = false
    @ObservationIgnored private let parakeet = ParakeetTranscriber()
    /// Sätts när Core ML inte kunde köra en modell på Neural Engine (sett på MacBook Air M1,
    /// 2026-11-08: "ANEProgramProcessRequestDirect() Failed with status=0xf" och sedan E5RT-fel).
    /// Därefter körs alla modeller på processor och grafikkrets. Sparas per appversion, så att
    /// en ny version provar Neural Engine igen.
    @ObservationIgnored private var avoidsNeuralEngine = UserDefaults.standard.bool(forKey: TranscriberService.neuralEngineKey)

    nonisolated private static var neuralEngineKey: String { "undvikNeuralEngine \(ErrorLog.appVersion)" }

    /// Beräkningsenheterna utan Neural Engine.
    nonisolated static let withoutNeuralEngine: MLComputeUnits = .cpuAndGPU
    /// SpeakerKits röstmodell utan Neural Engine: bara processorn (se `speakerKitTurns`).
    nonisolated static let speakerKitWithoutNeuralEngine: MLComputeUnits = .cpuOnly

    /// Hur länge ett talarsteg får ta innan det släpps: 3 minuter plus en fjärdedel av ljudets längd
    /// (5 minuter ljud ger drygt 4 minuter, en timme 18 minuter). Första gången kompileras modellen.
    nonisolated static func speakerDeadline(audioSeconds: Double) -> Double { 180 + audioSeconds / 4 }

    /// Datorer med lite minne (t.ex. 8 GB) kör en modell i taget och släpper den efteråt.
    static var hasLowMemory: Bool { FailureExplainer.isLowMemory(ProcessInfo.processInfo.physicalMemory) }

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
        case .crossChecking(.none): return "Korskollar…"
        case .crossChecking(let fraction?): return "Korskollar… \(Int(fraction * 100)) %"
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
        case .crossChecking: step = .crossCheck
        case .idle, .failed: return nil
        }
        return TranscriptionStep.label(for: step, in: steps)
    }

    /// Framsteg 0–1, eller `nil` om det inte går att uppskatta.
    var fraction: Double? {
        switch phase {
        case .downloadingModel(let fraction), .recheckingGaps(let fraction): return fraction
        case .transcribing(let fraction), .crossChecking(let fraction): return fraction
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
                try await parakeet.load(folder: folder, avoidsNeuralEngine: avoidsNeuralEngine)
            } else {
                let config = WhisperKitConfig(
                    model: model.rawValue,
                    downloadBase: AppPaths.modelsDirectory,
                    modelFolder: folder.path,
                    tokenizerFolder: AppPaths.modelsDirectory,
                    computeOptions: avoidsNeuralEngine
                        ? ModelComputeOptions(
                            melCompute: Self.withoutNeuralEngine,
                            audioEncoderCompute: Self.withoutNeuralEngine,
                            textDecoderCompute: Self.withoutNeuralEngine
                        )
                        : nil,
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
            throw fail(error, model: model)
        }
    }

    /// Släpper taligenkänningsmodellen ur minnet. Den läses in igen nästa gång.
    func releaseRecognitionModel() async {
        if let kit = whisperKit { await kit.unloadModels() }
        whisperKit = nil
        await parakeet.unload()
        loadedModel = nil
    }

    /// Släpper talarmodellerna ur minnet.
    func releaseSpeakerModels() async {
        speakerKit = nil
        await shortReplyDiarizer.unload()
    }

    /// Ett Core ML-fel som ett nytt försök utan Neural Engine kan lösa.
    private func canRetryWithoutNeuralEngine(_ error: Error) -> Bool {
        !avoidsNeuralEngine && FailureExplainer.isModelComputeFailure(error.localizedDescription)
    }

    /// Slutar använda Neural Engine och släpper alla modeller, så att de läses in på nytt
    /// på processor och grafikkrets.
    private func stopUsingNeuralEngine(after error: Error, model: WhisperModel, step: FailureStep) async {
        ErrorLog.append(model: model.displayName, step: step,
                        technical: "Försöker igen utan Neural Engine: \(error.localizedDescription)")
        avoidsNeuralEngine = true
        UserDefaults.standard.set(true, forKey: Self.neuralEngineKey)
        await releaseRecognitionModel()
        await releaseSpeakerModels()
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
            identifiesSpeakers: options.identifySpeakers,
            crossChecks: options.appliedCrossCheck != nil
        )
        defer { steps = [] }
        do {
            try await prepare(model: options.model)

            phase = .preparingAudio
            let samples = try await AudioLoader.loadSamples(from: fileURL)
            guard !samples.isEmpty else { throw TranscriberError.emptyAudio }

            let output = try await recognize(samples: samples, options: options, speakerTurns: nil)
            phase = .idle
            liveText = ""
            return output
        } catch {
            throw fail(error, model: options.model)
        }
    }

    /// Testlabbet: samma väg som en vanlig transkribering, men på ljud som redan är inläst
    /// och med talarturer som tagits fram en gång för alla körningar (`nil` = inga talare).
    func transcribe(samples: [Float], options: TranscriptionOptions, speakerTurns: [SpeakerTurn]?) async throws -> TranscriptionOutput {
        liveText = ""
        do {
            try await prepare(model: options.model)
            let output = try await recognize(samples: samples, options: options, speakerTurns: speakerTurns)
            phase = .idle
            liveText = ""
            return output
        } catch {
            throw fail(error, model: options.model)
        }
    }

    /// Gör felet begripligt (steg + förklaring), loggar det och visar det. Ett fel som
    /// redan är förklarat skickas vidare som det är.
    private func fail(_ error: Error, model: WhisperModel) -> Error {
        liveText = ""
        if error is CancellationError {
            phase = .idle
            return error
        }
        if let failure = error as? TranscriptionFailure {
            phase = .failed(failure.message)
            return failure
        }
        let step = Self.failureStep(for: phase)
        let technical = error.localizedDescription
        let memory = ProcessInfo.processInfo.physicalMemory
        let failure = TranscriptionFailure(
            step: step,
            technical: technical,
            message: FailureExplainer.message(step: step, technical: technical, physicalMemory: memory)
        )
        ErrorLog.append(model: model.displayName, step: step, technical: technical)
        phase = .failed(failure.message)
        return failure
    }

    static func failureStep(for phase: Phase) -> FailureStep {
        switch phase {
        case .downloadingModel: return .downloadModel
        case .loadingModel: return .loadModel
        case .preparingAudio: return .prepareAudio
        case .transcribing, .recheckingGaps: return .recognize
        case .identifyingSpeakers: return .identifySpeakers
        case .crossChecking: return .recognize
        case .idle, .failed: return .recognize
        }
    }

    /// Taligenkänning, ordlista och talare på inläst ljud. Modellen ska redan vara inläst.
    /// Med `speakerTurns` används de turerna i stället för att identifiera talarna igen.
    private func recognize(
        samples: [Float],
        options: TranscriptionOptions,
        speakerTurns: [SpeakerTurn]?
    ) async throws -> TranscriptionOutput {
        var diagnostics = TranscriptionDiagnostics()
        var notice: String?
        let clock = ContinuousClock()
        let transcriptionStart = clock.now

        phase = .transcribing(fraction: nil)
        // Talaridentifieringen får originalljudet; bara modellen får det utjämnade.
        let input = options.appliesLevelVolume ? VolumeLeveler.level(samples, sampleRate: AudioLoader.sampleRate) : samples
        var segments: [SegmentData]
        let language: String?
        if options.model.usesParakeet {
            let output: ParakeetTranscriber.Output
            do {
                output = try await runParakeet(input, options: options)
            } catch let error where canRetryWithoutNeuralEngine(error) {
                await stopUsingNeuralEngine(after: error, model: options.model, step: .recognize)
                try await prepare(model: options.model)
                phase = .transcribing(fraction: nil)
                output = try await runParakeet(input, options: options)
            }
            segments = output.segments
            diagnostics.pianissimoConfidence = output.confidence
            diagnostics.transcriptionSeconds = Self.seconds(clock.now - transcriptionStart)
            language = "sv"
        } else {
            guard var kit = whisperKit else { throw TranscriberError.modelNotLoaded }
            let results: [TranscriptionResult]
            do {
                results = try await whisperTranscribe(kit: kit, samples: input, options: options)
            } catch let error where canRetryWithoutNeuralEngine(error) {
                await stopUsingNeuralEngine(after: error, model: options.model, step: .recognize)
                try await prepare(model: options.model)
                guard let reloaded = whisperKit else { throw TranscriberError.modelNotLoaded }
                kit = reloaded
                phase = .transcribing(fraction: nil)
                results = try await whisperTranscribe(kit: kit, samples: input, options: options)
            }
            segments = Self.segments(from: results)
            diagnostics.whisperSegments = Self.segmentStatistics(results)
            diagnostics.transcriptionSeconds = Self.seconds(clock.now - transcriptionStart)
            if options.tuning.repairsGaps {
                let gapStart = clock.now
                let repaired = try await repairGaps(kit: kit, samples: input, segments: segments, options: options)
                segments = repaired.segments
                diagnostics.gaps = repaired.gaps
                diagnostics.gapCheckSeconds = Self.seconds(clock.now - gapStart)
            }
            language = options.languageCode ?? results.first?.language
        }
        // Namn ur ordlistan som hörts nästan rätt. Pianissimo kan inte få ordlistan som
        // ledtråd, och Whisper stavar ibland fel trots den.
        segments = VocabularyCorrection.apply(segments, vocabulary: TextCleaning.wordList(options.vocabulary))

        /// Talarturerna, för korskollen med Pianissimo i repliker.
        var turns: [SpeakerTurn] = speakerTurns ?? []
        if let speakerTurns {
            let assigned = SpeakerAssignment.assign(segments, turns: speakerTurns)
            if assigned.contains(where: { $0.speaker != nil }) {
                segments = try await rescueShortReplies(assigned, turns: speakerTurns, input: input, options: options, diagnostics: &diagnostics)
            }
        } else if options.identifySpeakers {
            // Med lite minne körs en modell i taget: taligenkänningen släpps innan talarna.
            if Self.hasLowMemory { await releaseRecognitionModel() }
            phase = .identifyingSpeakers
            let speakersStart = clock.now
            var diarized: (segments: [SegmentData], diarizer: String, turns: [SpeakerTurn])
            do {
                do {
                    diarized = try await diarizedSegments(samples: samples, segments: segments, options: options)
                } catch let error where canRetryWithoutNeuralEngine(error) {
                    await stopUsingNeuralEngine(after: error, model: options.model, step: .identifySpeakers)
                    diarized = try await diarizedSegments(samples: samples, segments: segments, options: options)
                }
            } catch let timeout as SpeakerStepTimedOut {
                // Texten är klar; bara talarna saknas. Det ska synas, inte bara loggas.
                diarized = (segments, "Ingen (tidsgräns)", [])
                notice = "Talarna kunde inte identifieras: steget tog längre än \(timeout.seconds / 60) minuter och avbröts. Texten är klar utan talare. Kör om med \"Skilj på talare\" avstängt, eller starta om appen och försök igen."
            }
            if Self.hasLowMemory { await releaseSpeakerModels() }
            segments = diarized.segments
            turns = diarized.turns
            diagnostics.diarizer = diarized.diarizer
            diagnostics.speakersSeconds = Self.seconds(clock.now - speakersStart)
            if !diarized.turns.isEmpty, segments.contains(where: { $0.speaker != nil }) {
                segments = try await rescueShortReplies(segments, turns: diarized.turns, input: input, options: options, diagnostics: &diagnostics)
            }
        }
        segments = segments.filter { !TextCleaning.isNonSpeechMarker($0.text) }
        if let check = options.appliedCrossCheck {
            segments = try await crossCheck(segments, with: check, input: input, turns: turns, options: options)
        }
        return TranscriptionOutput(segments: segments, language: language, diagnostics: diagnostics, notice: notice)
    }

    /// Experiment "Korskolla" (`CrossCheck`): ljudet transkriberas en gång till, och där
    /// körningarna hörde olika får Pianissimos ord den andra tolkningen. Texten ändras inte.
    /// Går något fel behålls texten utan markeringar.
    private func crossCheck(
        _ segments: [SegmentData],
        with check: CrossCheckSource,
        input: [Float],
        turns: [SpeakerTurn],
        options: TranscriptionOptions
    ) async throws -> [SegmentData] {
        do {
            let other: [WordTimingData]
            switch check {
            case .off:
                return segments
            case .kbLarge:
                other = try await kbLargeWords(input, options: options)
            case .pianissimoReplies:
                other = try await pianissimoReplyWords(input, turns: turns, options: options)
            }
            let (result, marked) = CrossCheck.mark(segments, against: other)
            ErrorLog.append(model: options.model.displayName, step: .recognize,
                            technical: "Info: Korskolla med \(check.label): \(marked) ställen markerade")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ErrorLog.append(model: options.model.displayName, step: .recognize,
                            technical: "Korskolla med \(check.label) avbröts (\(error.localizedDescription)). Texten behålls utan markeringar.")
            return segments
        }
    }

    /// Hela ljudet med KB Large ordagrann, som ord med tider. Pianissimo släpps ur minnet först.
    private func kbLargeWords(_ input: [Float], options: TranscriptionOptions) async throws -> [WordTimingData] {
        var kbOptions = options
        kbOptions.model = CrossCheckSource.kbLarge.model
        kbOptions.wordTimestamps = true
        kbOptions.crossCheck = .off
        try await prepare(model: kbOptions.model)
        guard let kit = whisperKit else { throw TranscriberError.modelNotLoaded }
        phase = .crossChecking(fraction: nil)
        // Whisper-modellerna får ljudet med jämnad volym, som när KB Large körs för sig.
        let leveled = kbOptions.appliesLevelVolume ? VolumeLeveler.level(input, sampleRate: AudioLoader.sampleRate) : input
        let results: [TranscriptionResult]
        do {
            results = try await whisperTranscribe(kit: kit, samples: leveled, options: kbOptions, phase: .crossCheck)
        } catch let error where canRetryWithoutNeuralEngine(error) {
            await stopUsingNeuralEngine(after: error, model: kbOptions.model, step: .recognize)
            try await prepare(model: kbOptions.model)
            guard let reloaded = whisperKit else { throw TranscriberError.modelNotLoaded }
            phase = .crossChecking(fraction: nil)
            results = try await whisperTranscribe(kit: reloaded, samples: leveled, options: kbOptions, phase: .crossCheck)
        }
        return Self.segments(from: results).flatMap(\.words)
    }

    /// Pianissimo en gång till, med ljudet delat i repliker efter talarna (`ReplyPlan`).
    private func pianissimoReplyWords(_ input: [Float], turns: [SpeakerTurn], options: TranscriptionOptions) async throws -> [WordTimingData] {
        guard !turns.isEmpty else { return [] }
        try await prepare(model: options.model)
        phase = .crossChecking(fraction: 0)
        let rate = AudioLoader.sampleRate
        let duration = Double(input.count) / rate
        var words: [WordTimingData] = []
        for piece in ReplyPlan.pieces(turns: turns, duration: duration) {
            try Task.checkCancellation()
            let from = max(0, min(input.count, Int(piece.start * rate)))
            let to = max(from, min(input.count, Int(piece.end * rate)))
            let clip = Array(input[from..<to])
            do {
                words += try await parakeet.words(samples: clip, offset: Double(from) / rate,
                                                  carefulSeams: options.carefulSeams, tuning: options.tuning)
            } catch let error where canRetryWithoutNeuralEngine(error) {
                await stopUsingNeuralEngine(after: error, model: options.model, step: .recognize)
                try await prepare(model: options.model)
                words += try await parakeet.words(samples: clip, offset: Double(from) / rate,
                                                  carefulSeams: options.carefulSeams, tuning: options.tuning)
            }
            advanceCrossCheck(to: piece.end / max(duration, 1))
        }
        return words
    }

    private func advanceCrossCheck(to fraction: Double) {
        guard case .crossChecking(let current) = phase, fraction > (current ?? 0) else { return }
        phase = .crossChecking(fraction: min(1, fraction))
    }

    /// Experiment "Fånga korta svar" (`ShortReplyRescue`): korta turer vars ord saknas i
    /// texten transkriberas för sig med Pianissimo och läggs in som egna repliker. Den
    /// vanliga texten ändras inte. Går något fel behålls texten som den var.
    private func rescueShortReplies(
        _ segments: [SegmentData],
        turns: [SpeakerTurn],
        input: [Float],
        options: TranscriptionOptions,
        diagnostics: inout TranscriptionDiagnostics
    ) async throws -> [SegmentData] {
        guard options.appliesShortReplyRescue else { return segments }
        let rate = AudioLoader.sampleRate
        let duration = Double(input.count) / rate
        let candidates = ShortReplyRescue.candidates(segments: segments, turns: turns, duration: duration)
        guard !candidates.isEmpty else { return segments }
        do {
            // Med lite minne släpptes taligenkänningen före talarna; den behövs igen.
            try await prepare(model: options.model)
            phase = .transcribing(fraction: 0)
            var rescued: [(turn: SpeakerTurn, words: [WordTimingData])] = []
            for (index, candidate) in candidates.enumerated() {
                try Task.checkCancellation()
                let from = max(0, min(input.count, Int(candidate.clipStart * rate)))
                let to = max(from, min(input.count, Int(candidate.clipEnd * rate)))
                let clip = Array(input[from..<to])
                let words: [WordTimingData]
                do {
                    words = try await parakeet.words(samples: clip, offset: Double(from) / rate,
                                                     carefulSeams: options.carefulSeams, tuning: options.tuning)
                } catch let error where canRetryWithoutNeuralEngine(error) {
                    await stopUsingNeuralEngine(after: error, model: options.model, step: .recognize)
                    try await prepare(model: options.model)
                    words = try await parakeet.words(samples: clip, offset: Double(from) / rate,
                                                     carefulSeams: options.carefulSeams, tuning: options.tuning)
                }
                rescued.append((candidate.turn, words))
                advanceTranscribing(to: Double(index + 1) / Double(candidates.count))
            }
            let (result, added) = ShortReplyRescue.insertCounting(rescued, into: segments, turns: turns)
            diagnostics.diarizer = "\(diagnostics.diarizer ?? "talare"), korta svar: \(added) av \(candidates.count)"
            ErrorLog.append(model: options.model.displayName, step: .recognize,
                            technical: "Info: Fånga korta svar: \(candidates.count) korta turer utan text, \(added) svar inlagda")
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            ErrorLog.append(model: options.model.displayName, step: .recognize,
                            technical: "Fånga korta svar avbröts (\(error.localizedDescription)). Texten behålls utan dem.")
            return segments
        }
    }

    private func runParakeet(_ input: [Float], options: TranscriptionOptions) async throws -> ParakeetTranscriber.Output {
        try await parakeet.transcribe(
            samples: input,
            carefulSeams: options.carefulSeams,
            tuning: options.tuning
        ) { [weak self] fraction, text in
            let text = TextCleaning.clean(text)
            Task { @MainActor in
                guard let self else { return }
                self.advanceTranscribing(to: fraction)
                if !text.isEmpty { self.liveText = text }
            }
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Hur säker Whisper var på varje stycke, och om det skrevs om med mer slump.
    static func segmentStatistics(_ results: [TranscriptionResult]) -> [TestLabReport.WhisperSegment] {
        results
            .flatMap(\.segments)
            .sorted { $0.start < $1.start }
            .map { segment in
                TestLabReport.WhisperSegment(
                    start: Double(segment.start),
                    end: Double(segment.end),
                    words: TextCleaning.clean(segment.text).split(whereSeparator: \.isWhitespace).count,
                    temperature: Double(segment.temperature),
                    averageLogProbability: Double(segment.avgLogprob),
                    compressionRatio: Double(segment.compressionRatio),
                    noSpeechProbability: Double(segment.noSpeechProb)
                )
            }
    }

    private func whisperTranscribe(
        kit: WhisperKit,
        samples: [Float],
        options: TranscriptionOptions,
        phase step: TranscriptionStep = .transcribe
    ) async throws -> [TranscriptionResult] {
        let decodeOptions = DecodingOptions(
            task: options.translateToEnglish ? .translate : .transcribe,
            language: options.languageCode,
            temperatureFallbackCount: options.tuning.temperatureFallbackCount,
            usePrefillPrompt: true,
            detectLanguage: options.languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: options.wordTimestamps || options.identifySpeakers,
            windowClipTime: options.tuning.windowClipTime,
            promptTokens: Self.promptTokens(for: options.vocabulary, style: options.tuning.stylePrompt, tokenizer: kit.tokenizer),
            compressionRatioThreshold: options.tuning.compressionRatioThreshold,
            logProbThreshold: options.tuning.logProbThreshold,
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
                Task { @MainActor in
                    if step == .crossCheck { self?.advanceCrossCheck(to: fraction) } else { self?.advanceTranscribing(to: fraction) }
                }
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
    ) async throws -> (segments: [SegmentData], gaps: TestLabReport.Gaps) {
        phase = .recheckingGaps(fraction: 0)
        let rate = AudioLoader.sampleRate
        let speech = SpeechCoverage.speechRegions(in: samples, sampleRate: rate)
        let gaps = SpeechCoverage.uncovered(speech: speech, segments: segments)
        let none = TestLabReport.Gaps(count: 0, seconds: 0, segmentsAdded: 0)
        guard !gaps.isEmpty else { return (segments, none) }

        let decodeOptions = DecodingOptions(
            task: options.translateToEnglish ? .translate : .transcribe,
            language: options.languageCode,
            temperatureFallbackCount: options.tuning.temperatureFallbackCount,
            usePrefillPrompt: true,
            detectLanguage: options.languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: options.wordTimestamps || options.identifySpeakers,
            windowClipTime: options.tuning.windowClipTime,
            promptTokens: options.tuning.stylePromptInGapCheck
                ? Self.promptTokens(for: "", style: options.tuning.stylePrompt, tokenizer: kit.tokenizer)
                : nil,
            compressionRatioThreshold: options.tuning.compressionRatioThreshold,
            logProbThreshold: options.tuning.logProbThreshold,
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
        let stats = TestLabReport.Gaps(
            count: gaps.count,
            seconds: gaps.reduce(0) { $0 + $1.duration },
            segmentsAdded: repaired.count - segments.count
        )
        return (repaired.sorted { $0.start < $1.start }, stats)
    }

    // MARK: - Ordlista

    /// Whisper kan få en text "före" ljudet som ledtråd. Står namn och fackord där
    /// stavas de oftare rätt, t.ex. "TG", "bruttovinst" eller "Fortnox".
    static func promptTokens(for vocabulary: String, style: String? = nil, tokenizer: WhisperTokenizer?) -> [Int]? {
        let words = TextCleaning.wordList(vocabulary)
        var parts: [String] = []
        if let style, !style.isEmpty { parts.append(style) }
        if !words.isEmpty { parts.append(words.joined(separator: ", ") + ".") }
        guard let tokenizer, !parts.isEmpty else { return nil }
        let tokens = tokenizer.encode(text: " " + parts.joined(separator: " "))
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

    // MARK: - Talaridentifiering (Nemotron 3 eller SpeakerKit)

    private func diarizedSegments(
        samples: [Float],
        segments: [SegmentData],
        options: TranscriptionOptions
    ) async throws -> (segments: [SegmentData], diarizer: String, turns: [SpeakerTurn]) {
        let (turns, diarizerName) = try await speakerTurns(samples: samples, options: options)

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
        return (assigned.contains { $0.speaker != nil } ? assigned : segments, diarizerName, turns)
    }

    /// Vem som talar när, och vilken modell som kom fram till det. Varje modell har en tidsgräns
    /// (`speakerDeadline`): hänger sig Nemotron byts den mot SpeakerKit, och hänger sig den också
    /// kastas `SpeakerStepTimedOut`. Delstegen loggas i Felloggen, så att en hängning syns var den stannade.
    func speakerTurns(samples: [Float], options: TranscriptionOptions) async throws -> (turns: [SpeakerTurn], diarizer: String) {
        let limit = Self.speakerDeadline(audioSeconds: Double(samples.count) / AudioLoader.sampleRate)
        let clock = ContinuousClock()
        let model = options.model.displayName
        // Nemotron tar inget antal talare, så ett fast antal går till de andra. Går
        // modellen inte att ladda ner eller ger den inga turer används den vanliga vägen.
        var nemotronTurns: [SpeakerTurn]?
        if options.sortformerDiarization && options.speakerCount.exact == nil && !nemotronStalled {
            ErrorLog.append(model: model, step: .identifySpeakers, technical: "Info: Nemotron 3 startar (tidsgräns \(Int(limit)) s)")
            let started = clock.now
            let diarizer = shortReplyDiarizer
            let avoidsNeuralEngine = self.avoidsNeuralEngine
            do {
                let found = try await Deadline.run(seconds: limit) {
                    try await diarizer.turns(
                        samples: samples,
                        computeUnits: avoidsNeuralEngine ? Self.withoutNeuralEngine : .all
                    )
                }
                if let found {
                    nemotronTurns = found
                    ErrorLog.append(model: model, step: .identifySpeakers,
                                    technical: "Info: Nemotron 3 klar på \(Int(Self.seconds(clock.now - started))) s")
                } else {
                    nemotronStalled = true
                    ErrorLog.append(model: model, step: .identifySpeakers,
                                    technical: "Tidsgräns: Nemotron 3 svarade inte på \(Int(limit)) s. Byter till SpeakerKit.")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Felet stoppar inte körningen, men det ska synas i loggen (det försvann förut).
                ErrorLog.append(model: "Nemotron 3", step: .identifySpeakers,
                                technical: "Byter till SpeakerKit: \(error.localizedDescription)")
            }
        }
        if let nemotronTurns, !nemotronTurns.isEmpty {
            return (nemotronTurns, "Nemotron 3")
        }
        ErrorLog.append(model: model, step: .identifySpeakers, technical: "Info: SpeakerKit startar (tidsgräns \(Int(limit)) s)")
        let started = clock.now
        let turns = try await Deadline.run(seconds: limit) { [self] in
            try await speakerKitTurns(samples: samples, speakers: options.speakerCount)
        }
        guard let turns else {
            speakerKit = nil
            ErrorLog.append(model: model, step: .identifySpeakers,
                            technical: "Tidsgräns: SpeakerKit svarade inte på \(Int(limit)) s. Fortsätter utan talare.")
            throw SpeakerStepTimedOut(seconds: Int(limit))
        }
        ErrorLog.append(model: model, step: .identifySpeakers,
                        technical: "Info: SpeakerKit klar på \(Int(Self.seconds(clock.now - started))) s")
        return (turns, "SpeakerKit")
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
            if avoidsNeuralEngine {
                // Segmenteraren kör redan på processorn; bara embeddern använder Neural Engine.
                // Den körs då helt på processorn, inte på grafikkretsen: på MacBook Air M1 med
                // macOS 14 (2026-11-08) svarade SpeakerKit aldrig efter bytet till .cpuAndGPU,
                // utan att någon tråd räknade.
                config.diarizer = SpeakerKitDiarizer.pyannote(
                    config: config,
                    embedderModelInfo: .embedder(computeUnits: Self.speakerKitWithoutNeuralEngine)
                )
            }
            kit = try await SpeakerKit(config)
            speakerKit = kit
        }

        let diarizationOptions = PyannoteDiarizationOptions(numberOfSpeakers: speakers.exact)
        let progress = SpeakerProgressLog()
        let diarization = try await kit.diarize(audioArray: samples, options: diarizationOptions) { update in
            progress.report(update.fractionCompleted)
        }
        return diarization.segments.compactMap { segment -> SpeakerTurn? in
            guard let id = segment.speaker.speakerId else { return nil }
            return SpeakerTurn(start: Double(segment.startTime), end: Double(segment.endTime), speaker: id)
        }
    }
}

/// Skriver SpeakerKits förlopp i Felloggen var fjärdedel, så att en hängning visar om modellen
/// står still från början eller fastnar halvvägs. Anropas från SpeakerKits egna trådar.
final class SpeakerProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastQuarter = -1

    /// Den fjärdedel (0–4) som ska loggas för `fraction`, eller `nil` om den redan är loggad.
    func quarterToLog(_ fraction: Double) -> Int? {
        let quarter = Int((min(max(fraction, 0), 1) * 4).rounded(.down))
        lock.lock(); defer { lock.unlock() }
        guard quarter > lastQuarter else { return nil }
        lastQuarter = quarter
        return quarter
    }

    func report(_ fraction: Double) {
        guard let quarter = quarterToLog(fraction) else { return }
        Task { @MainActor in
            ErrorLog.append(model: "SpeakerKit", step: .identifySpeakers, technical: "Info: SpeakerKit \(quarter * 25) %")
        }
    }
}

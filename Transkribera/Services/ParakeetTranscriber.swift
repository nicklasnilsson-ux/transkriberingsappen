import CoreML
import FluidAudio
import Foundation
import TranskriberaCore

/// Kör Pianissimo (KlangAI:s svenska Parakeet TDT) lokalt med FluidAudio.
///
/// FluidAudio har egna typer med samma namn som WhisperKit och appen (t.ex.
/// `WordTiming` och `Language`), så biblioteket används bara i den här filen.
actor ParakeetTranscriber {
    enum TranscriberError: LocalizedError {
        case notLoaded

        var errorDescription: String? {
            "Pianissimo-modellen är inte inläst."
        }
    }

    /// Delarna som modellmappen måste innehålla (FluidAudios Parakeet v3-format).
    static let requiredFiles = [
        "Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json"
    ]

    /// Texten och Pianissimos egen säkerhet för den (0–1).
    struct Output {
        var segments: [SegmentData]
        var confidence: Double
    }

    /// Det som avgör hur `AsrManager` ställs in. Byts det skapas en ny.
    private struct Setup: Equatable {
        var carefulSeams: Bool
        var tuning: DecoderTuning
    }

    private var models: AsrModels?
    private var manager: AsrManager?
    private var setup: Setup?
    private var loadedFolder: URL?
    private var loadedWithoutNeuralEngine = false

    /// `avoidsNeuralEngine` kör modellen på processor och grafikkrets: en reserv när Core ML
    /// inte kan köra den på Neural Engine (sett på MacBook Air M1).
    func load(folder: URL, avoidsNeuralEngine: Bool = false) async throws {
        if models != nil, loadedFolder == folder, loadedWithoutNeuralEngine == avoidsNeuralEngine { return }
        unload()
        if avoidsNeuralEngine {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            models = try AsrModels.loadLocal(from: folder, version: .v3, configuration: configuration)
        } else {
            models = try AsrModels.loadLocal(from: folder, version: .v3)
        }
        loadedFolder = folder
        loadedWithoutNeuralEngine = avoidsNeuralEngine
    }

    func unload() {
        models = nil
        manager = nil
        setup = nil
        loadedFolder = nil
        loadedWithoutNeuralEngine = false
    }

    /// Långa inspelningar delas i fönster på 15 sekunder. Med `carefulSeams` provar
    /// FluidAudio flera sätt att skarva fönstren i början av filen och väljer det
    /// säkraste (tar 10–50 % längre tid). `tuning` ändras bara av Testlabbet.
    private func manager(_ setup: Setup) throws -> AsrManager {
        guard let models else { throw TranscriberError.notLoaded }
        if let manager, self.setup == setup { return manager }
        let config = ASRConfig(
            tdtConfig: TdtConfig(maxTokensPerChunk: setup.tuning.maxTokensPerChunk),
            dualDecodeArbitration: setup.carefulSeams,
            seamGapRepairMinGapSeconds: setup.tuning.seamGapRepairMinGapSeconds
        )
        let manager = AsrManager(config: config, models: models)
        self.manager = manager
        self.setup = setup
        return manager
    }

    /// Transkriberar 16 kHz mono-ljud. `progress` får andelen klar (0–1) och, om den finns, senaste texten.
    func transcribe(
        samples: [Float],
        carefulSeams: Bool = false,
        tuning: DecoderTuning = .production,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> Output {
        let manager = try manager(Setup(carefulSeams: carefulSeams, tuning: tuning))

        // FluidAudio rapporterar bara andel klar (för ljud över ca 15 s), ingen löpande text.
        let stream = await manager.transcriptionProgressStream
        let watcher = Task {
            do {
                for try await fraction in stream { progress(min(1, fraction), "") }
            } catch {}
        }
        defer { watcher.cancel() }

        let layers = await manager.decoderLayerCount
        var state = try TdtDecoderState(decoderLayers: layers)
        let result = try await manager.transcribe(samples, decoderState: &state)

        let tokens = (result.tokenTimings ?? []).map {
            TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime)
        }
        let words = TokenWords.words(from: tokens)
        let confidence = Double(result.confidence)
        if words.isEmpty {
            let text = TextCleaning.clean(result.text)
            let duration = Double(samples.count) / 16_000
            return Output(segments: text.isEmpty ? [] : [SegmentData(start: 0, end: duration, text: text)], confidence: confidence)
        }
        return Output(segments: SentenceSegmenter.segments(from: words), confidence: confidence)
    }

    /// Kortaste ljud (sekunder) som skickas till modellen. Kortare repliker ("Ja.") fylls ut
    /// med tystnad i slutet.
    static let shortestClip = 1.0

    /// Orden i en bit av ljudet ("Talare först"), med tider från början av hela ljudet
    /// (`offset` = bitens start i sekunder).
    func words(
        samples: [Float],
        offset: Double,
        carefulSeams: Bool = false,
        tuning: DecoderTuning = .production
    ) async throws -> [WordTimingData] {
        let manager = try manager(Setup(carefulSeams: carefulSeams, tuning: tuning))
        var clip = samples
        let shortest = Int(Self.shortestClip * 16_000)
        if clip.count < shortest { clip += [Float](repeating: 0, count: shortest - clip.count) }

        let layers = await manager.decoderLayerCount
        var state = try TdtDecoderState(decoderLayers: layers)
        let result = try await manager.transcribe(clip, decoderState: &state)
        let tokens = (result.tokenTimings ?? []).map {
            TimedToken(text: $0.token, start: $0.startTime + offset, end: $0.endTime + offset)
        }
        let words = TokenWords.words(from: tokens)
        if words.isEmpty {
            let text = TextCleaning.clean(result.text)
            let end = offset + Double(samples.count) / 16_000
            return text.isEmpty ? [] : [WordTimingData(word: " " + text, start: offset, end: end, probability: Double(result.confidence))]
        }
        return words
    }
}

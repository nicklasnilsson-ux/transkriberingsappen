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

    private var models: AsrModels?
    private var manager: AsrManager?
    private var carefulSeams = false
    private var loadedFolder: URL?

    func load(folder: URL) async throws {
        if models != nil, loadedFolder == folder { return }
        unload()
        models = try AsrModels.loadLocal(from: folder, version: .v3)
        loadedFolder = folder
    }

    func unload() {
        models = nil
        manager = nil
        loadedFolder = nil
    }

    /// Långa inspelningar delas i fönster på 15 sekunder. Med `carefulSeams` provar
    /// FluidAudio flera sätt att skarva fönstren i början av filen och väljer det
    /// säkraste (tar 10–50 % längre tid).
    private func manager(carefulSeams: Bool) throws -> AsrManager {
        guard let models else { throw TranscriberError.notLoaded }
        if let manager, self.carefulSeams == carefulSeams { return manager }
        let manager = AsrManager(config: ASRConfig(dualDecodeArbitration: carefulSeams), models: models)
        self.manager = manager
        self.carefulSeams = carefulSeams
        return manager
    }

    /// Transkriberar 16 kHz mono-ljud. `progress` får andelen klar (0–1) och, om den finns, senaste texten.
    func transcribe(
        samples: [Float],
        carefulSeams: Bool = false,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [SegmentData] {
        let manager = try manager(carefulSeams: carefulSeams)

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
        if words.isEmpty {
            let text = TextCleaning.clean(result.text)
            let duration = Double(samples.count) / 16_000
            return text.isEmpty ? [] : [SegmentData(start: 0, end: duration, text: text)]
        }
        return SentenceSegmenter.segments(from: words)
    }
}

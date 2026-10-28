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

    private var manager: AsrManager?
    private var loadedFolder: URL?

    func load(folder: URL) async throws {
        if manager != nil, loadedFolder == folder { return }
        unload()
        let models = try AsrModels.loadLocal(from: folder, version: .v3)
        manager = AsrManager(config: .default, models: models)
        loadedFolder = folder
    }

    func unload() {
        manager = nil
        loadedFolder = nil
    }

    /// Transkriberar 16 kHz mono-ljud. `progress` får andelen klar (0–1) och senaste texten.
    func transcribe(
        samples: [Float],
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [SegmentData] {
        guard let manager else { throw TranscriberError.notLoaded }

        await manager.setWindowHandler { window in
            let fraction = window.windowCount > 0 ? Double(window.index + 1) / Double(window.windowCount) : 0
            progress(min(1, fraction), window.text)
        }
        defer { Task { await manager.setWindowHandler(nil) } }

        let layers = await manager.decoderLayerCount
        var state = try TdtDecoderState(decoderLayers: layers)
        let result = try await manager.transcribe(samples, decoderState: &state)

        let words = buildWordTimings(from: result.tokenTimings ?? []).map { timing in
            WordTimingData(word: " " + timing.word, start: timing.startTime, end: timing.endTime, probability: 1)
        }
        if words.isEmpty {
            let text = TextCleaning.clean(result.text)
            let duration = Double(samples.count) / 16_000
            return text.isEmpty ? [] : [SegmentData(start: 0, end: duration, text: text)]
        }
        return SentenceSegmenter.segments(from: words)
    }
}

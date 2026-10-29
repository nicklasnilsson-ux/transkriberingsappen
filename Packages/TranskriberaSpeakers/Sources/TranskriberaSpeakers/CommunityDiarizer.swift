import FluidAudio
import Foundation
import TranskriberaCore

/// Talaridentifiering med pyannotes community-1-pipeline, som FluidAudio kör lokalt med
/// CoreML. Till skillnad från SpeakerKit 1.1.1 (segmenterare från pyannote 3) tar den
/// emot ett minsta och största antal talare.
///
/// FluidAudio har egna typer med samma namn som WhisperKit och appen, så biblioteket
/// används bara i det här paketet.
public actor CommunityDiarizer {
    /// macOS 14 har ett fel i Apples BNNS som kan krascha FluidAudios talaridentifiering
    /// (FluidAudio #878, rättat i macOS 15). Där används den gamla i stället.
    public static var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
    }

    private let modelsDirectory: URL
    private var models: OfflineDiarizerModels?

    /// Modellerna laddas ner till `modelsDirectory` första gången (några tiotal MB).
    public init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    /// Talarturer för ljud i 16 kHz mono.
    public func turns(samples: [Float], speakers: SpeakerCount) async throws -> [SpeakerTurn] {
        try await turns(samples: samples, config: Self.config(for: speakers))
    }

    func turns(samples: [Float], config: OfflineDiarizerConfig) async throws -> [SpeakerTurn] {
        let models = try await loadedModels()
        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)
        let result = try await manager.process(audio: samples)
        return Self.turns(from: result.segments.map {
            (id: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        })
    }

    /// - Parameter reembedShortTurns: Tal som inte fått något röstavtryck (oftast korta svar,
    ///   under 1 s) jämförs med talarnas röster i efterhand. Annars räknar FluidAudio dem
    ///   till talaren runt omkring, vilket gav precis felet att "Varje dag." hamnade hos
    ///   den som frågade (se `CommunityDiarizerTests`).
    static func config(for speakers: SpeakerCount, reembedShortTurns: Bool = true) -> OfflineDiarizerConfig {
        var config = OfflineDiarizerConfig(clustering: .community)
        if reembedShortTurns {
            config.zeroVoteReembed = OfflineDiarizerConfig.ZeroVoteReembed(enabled: true, minDurationSeconds: 0.3)
        }
        if let exact = speakers.exact {
            config.clustering.numSpeakers = exact
        } else {
            config.clustering.minSpeakers = speakers.minimum
            config.clustering.maxSpeakers = speakers.maximum
        }
        return config
    }

    /// FluidAudio namnger talarna "S1", "S2" …; appen numrerar dem från 0.
    static func turns(from segments: [(id: String, start: Double, end: Double)]) -> [SpeakerTurn] {
        var numbers: [String: Int] = [:]
        return segments.compactMap { segment in
            guard segment.end > segment.start else { return nil }
            let number: Int
            if let existing = numbers[segment.id] {
                number = existing
            } else {
                number = numbers.count
                numbers[segment.id] = number
            }
            return SpeakerTurn(start: segment.start, end: segment.end, speaker: number)
        }
    }

    private func loadedModels() async throws -> OfflineDiarizerModels {
        if let models { return models }
        let loaded = try await OfflineDiarizerModels.load(from: modelsDirectory)
        models = loaded
        return loaded
    }
}

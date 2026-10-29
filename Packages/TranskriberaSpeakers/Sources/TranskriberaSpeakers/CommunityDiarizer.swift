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

    /// Kortaste tal (sekunder) som får ett eget röstavtryck. Standard i community-1 är 1 s.
    /// Då fick ett kort svar som "Varje dag." (0,8 s) ingen tur alls och hamnade hos den som
    /// frågade; med 0,3 s blev alla repliker rätt i `CommunityDiarizerTests` (CI 2026-10-29).
    static let shortestEmbeddedSpeech = 0.3

    /// - Parameter shortTurns: Ge korta repliker egna röstavtryck, och jämför tal som ändå
    ///   saknar avtryck med talarnas röster i efterhand. `false` ger community-1:s standard,
    ///   bara för jämförelser i testerna.
    static func config(for speakers: SpeakerCount, shortTurns: Bool = true) -> OfflineDiarizerConfig {
        var config = OfflineDiarizerConfig(clustering: .community)
        if shortTurns {
            config.embedding.minSegmentDurationSeconds = shortestEmbeddedSpeech
            config.zeroVoteReembed = OfflineDiarizerConfig.ZeroVoteReembed(
                enabled: true, minDurationSeconds: shortestEmbeddedSpeech
            )
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

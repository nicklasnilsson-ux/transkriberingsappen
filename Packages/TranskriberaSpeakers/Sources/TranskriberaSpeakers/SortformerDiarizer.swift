import FluidAudio
import Foundation
import TranskriberaCore

/// Talaridentifiering med NVIDIAs Sortformer, som FluidAudio kör lokalt med CoreML. Den är
/// byggd för korta repliker och turtagning, men klarar högst fyra talare och tar inget
/// antal talare som önskemål.
///
/// FluidAudio har egna typer med samma namn, så det här heter något annat.
public actor ShortReplyDiarizer {
    public static let maximumSpeakers = 4

    /// macOS 14 har samma fel i Apples BNNS som community-1 (FluidAudio #878).
    public static var isSupported: Bool { CommunityDiarizer.isSupported }

    private var diarizer: SortformerDiarizer?

    public init() {}

    /// Talarturer för ljud i 16 kHz mono. Modellen laddas ner första gången.
    public func turns(samples: [Float]) async throws -> [SpeakerTurn] {
        let diarizer = try await loadedDiarizer()
        diarizer.reset()
        let timeline = try diarizer.processComplete(samples, sourceSampleRate: 16_000)
        return Self.turns(from: timeline.speakers.flatMap { index, speaker in
            speaker.finalizedSegments.map {
                (speaker: index, start: Double($0.startTime), end: Double($0.endTime))
            }
        })
    }

    /// Turerna i tidsordning; ogiltiga (tomma) turer tas bort.
    static func turns(from segments: [(speaker: Int, start: Double, end: Double)]) -> [SpeakerTurn] {
        segments
            .filter { $0.end > $0.start }
            .sorted { ($0.start, $0.speaker) < ($1.start, $1.speaker) }
            .map { SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) }
    }

    private func loadedDiarizer() async throws -> SortformerDiarizer {
        if let diarizer { return diarizer }
        let config = SortformerConfig.default
        let models = try await SortformerModels.loadFromHuggingFace(config: config)
        let created = SortformerDiarizer(config: config)
        created.initialize(models: models)
        diarizer = created
        return created
    }
}

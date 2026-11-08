import CoreML
import FluidAudio
import Foundation
import TranskriberaCore

/// Talaridentifiering med NVIDIAs Nemotron 3 Diarization (efterföljare till Sortformer),
/// som FluidAudio kör lokalt med CoreML. Den är byggd för korta repliker och turtagning,
/// klarar upp till åtta talare och tar inget antal talare som önskemål.
///
/// FluidAudio har egna typer med samma namn som appen, så biblioteket används bara i det
/// här paketet.
public actor ShortReplyDiarizer {
    public static let maximumSpeakers = 8

    /// Kortaste tal (sekunder) som blir en egen tur. Standard i FluidAudio är 0,2 s.
    static let shortestTurn: Float = 0.2

    /// macOS 14 har samma fel i Apples BNNS som community-1 (FluidAudio #878).
    public static var isSupported: Bool { CommunityDiarizer.isSupported }

    private var diarizer: Nemotron3Diarizer?
    private var loadedComputeUnits: MLComputeUnits?

    public init() {}

    /// Släpper modellen ur minnet. Den läses in igen nästa gång (från disk).
    public func unload() {
        diarizer = nil
        loadedComputeUnits = nil
    }

    /// Talarturer för ljud i 16 kHz mono. Modellen (några hundra MB) laddas ner första gången.
    /// `computeUnits` är `.all` utom när Neural Engine inte fungerar (se TranscriberService).
    public func turns(samples: [Float], computeUnits: MLComputeUnits = .all) async throws -> [SpeakerTurn] {
        let diarizer = try await loadedDiarizer(computeUnits: computeUnits)
        let (probabilities, frameCount) = try diarizer.processComplete(samples)
        let segments = Nemotron3Diarizer.segments(
            probabilities: probabilities,
            frameCount: frameCount,
            minDurationSeconds: Self.shortestTurn
        )
        return Self.turns(from: segments.map {
            (speaker: $0.speakerIndex, start: Double($0.startSeconds), end: Double($0.endSeconds))
        })
    }

    /// Turerna i tidsordning; ogiltiga (tomma) turer tas bort.
    static func turns(from segments: [(speaker: Int, start: Double, end: Double)]) -> [SpeakerTurn] {
        segments
            .filter { $0.end > $0.start }
            .sorted { ($0.start, $0.speaker) < ($1.start, $1.speaker) }
            .map { SpeakerTurn(start: $0.start, end: $0.end, speaker: $0.speaker) }
    }

    private func loadedDiarizer(computeUnits: MLComputeUnits) async throws -> Nemotron3Diarizer {
        if let diarizer, loadedComputeUnits == computeUnits { return diarizer }
        // "offline": 30 sekunders buffert, bäst kvalitet för färdiga inspelningar.
        let config = Nemotron3Config.offline
        let models = try await Nemotron3Models.loadFromHuggingFace(config: config, computeUnits: computeUnits)
        let created = Nemotron3Diarizer(config: config, models: models)
        diarizer = created
        loadedComputeUnits = computeUnits
        return created
    }
}

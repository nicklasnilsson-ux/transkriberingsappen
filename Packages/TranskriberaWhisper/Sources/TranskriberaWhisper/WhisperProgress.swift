import Foundation
import WhisperKit

/// Transkriberar med WhisperKit och rapporterar förlopp och text under tiden.
///
/// WhisperKit skickar inte vidare `segmentCallback` när ljudet delas upp med VAD (allt
/// som är längre än 30 sekunder). Förloppet stod därför på 0 % och ingen text visades
/// under hela transkriberingen. Här läses förloppet i stället från `WhisperKit.progress`,
/// som räknar alla delar även när de körs parallellt, och texten fångas med
/// `segmentDiscoveryCallback` på instansen, som är den VAD-uppdelningen använder.
public enum WhisperProgress {
    public static func transcribe(
        kit: WhisperKit,
        audioArray: [Float],
        decodeOptions: DecodingOptions,
        onProgress: @escaping @Sendable (Double) -> Void,
        onText: @escaping @Sendable (String) -> Void
    ) async throws -> [TranscriptionResult] {
        let tracker = ProgressTracker()
        let previousSegmentCallback = kit.segmentDiscoveryCallback
        kit.segmentDiscoveryCallback = { segments in
            if let text = segments.last?.text { onText(text) }
        }
        defer { kit.segmentDiscoveryCallback = previousSegmentCallback }

        let results = try await kit.transcribe(
            audioArray: audioArray,
            decodeOptions: decodeOptions,
            // Anropas för varje token som avkodas, i alla parallella delar.
            callback: { _ in
                tracker.advance(to: kit.progress.fractionCompleted, report: onProgress)
                return nil
            }
        )
        tracker.advance(to: 1, report: onProgress)
        return results
    }
}

/// Släpper bara igenom förlopp som har ökat märkbart, så att det aldrig går bakåt och
/// gränssnittet inte uppdateras för varje token. Rapporten görs under låset, så att
/// anrop från parallella delar inte kan komma fram i fel ordning.
final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0.0

    func advance(to fraction: Double, report: (Double) -> Void) {
        guard fraction.isFinite else { return }
        let fraction = min(1, fraction)
        lock.lock()
        defer { lock.unlock() }
        guard fraction >= last + 0.001 else { return }
        last = fraction
        report(fraction)
    }
}

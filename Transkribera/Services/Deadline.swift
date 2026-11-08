import Foundation

/// Kör ett jobb med tidsgräns. Går tiden ut släpps jobbet (det kan ligga kvar i bakgrunden om det
/// hänger sig i ett Core ML-anrop, som aldrig svarar på avbrott) och `nil` returneras.
/// Avbryts den som väntar (användaren trycker Avbryt) kastas `CancellationError` direkt.
@MainActor
enum Deadline {
    static func run<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T? {
        let task = Task<T, Error> { @MainActor in try await operation() }
        let wait = AbandonableWait<T>()
        var timedOut = false
        let timer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            timedOut = true
            wait.abandon()
        }
        defer { timer.cancel() }
        do {
            return try await withTaskCancellationHandler {
                try await wait.wait(for: task)
            } onCancel: {
                Task { @MainActor in wait.abandon() }
            }
        } catch is CancellationError {
            task.cancel()
            if timedOut { return nil }
            throw CancellationError()
        }
    }
}

/// Talarsteget tog för lång tid i båda modellerna. Texten blir klar utan talare.
struct SpeakerStepTimedOut: Error {
    let seconds: Int
}

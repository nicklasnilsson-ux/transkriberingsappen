import Foundation

/// Väntar på ett jobb men kan släppa det: `abandon()` får `wait` att kasta `CancellationError`
/// direkt, även om jobbet själv inte svarar på avbrott. Core ML-anrop som hänger sig (sett på en
/// MacBook Air M1 i steget "Identifierar talare") kontrollerar aldrig `Task.isCancelled`, så
/// "Avbryt transkriberingen" gjorde ingenting. Jobbet lever kvar i bakgrunden men resultatet kastas.
@MainActor
final class AbandonableWait<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    private var abandoned = false
    private(set) var isFinished = false

    /// Svarar när jobbet är klart, eller med `CancellationError` om `abandon()` anropats.
    func wait(for task: Task<T, Error>) async throws -> T {
        if abandoned { throw CancellationError() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            self.continuation = continuation
            Task { @MainActor in
                let result = await task.result
                self.finish(result)
            }
        }
    }

    func abandon() {
        abandoned = true
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<T, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        isFinished = true
        continuation.resume(with: result)
    }
}

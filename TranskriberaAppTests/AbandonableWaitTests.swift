import XCTest
@testable import Transkribera

/// "Avbryt transkriberingen" gjorde ingenting när ett Core ML-anrop hängde sig i steget
/// "Identifierar talare" (Nicklas, MacBook Air M1, 2026-11-08): jobbet svarar aldrig på avbrott.
@MainActor
final class AbandonableWaitTests: XCTestCase {
    /// Ett jobb som hänger tills testet släpper det, och som struntar i avbrott.
    private final class Hang {
        var release: CheckedContinuation<Int, Never>?
        lazy var task: Task<Int, Error> = Task { @MainActor in
            await withCheckedContinuation { self.release = $0 }
        }
        func finish(_ value: Int = 1) { release?.resume(returning: value); release = nil }
    }

    func testAbandonEndsTheWaitEvenWhenTheJobNeverAnswersCancellation() async throws {
        let hang = Hang()
        let wait = AbandonableWait<Int>()
        let task = hang.task
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            task.cancel()          // som kön gör: det hjälper inte
            wait.abandon()         // efter fristen
        }
        do {
            _ = try await wait.wait(for: task)
            XCTFail("väntan skulle ha avbrutits")
        } catch is CancellationError {
        }
        XCTAssertTrue(wait.isFinished)
        hang.finish()              // städa
    }

    func testAJobThatFinishesNormallyGivesItsResult() async throws {
        let wait = AbandonableWait<Int>()
        let task = Task<Int, Error> { 42 }
        let value = try await wait.wait(for: task)
        XCTAssertEqual(value, 42)
    }

    func testAbandoningBeforeWaitingEndsImmediately() async {
        let wait = AbandonableWait<Int>()
        wait.abandon()
        do {
            _ = try await wait.wait(for: Task<Int, Error> { 1 })
            XCTFail("väntan skulle ha avbrutits")
        } catch is CancellationError {
        } catch {
            XCTFail("fel fel: \(error)")
        }
    }

    func testAbandoningAfterTheResultIsAHarmlessNoOp() async throws {
        let wait = AbandonableWait<Int>()
        let value = try await wait.wait(for: Task<Int, Error> { 7 })
        wait.abandon()
        XCTAssertEqual(value, 7)
    }
}

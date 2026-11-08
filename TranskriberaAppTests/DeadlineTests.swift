import XCTest
@testable import Transkribera

/// Talarsteget hängde sig tyst på en MacBook Air M1 (8 GB, 2026-11-08). Varje talarmodell har
/// därför en tidsgräns: ett jobb som aldrig svarar släpps, och texten blir klar ändå.
@MainActor
final class DeadlineTests: XCTestCase {
    private final class Hang {
        var release: CheckedContinuation<Int, Never>?
        func run() async -> Int { await withCheckedContinuation { self.release = $0 } }
        func finish() { release?.resume(returning: 0); release = nil }
    }

    func testAJobThatNeverAnswersIsReleasedAtTheDeadline() async throws {
        let hang = Hang()
        let start = Date()
        let value = try await Deadline.run(seconds: 0.2) { await hang.run() }
        XCTAssertNil(value, "tidsgränsen ska ge nil, inte vänta för alltid")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        hang.finish()
    }

    func testAJobWithinTheDeadlineGivesItsResult() async throws {
        let value = try await Deadline.run(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testErrorsFromTheJobAreThrown() async {
        struct Boom: Error {}
        do {
            _ = try await Deadline.run(seconds: 5) { () async throws -> Int in throw Boom() }
            XCTFail("felet skulle ha kastats")
        } catch is Boom {
        } catch {
            XCTFail("fel fel: \(error)")
        }
    }

    func testCancellingTheCallerStopsWaitingAtOnce() async {
        let hang = Hang()
        let outer = Task { @MainActor in
            try await Deadline.run(seconds: 60) { await hang.run() }
        }
        try? await Task.sleep(for: .milliseconds(100))
        outer.cancel()
        let result = await outer.result
        if case .success = result { XCTFail("Avbryt ska ge CancellationError, inte ett tidsgränsvärde") }
        hang.finish()
    }

    func testSpeakerDeadlineGrowsWithTheAudio() {
        XCTAssertEqual(TranscriberService.speakerDeadline(audioSeconds: 0), 180)
        XCTAssertEqual(TranscriberService.speakerDeadline(audioSeconds: 300), 255)
        XCTAssertEqual(TranscriberService.speakerDeadline(audioSeconds: 3600), 1080)
    }
}

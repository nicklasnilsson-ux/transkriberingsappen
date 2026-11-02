import XCTest
@testable import TranskriberaCore

final class QueueHoldsTests: XCTestCase {
    func testNothingHeldByDefault() {
        XCTAssertFalse(QueueHolds().isHeld)
    }

    func testRecordingHoldsTheQueue() {
        XCTAssertTrue(QueueHolds(recording: true).isHeld)
    }

    func testTestLabHoldsTheQueue() {
        XCTAssertTrue(QueueHolds(testLab: true).isHeld)
    }

    func testReleasingOneReasonKeepsTheOtherHolding() {
        var holds = QueueHolds(testLab: true, recording: true)
        holds.recording = false
        XCTAssertTrue(holds.isHeld, "Testlabbet håller fortfarande")
        holds.testLab = false
        XCTAssertFalse(holds.isHeld)
    }

    func testImportDuringRecordingDoesNotNavigate() {
        XCTAssertFalse(ImportNavigation.shouldNavigate(recordingBusy: true))
        XCTAssertTrue(ImportNavigation.shouldNavigate(recordingBusy: false))
    }
}

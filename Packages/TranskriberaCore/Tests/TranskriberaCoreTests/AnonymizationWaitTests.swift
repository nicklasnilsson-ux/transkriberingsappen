import XCTest
@testable import TranskriberaCore

final class AnonymizationWaitTests: XCTestCase {
    /// Regression: tyst mötesinspelning gav noll stycken och "Anonymiserar…" snurrade för alltid.
    func testEmptyTranscriptNeverWaits() {
        XCTAssertFalse(AnonymizationWait.isWaiting(segmentCount: 0, hasCurrentResult: false))
    }

    func testWaitsOnlyWhileTextIsBeingProcessed() {
        XCTAssertTrue(AnonymizationWait.isWaiting(segmentCount: 3, hasCurrentResult: false))
        XCTAssertFalse(AnonymizationWait.isWaiting(segmentCount: 3, hasCurrentResult: true))
    }
}

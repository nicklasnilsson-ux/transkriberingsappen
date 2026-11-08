import XCTest
@testable import Transkribera

/// SpeakerKits förlopp loggas en gång per fjärdedel, så att Felloggen visar var en hängning stannade.
final class SpeakerProgressLogTests: XCTestCase {
    func testEachQuarterIsLoggedOnceAndInOrder() {
        let log = SpeakerProgressLog()
        let logged = [0, 0.1, 0.24, 0.25, 0.3, 0.5, 0.49, 0.75, 0.99, 1.0, 1.0].compactMap { log.quarterToLog($0) }
        XCTAssertEqual(logged, [0, 1, 2, 3, 4])
    }

    func testOutOfRangeValuesAreClamped() {
        let log = SpeakerProgressLog()
        XCTAssertEqual(log.quarterToLog(-1), 0)
        XCTAssertEqual(log.quarterToLog(7), 4)
        XCTAssertNil(log.quarterToLog(2))
    }
}

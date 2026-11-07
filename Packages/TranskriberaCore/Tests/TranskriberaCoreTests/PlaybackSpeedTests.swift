import XCTest
@testable import TranskriberaCore

final class PlaybackSpeedTests: XCTestCase {
    func testTheSpeedsNicklasAskedFor() {
        XCTAssertEqual(PlaybackSpeed.steps, [0.75, 1, 1.25, 1.5, 1.75, 2])
        XCTAssertEqual(PlaybackSpeed.normal, 1)
    }

    func testLabelsUseDecimalComma() {
        XCTAssertEqual(PlaybackSpeed.steps.map(PlaybackSpeed.label), ["0,75×", "1×", "1,25×", "1,5×", "1,75×", "2×"])
        XCTAssertEqual(PlaybackSpeed.menuLabel(1), "1× (Normal)")
        XCTAssertEqual(PlaybackSpeed.menuLabel(1.5), "1,5×")
    }

    func testFasterAndSlowerStopAtTheEnds() {
        XCTAssertEqual(PlaybackSpeed.faster(than: 1), 1.25)
        XCTAssertEqual(PlaybackSpeed.faster(than: 2), 2)
        XCTAssertEqual(PlaybackSpeed.slower(than: 1), 0.75)
        XCTAssertEqual(PlaybackSpeed.slower(than: 0.75), 0.75)
    }

    func testBrokenStoredValuesBecomeAValidStep() {
        XCTAssertEqual(PlaybackSpeed.clamped(0), 0.75)
        XCTAssertEqual(PlaybackSpeed.clamped(5), 2)
        XCTAssertEqual(PlaybackSpeed.clamped(1.3), 1.25)
        XCTAssertEqual(PlaybackSpeed.clamped(.nan), 1)
        XCTAssertTrue(PlaybackSpeed.isNormal(1.05))
    }
}

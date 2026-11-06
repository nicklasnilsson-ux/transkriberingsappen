import XCTest
@testable import TranskriberaCore

final class ReadingTextSizeTests: XCTestCase {
    func testStandardIs16() {
        XCTAssertEqual(ReadingTextSize.standard, 16)
        XCTAssertTrue(ReadingTextSize.steps.contains(ReadingTextSize.standard))
    }

    func testStepsUpAndDownAndStopsAtEnds() {
        XCTAssertEqual(ReadingTextSize.larger(than: 16), 18)
        XCTAssertEqual(ReadingTextSize.larger(than: 18), 20)
        XCTAssertEqual(ReadingTextSize.larger(than: 20), 20)
        XCTAssertEqual(ReadingTextSize.smaller(than: 16), 14)
        XCTAssertEqual(ReadingTextSize.smaller(than: 14), 14)
    }

    func testOddStoredValueSnapsToAStep() {
        XCTAssertEqual(ReadingTextSize.clamped(0), 14)
        XCTAssertEqual(ReadingTextSize.clamped(16.4), 16)
        XCTAssertEqual(ReadingTextSize.clamped(99), 20)
        XCTAssertEqual(ReadingTextSize.larger(than: 17.2), 20)
    }

    /// Den som sparat ett av de gamla stegen (13/15/17/20) får närmaste nya steg uppåt, aldrig mindre text.
    func testOldStepsBecomeTheNextLargerNewStep() {
        XCTAssertEqual(ReadingTextSize.clamped(13), 14)
        XCTAssertEqual(ReadingTextSize.clamped(15), 16)
        XCTAssertEqual(ReadingTextSize.clamped(17), 18)
        XCTAssertEqual(ReadingTextSize.clamped(20), 20)
    }

    func testColumnWidthFollowsTheTextSize() {
        XCTAssertEqual(ReadingTextSize.columnWidth(for: 16), 640)
        XCTAssertEqual(ReadingTextSize.columnWidth(for: 20), 800)
        // Ett trasigt sparat värde ger bredden för närmaste giltiga steg.
        XCTAssertEqual(ReadingTextSize.columnWidth(for: 14.5), ReadingTextSize.columnWidth(for: 14))
    }
}

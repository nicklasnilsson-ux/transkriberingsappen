import XCTest
@testable import TranskriberaCore

final class ReadingTextSizeTests: XCTestCase {
    func testStandardIs15() {
        XCTAssertEqual(ReadingTextSize.standard, 15)
        XCTAssertTrue(ReadingTextSize.steps.contains(ReadingTextSize.standard))
    }

    func testStepsUpAndDownAndStopsAtEnds() {
        XCTAssertEqual(ReadingTextSize.larger(than: 15), 17)
        XCTAssertEqual(ReadingTextSize.larger(than: 17), 20)
        XCTAssertEqual(ReadingTextSize.larger(than: 20), 20)
        XCTAssertEqual(ReadingTextSize.smaller(than: 15), 13)
        XCTAssertEqual(ReadingTextSize.smaller(than: 13), 13)
    }

    func testOddStoredValueSnapsToAStep() {
        XCTAssertEqual(ReadingTextSize.clamped(0), 13)
        XCTAssertEqual(ReadingTextSize.clamped(16.4), 17)
        XCTAssertEqual(ReadingTextSize.clamped(99), 20)
        XCTAssertEqual(ReadingTextSize.larger(than: 16), 17)
    }

    func testColumnWidthFollowsTheTextSize() {
        XCTAssertEqual(ReadingTextSize.columnWidth(for: 15), 600)
        XCTAssertEqual(ReadingTextSize.columnWidth(for: 20), 800)
        // Ett trasigt sparat värde ger bredden för närmaste giltiga steg.
        XCTAssertEqual(ReadingTextSize.columnWidth(for: 14.2), ReadingTextSize.columnWidth(for: 13))
    }
}

import XCTest
@testable import Transkribera

/// Talarchipen i "Vem är intervjuare?" bryts till nya rader i stället för att tryckas ihop
/// när det är många talare (12 talare visade bara hoptryckta chip utan namn).
final class FlowLayoutTests: XCTestCase {
    func testTwelveSpeakersWrapAndNoRowIsWiderThanTheSpace() {
        let widths = [CGFloat](repeating: 90, count: 12)
        let rows = FlowLayout.lines(widths: widths, maxWidth: 400, spacing: 12)
        XCTAssertGreaterThan(rows.count, 1)
        XCTAssertEqual(rows.flatMap { $0 }, Array(0..<12), "alla chip med, i ordning, inga dubbletter")
        for r in rows {
            let w = widths[r].reduce(0, +) + 12 * CGFloat(r.count - 1)
            XCTAssertLessThanOrEqual(w, 400)
        }
    }

    func testFewSpeakersStayOnOneRow() {
        XCTAssertEqual(FlowLayout.lines(widths: [90, 90, 90], maxWidth: 400, spacing: 12).count, 1)
    }

    func testAChipWiderThanTheSpaceGetsItsOwnRowInsteadOfBeingDropped() {
        let rows = FlowLayout.lines(widths: [90, 500, 90], maxWidth: 400, spacing: 12)
        XCTAssertEqual(rows, [0..<1, 1..<2, 2..<3])
    }

    func testNoSpeakersGivesNoRows() {
        XCTAssertTrue(FlowLayout.lines(widths: [], maxWidth: 400, spacing: 12).isEmpty)
    }
}

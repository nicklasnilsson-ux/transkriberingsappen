import XCTest
@testable import TranskriberaCore

/// "Ångra" efter en sparad rättning ska ge tillbaka både texten och ordtiderna, och bara det som ändrades.
final class EditUndoTests: XCTestCase {
    private let words = Data("ord".utf8)

    private func entry(_ index: Int, _ text: String, words: Data? = nil) -> EditUndo.Entry {
        EditUndo.Entry(index: index, text: text, wordsData: words)
    }

    func testNothingChangedGivesNothingToUndo() {
        let state = [entry(0, "a", words: words), entry(1, "b")]
        XCTAssertNil(EditUndo.changes(before: state, after: state))
    }

    func testOnlyTheChangedSegmentIsKept() throws {
        let before = [entry(0, "a", words: words), entry(1, "b", words: words), entry(2, "c")]
        let after = [entry(0, "a", words: words), entry(1, "B", words: nil), entry(2, "c")]
        let undo = try XCTUnwrap(EditUndo.changes(before: before, after: after))
        XCTAssertEqual(undo.entries, [entry(1, "b", words: words)])
    }

    func testTheWordTimingsComeBackWithTheText() throws {
        let before = [entry(4, "hej", words: words)]
        let after = [entry(4, "hej då", words: nil)]
        let undo = try XCTUnwrap(EditUndo.changes(before: before, after: after))
        XCTAssertEqual(undo.entries.first?.wordsData, words)
        XCTAssertEqual(undo.entries.first?.text, "hej")
    }

    func testChangedWordTimingsAloneCount() {
        XCTAssertNotNil(EditUndo.changes(before: [entry(0, "a", words: words)], after: [entry(0, "a", words: nil)]))
    }

    func testASegmentThatIsGoneFromTheAfterStateIsIgnored() {
        XCTAssertNil(EditUndo.changes(before: [entry(0, "a"), entry(1, "b")], after: [entry(0, "a")]))
    }
}

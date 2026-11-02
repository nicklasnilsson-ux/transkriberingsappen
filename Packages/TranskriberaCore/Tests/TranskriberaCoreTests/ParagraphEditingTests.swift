import XCTest
@testable import TranskriberaCore

/// Ett stycke rättas i ett fält; ändringen ska hamna i rätt segment och inget annat får ändras.
final class ParagraphEditingTests: XCTestCase {
    let texts = [" Jag börjar med ärendena.", " Sedan tar jag de akuta.", " Efter lunch blir det möten."]
    var joined: String { ParagraphEditing.join(texts) }

    private func split(_ edited: String) -> [String] { ParagraphEditing.split(texts, edited: edited) }

    func testJoinMatchesTheParagraphView() {
        XCTAssertEqual(joined, "Jag börjar med ärendena. Sedan tar jag de akuta. Efter lunch blir det möten.")
        XCTAssertEqual(ParagraphEditing.join(["a", "  ", "b"]), "a b")
    }

    func testUnchangedTextKeepsEverySegmentExactly() {
        XCTAssertEqual(split(joined), texts)
        XCTAssertEqual(split("Jag börjar med ärendena.\nSedan tar jag de akuta. Efter lunch blir det möten."), texts)
    }

    func testWordInTheMiddleSegmentChangesOnlyThatSegment() {
        XCTAssertEqual(
            split("Jag börjar med ärendena. Sedan tar jag de brådskande. Efter lunch blir det möten."),
            [texts[0], "Sedan tar jag de brådskande.", texts[2]]
        )
    }

    func testFirstWordOfASegmentStaysInThatSegment() {
        XCTAssertEqual(
            split("Jag börjar med ärendena. Då tar jag de akuta. Efter lunch blir det möten."),
            [texts[0], "Då tar jag de akuta.", texts[2]]
        )
    }

    func testAddedWordsGoToTheSegmentBefore() {
        XCTAssertEqual(split("Jag börjar med ärendena idag. Sedan tar jag de akuta. Efter lunch blir det möten.")[0],
                       "Jag börjar med ärendena idag.")
        XCTAssertEqual(split(joined + " Sen går jag hem.")[2], "Efter lunch blir det möten. Sen går jag hem.")
    }

    func testSeveralEditsInDifferentSegmentsEachLandInTheirSegment() {
        XCTAssertEqual(
            split("XJag börjar med uppgifterna. Sedan tar jag de akuta. Efter lunch blir det mötena."),
            ["XJag börjar med uppgifterna.", texts[1], "Efter lunch blir det mötena."]
        )
    }

    func testDeletingAWholeSegmentLeavesItEmpty() {
        XCTAssertEqual(split("Jag börjar med ärendena. Efter lunch blir det möten."), [texts[0], "", texts[2]])
    }

    func testEditAcrossABoundary() {
        XCTAssertEqual(
            split("Jag börjar med ärendena och tar de akuta. Efter lunch blir det möten."),
            ["Jag börjar med ärendena och", "tar de akuta.", texts[2]]
        )
    }

    func testEmptySegmentsAreLeftAlone() {
        XCTAssertEqual(ParagraphEditing.split(["Hej.", "", "Hejdå."], edited: "Hej där. Hejdå."), ["Hej där.", "", "Hejdå."])
    }

    func testTheSegmentsAlwaysJoinBackToTheEditedText() {
        let edits = [
            joined,
            "Jag börjar. Efter lunch blir det möten.",
            "Helt ny text.",
            "Jag börjar med ärendena. Sedan tar jag de akuta.Efter lunch blir det möten.",
            "Jag Sedan Efter",
            "a",
        ]
        for edited in edits {
            let normalized = edited.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            XCTAssertEqual(ParagraphEditing.join(split(edited)), normalized, edited)
        }
    }
}

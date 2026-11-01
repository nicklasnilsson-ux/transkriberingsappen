import XCTest
@testable import TranskriberaCore

/// Rättning i den anonymiserade texten får aldrig skriva över de dolda uppgifterna i originalet.
final class AnonymizedEditingTests: XCTestCase {
    private func edit(original: String, shown: String, edited: String) -> String? {
        AnonymizedEditing(original: original, shown: shown)?.originalText(applying: edited)
    }

    func testEditOutsideAPlaceholderKeepsTheHiddenValue() {
        let result = edit(
            original: "Jag heter Anna Svensson och bor i Lund.",
            shown: "Jag heter [PERSON 1] och bor i Lund.",
            edited: "Jag heter [PERSON 1] och bor i Malmö."
        )
        XCTAssertEqual(result, "Jag heter Anna Svensson och bor i Malmö.")
    }

    func testEditBeforeAPlaceholderKeepsTheHiddenValue() {
        let result = edit(
            original: "Hej, jag heter Anna Svensson.",
            shown: "Hej, jag heter [PERSON 1].",
            edited: "Hej där, jag heter [PERSON 1]."
        )
        XCTAssertEqual(result, "Hej där, jag heter Anna Svensson.")
    }

    func testAppendingAfterTheLastPlaceholder() {
        let result = edit(original: "Det var Anna", shown: "Det var [PERSON 1]", edited: "Det var [PERSON 1] igen")
        XCTAssertEqual(result, "Det var Anna igen")
    }

    func testTwoPlaceholdersAndEditBetweenThem() {
        let result = edit(
            original: "Anna ringde Erik i går.",
            shown: "[PERSON 1] ringde [PERSON 2] i går.",
            edited: "[PERSON 1] mejlade [PERSON 2] i går."
        )
        XCTAssertEqual(result, "Anna mejlade Erik i går.")
    }

    func testTouchingAPlaceholderReplacesTheWholeValue() {
        let result = edit(
            original: "Jag heter Anna Svensson och bor i Lund.",
            shown: "Jag heter [PERSON 1] och bor i Lund.",
            edited: "Jag heter Eva och bor i Lund."
        )
        XCTAssertEqual(result, "Jag heter Eva och bor i Lund.")
    }

    func testTypingInsideAPlaceholderReplacesTheWholeValue() {
        let result = edit(
            original: "Det var Anna där.",
            shown: "Det var [PERSON 1] där.",
            edited: "Det var [PERSONX 1] där."
        )
        XCTAssertEqual(result, "Det var [PERSONX 1] där.")
    }

    func testDeletingAWordNextToAPlaceholderKeepsTheValue() {
        let result = edit(
            original: "Hej Anna Svensson, välkommen.",
            shown: "Hej [PERSON 1], välkommen.",
            edited: "[PERSON 1], välkommen."
        )
        XCTAssertEqual(result, "Anna Svensson, välkommen.")
    }

    func testUnchangedTextGivesBackTheOriginalExactly() {
        let original = "Anna Svensson bor i Lund."
        XCTAssertEqual(edit(original: original, shown: "[PERSON 1] bor i Lund.", edited: "[PERSON 1] bor i Lund."), original)
    }

    func testWithoutPlaceholdersTheEditIsTheNewText() {
        XCTAssertEqual(edit(original: "Hej alla", shown: "Hej alla", edited: "Hej allihopa"), "Hej allihopa")
    }

    func testTextThatCannotBeMappedBackIsNotEditable() {
        // Två platshållare utan text emellan går inte att dela upp i originalet.
        XCTAssertNil(AnonymizedEditing(original: "AnnaErik", shown: "[PERSON 1][PERSON 2]"))
        // Den visade texten stämmer inte med originalet.
        XCTAssertNil(AnonymizedEditing(original: "Något helt annat", shown: "Hej [PERSON 1]"))
    }

    func testRealAnonymizerOutputRoundTrips() {
        let rules = AnonymizationOptions(useSystemNameRecognition: false)
        let original = "Mitt personnummer är 19850101-1234 och jag trivs."
        let shown = Anonymizer.anonymize(original, options: rules)
        XCTAssertNotEqual(shown, original)
        let result = edit(original: original, shown: shown, edited: shown.replacingOccurrences(of: "trivs", with: "mår bra"))
        XCTAssertEqual(result, "Mitt personnummer är 19850101-1234 och jag mår bra.")
    }
}

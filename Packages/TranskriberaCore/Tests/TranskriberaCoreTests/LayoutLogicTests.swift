import XCTest
@testable import TranskriberaCore

final class LayoutLogicTests: XCTestCase {
    func testRetranscribeNeedsConfirmationWhenTextExists() {
        XCTAssertNil(RetranscribeConfirmation(replacingText: true, confirmed: false))
        XCTAssertNotNil(RetranscribeConfirmation(replacingText: true, confirmed: true))
    }

    func testRetryAfterFailureNeedsNoConfirmation() {
        XCTAssertNotNil(RetranscribeConfirmation(replacingText: false, confirmed: false))
    }

    func testDialogWarnsAboutCorrectionsAndSpeakerNames() {
        XCTAssertTrue(RetranscribeConfirmation.dialogMessage.contains("Rättningar"))
        XCTAssertTrue(RetranscribeConfirmation.dialogMessage.contains("talarnamn"))
    }

    func testCollapseHasHysteresis() {
        XCTAssertFalse(TitleCardCollapse.isCollapsed(offset: 100, wasCollapsed: false))
        XCTAssertFalse(TitleCardCollapse.isCollapsed(offset: 260, wasCollapsed: false))
        XCTAssertTrue(TitleCardCollapse.isCollapsed(offset: 261, wasCollapsed: false))
        // Kvar hopfälld mellan 200 och 260 på väg upp.
        XCTAssertTrue(TitleCardCollapse.isCollapsed(offset: 230, wasCollapsed: true))
        XCTAssertTrue(TitleCardCollapse.isCollapsed(offset: 200, wasCollapsed: true))
        XCTAssertFalse(TitleCardCollapse.isCollapsed(offset: 199, wasCollapsed: true))
        // Utfälld mellan 200 och 260 på väg ner.
        XCTAssertFalse(TitleCardCollapse.isCollapsed(offset: 230, wasCollapsed: false))
    }

    func testNegativeOffsetFromOverscrollIsExpanded() {
        XCTAssertFalse(TitleCardCollapse.isCollapsed(offset: -30, wasCollapsed: true))
    }
}

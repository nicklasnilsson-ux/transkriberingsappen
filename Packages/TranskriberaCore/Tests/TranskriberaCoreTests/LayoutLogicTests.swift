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
        // Medan sökfältet är öppet i raden fälls den inte ut, så att fältet inte tappar fokus.
        XCTAssertTrue(TitleCardCollapse.isCollapsed(offset: 0, wasCollapsed: true, keepCollapsed: true))
        XCTAssertFalse(TitleCardCollapse.isCollapsed(offset: 0, wasCollapsed: false, keepCollapsed: true))
    }

    func testMiniPlayerSizesGrowAndKeepAspect() {
        let sizes = MiniPlayerSize.allCases
        XCTAssertEqual(sizes, [.small, .medium, .large])
        XCTAssertTrue(MiniPlayerSize.small.width < MiniPlayerSize.medium.width)
        XCTAssertTrue(MiniPlayerSize.medium.width < MiniPlayerSize.large.width)
        for size in sizes {
            XCTAssertEqual(size.height, (size.width * 9 / 16).rounded())
        }
    }

    func testMiniPlayerSizeDefaultsToSmall() {
        XCTAssertEqual(MiniPlayerSize.resolved(nil), .small)
        XCTAssertEqual(MiniPlayerSize.resolved("skräp"), .small)
        XCTAssertEqual(MiniPlayerSize.resolved("large"), .large)
    }

    func testDeleteNeedsConfirmationAndSomethingToDelete() {
        XCTAssertNil(DeleteConfirmation(count: 3, confirmed: false))
        XCTAssertNil(DeleteConfirmation(count: 0, confirmed: true))
        XCTAssertNotNil(DeleteConfirmation(count: 3, confirmed: true))
    }

    func testBulkDialogsNameHowManyAreAffected() {
        XCTAssertTrue(DeleteConfirmation.title(count: 4).contains("4"))
        XCTAssertTrue(DeleteConfirmation.message(count: 4).contains("4"))
        XCTAssertTrue(BulkRetranscribe.title(count: 4).contains("4"))
        XCTAssertTrue(BulkRetranscribe.message(count: 4).contains("4"))
        XCTAssertTrue(BulkRetranscribe.message(count: 4).contains("Rättningar"))
        XCTAssertEqual(DeleteConfirmation.title(count: 1), "Radera 1 transkribering?")
    }

    func testRerunIsNotChangedWhenChoicesMatchTheFile() {
        XCTAssertFalse(RerunChange.isChanged(
            modelOnFile: "KB Large ordagrann (jämnad volym)", chosenModel: nil,
            languageOnFile: "sv", chosenLanguage: nil,
            identifiedSpeakersOnFile: true, chosenIdentify: nil,
            speakerCountOnFile: 2, chosenExactSpeakers: nil))
        // Samma värden valda uttryckligen räknas inte som ändring.
        XCTAssertFalse(RerunChange.isChanged(
            modelOnFile: "KB Large ordagrann (jämnad volym)", chosenModel: "KB Large ordagrann",
            languageOnFile: "sv", chosenLanguage: "sv",
            identifiedSpeakersOnFile: true, chosenIdentify: true,
            speakerCountOnFile: 2, chosenExactSpeakers: 2))
    }

    func testRerunIsChangedWhenAnyChoiceDiffers() {
        func changed(model: String? = nil, language: String? = nil, identify: Bool? = nil, speakers: Int? = nil) -> Bool {
            RerunChange.isChanged(
                modelOnFile: "Pianissimo", chosenModel: model,
                languageOnFile: "sv", chosenLanguage: language,
                identifiedSpeakersOnFile: true, chosenIdentify: identify,
                speakerCountOnFile: 2, chosenExactSpeakers: speakers)
        }
        XCTAssertTrue(changed(model: "KB Large ordagrann"))
        XCTAssertTrue(changed(language: "en"))
        XCTAssertTrue(changed(language: "auto"))
        XCTAssertTrue(changed(identify: false))
        XCTAssertTrue(changed(speakers: 3))
    }
}

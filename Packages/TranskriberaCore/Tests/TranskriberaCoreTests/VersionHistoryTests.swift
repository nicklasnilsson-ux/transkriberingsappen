import XCTest
@testable import TranskriberaCore

final class VersionHistoryTests: XCTestCase {
    private func slot(_ minute: Int) -> VersionSlot {
        VersionSlot(id: UUID(), date: Date(timeIntervalSince1970: Double(minute) * 60))
    }

    func testCapacityIsFourIncludingTheShownVersion() {
        XCTAssertEqual(VersionHistory.capacity, 4)
    }

    func testNothingIsDroppedWhileThereIsRoom() {
        // Tre sparade + den nya = 4: ingenting raderas.
        XCTAssertEqual(VersionHistory.idsToDrop(existing: []), [])
        XCTAssertEqual(VersionHistory.idsToDrop(existing: [slot(1), slot(2)]), [])
        XCTAssertEqual(VersionHistory.idsToDrop(existing: [slot(1), slot(2), slot(3)]), [])
    }

    func testTheFifthVersionDropsTheOldestAndNothingElse() {
        let v = [slot(30), slot(10), slot(20), slot(40)] // fyra sparade + den nya = 5
        let dropped = VersionHistory.idsToDrop(existing: v)
        XCTAssertEqual(dropped, [v[1].id]) // den med minut 10, oavsett ordning i listan
    }

    func testSeveralAreDroppedIfTheListsomehowIsTooLong() {
        let v = [slot(1), slot(2), slot(3), slot(4), slot(5)]
        XCTAssertEqual(VersionHistory.idsToDrop(existing: v), [v[0].id, v[1].id, v[2].id])
    }

    func testPositionAndLatest() {
        let v = [slot(30), slot(10), slot(20)]
        XCTAssertEqual(VersionHistory.position(of: v[1].id, in: v)?.number, 1)
        XCTAssertEqual(VersionHistory.position(of: v[0].id, in: v)?.number, 3)
        XCTAssertEqual(VersionHistory.position(of: v[0].id, in: v)?.total, 3)
        XCTAssertNil(VersionHistory.position(of: UUID(), in: v))
        XCTAssertTrue(VersionHistory.isLatest(v[0].id, in: v))
        XCTAssertFalse(VersionHistory.isLatest(v[2].id, in: v))
    }

    func testLabelAlwaysCarriesTheTime() {
        XCTAssertEqual(VersionHistory.label(number: 2, total: 4, time: "14:32"), "Version 2 av 4 · 14:32")
    }

    func testDialogKindAndWhenItIsShown() {
        XCTAssertEqual(RetranscribeDialog.kind(versionCount: 1), .roomLeft(versions: 1))
        XCTAssertEqual(RetranscribeDialog.kind(versionCount: 3), .roomLeft(versions: 3))
        XCTAssertEqual(RetranscribeDialog.kind(versionCount: 4), .replacesOldest)
        // Av i Inställningar stänger bara av dialogen när det finns plats.
        XCTAssertFalse(RetranscribeDialog.needsDialog(versionCount: 2, askSetting: false))
        XCTAssertTrue(RetranscribeDialog.needsDialog(versionCount: 2, askSetting: true))
        XCTAssertTrue(RetranscribeDialog.needsDialog(versionCount: 4, askSetting: false))
        XCTAssertTrue(RetranscribeDialog.canSuppress(.roomLeft(versions: 2)))
        XCTAssertFalse(RetranscribeDialog.canSuppress(.replacesOldest))
    }

    func testFullDialogNamesWhatIsDeletedOnTheButton() {
        XCTAssertTrue(RetranscribeDialog.confirmButton(.replacesOldest).contains("radera"))
        XCTAssertEqual(RetranscribeDialog.confirmButton(.roomLeft(versions: 1)), "Transkribera igen")
    }

    func testSnapshotKeepsTextSpeakersAndWordTimes() throws {
        let words = [WordTimingData(word: " hej", start: 1, end: 1.5, probability: 0.9, uncertainSpeaker: true)]
        let segments = [
            SegmentData(start: 1, end: 2, text: "hej", speaker: "Maria", words: words, uncertainSpeaker: true),
            SegmentData(start: 2, end: 3, text: "där", speaker: nil),
        ]
        let back = try VersionSnapshot.decode(VersionSnapshot(segments: segments).encoded())
        XCTAssertEqual(back.segments, segments)
    }
}

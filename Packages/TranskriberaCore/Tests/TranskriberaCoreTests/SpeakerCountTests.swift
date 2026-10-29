import XCTest
@testable import TranskriberaCore

final class SpeakerCountTests: XCTestCase {
    func testEveryChoiceSurvivesSaving() {
        for choice in SpeakerCount.choices {
            XCTAssertEqual(SpeakerCount(rawValue: choice.rawValue), choice, choice.rawValue)
        }
        XCTAssertEqual(Set(SpeakerCount.choices.map(\.rawValue)).count, SpeakerCount.choices.count)
    }

    func testAutomaticMeansAtLeastTwo() {
        XCTAssertEqual(SpeakerCount.automatic.minimum, 2)
        XCTAssertNil(SpeakerCount.automatic.maximum)
        XCTAssertNil(SpeakerCount.automatic.exact)
        XCTAssertEqual(SpeakerCount.choices.first, SpeakerCount.automatic)
    }

    func testRawValues() {
        XCTAssertEqual(SpeakerCount(rawValue: "3"), SpeakerCount.exactly(3))
        XCTAssertEqual(SpeakerCount(rawValue: "2-4"), SpeakerCount(minimum: 2, maximum: 4))
        XCTAssertEqual(SpeakerCount(rawValue: "min3"), SpeakerCount(minimum: 3, maximum: nil))
        XCTAssertEqual(SpeakerCount(rawValue: "2-2"), SpeakerCount.exactly(2))
        XCTAssertNil(SpeakerCount(rawValue: "4-2"))
        XCTAssertNil(SpeakerCount(rawValue: "0"))
        XCTAssertNil(SpeakerCount(rawValue: "tre"))
    }

    /// Den gamla inställningen (heltal) ska ge samma val efter uppdateringen.
    func testLegacySetting() {
        XCTAssertEqual(SpeakerCount(legacyCount: 0), SpeakerCount.automatic)
        XCTAssertEqual(SpeakerCount(legacyCount: 3), SpeakerCount.exactly(3))
    }

    func testLabels() {
        XCTAssertEqual(SpeakerCount.automatic.label, "Automatiskt, minst 2")
        XCTAssertEqual(SpeakerCount(minimum: 2, maximum: 4).label, "2–4 talare")
        XCTAssertEqual(SpeakerCount.exactly(3).label, "3 talare")
    }
}

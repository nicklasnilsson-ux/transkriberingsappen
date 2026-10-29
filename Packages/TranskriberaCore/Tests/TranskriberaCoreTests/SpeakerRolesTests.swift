import XCTest
@testable import TranskriberaCore

final class SpeakerRolesTests: XCTestCase {
    func testInterviewerAndCustomersInOrderOfAppearance() {
        let names = SpeakerRoles.names(for: ["Talare 1", "Talare 2", "Talare 3"], interviewer: "Talare 2")
        XCTAssertEqual(names, ["Talare 2": "Intervjuare", "Talare 1": "Kund 1", "Talare 3": "Kund 2"])
    }

    func testOneCustomer() {
        let names = SpeakerRoles.names(for: ["Talare 1", "Talare 2"], interviewer: "Talare 1")
        XCTAssertEqual(names, ["Talare 1": "Intervjuare", "Talare 2": "Kund 1"])
    }

    /// Rollerna får aldrig anonymiseras bort (fel i 0.5.2).
    func testRolesAreNotAnonymized() {
        for role in SpeakerRoles.names(for: ["A", "B", "C", "D"], interviewer: "A").values {
            XCTAssertTrue(NameDetector.isGenericSpeaker(role), role)
        }
    }

    func testAsksOnlyForUnnamedSpeakers() {
        XCTAssertTrue(SpeakerRoles.needsRoles(["Talare 1", "Talare 2"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Talare 1"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Intervjuare", "Kund 1"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Talare 1", "Anna"]))
    }
}

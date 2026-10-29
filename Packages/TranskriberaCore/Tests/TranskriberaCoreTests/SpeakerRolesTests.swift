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

    func testSeveralInterviewersAreNumbered() {
        let names = SpeakerRoles.names(
            for: ["Talare 1", "Talare 2", "Talare 3", "Talare 4"], interviewers: ["Talare 1", "Talare 3"]
        )
        XCTAssertEqual(names, [
            "Talare 1": "Intervjuare 1", "Talare 2": "Kund 1", "Talare 3": "Intervjuare 2", "Talare 4": "Kund 2",
        ])
        for role in names.values {
            XCTAssertTrue(NameDetector.isGenericSpeaker(role), role)
        }
    }

    /// Att lägga till eller ta bort en intervjuare i efterhand utgår från rollnamnen.
    func testRolesCanBeChangedAfterwards() {
        let speakers = ["Intervjuare", "Kund 1", "Kund 2"]
        let added = SpeakerRoles.names(for: speakers, interviewers: ["Intervjuare", "Kund 1"])
        XCTAssertEqual(added, ["Intervjuare": "Intervjuare 1", "Kund 1": "Intervjuare 2", "Kund 2": "Kund 1"])
        let removed = SpeakerRoles.names(for: Array(added.values.sorted()), interviewers: ["Intervjuare 1"])
        XCTAssertEqual(removed["Intervjuare 1"], "Intervjuare")
        XCTAssertEqual(removed["Intervjuare 2"], "Kund 1")
    }

    func testRecognizesInterviewerRoles() {
        XCTAssertTrue(SpeakerRoles.isInterviewer("Intervjuare"))
        XCTAssertTrue(SpeakerRoles.isInterviewer("Intervjuare 2"))
        XCTAssertFalse(SpeakerRoles.isInterviewer("Kund 1"))
        XCTAssertFalse(SpeakerRoles.isInterviewer("Intervjuaren Anna"))
    }
}

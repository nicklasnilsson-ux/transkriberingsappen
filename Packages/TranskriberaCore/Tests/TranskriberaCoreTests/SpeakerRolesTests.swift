import XCTest
@testable import TranskriberaCore

final class SpeakerRolesTests: XCTestCase {
    /// Övriga talare behåller sitt "Talare N", så att ett namn aldrig byter person.
    func testOthersKeepTheirNumber() {
        let names = SpeakerRoles.names(for: ["Talare 1", "Talare 2", "Talare 3"], interviewer: "Talare 2")
        XCTAssertEqual(names, ["Talare 2": "Intervjuare", "Talare 1": "Talare 1", "Talare 3": "Talare 3"])
    }

    func testOneOtherSpeaker() {
        let names = SpeakerRoles.names(for: ["Talare 1", "Talare 2"], interviewer: "Talare 1")
        XCTAssertEqual(names, ["Talare 1": "Intervjuare", "Talare 2": "Talare 2"])
    }

    /// "Kund" kommer inte tillbaka (Nicklas 2026-11-10): inga namn som appen sätter börjar med Kund.
    func testNoRoleIsEverKund() {
        let inputs: [[String]] = [
            ["Talare 1", "Talare 2", "Talare 3", "Talare 4"],
            ["A", "B", "C"],
            ["Intervjuare", "Kund 1", "Kund 2"],
            ["Intervjuare 1", "Intervjuare 2", "Talare 1"],
        ]
        for speakers in inputs {
            for count in 0...speakers.count {
                let names = SpeakerRoles.names(for: speakers, interviewers: Set(speakers.prefix(count)))
                for name in names.values {
                    XCTAssertFalse(name.lowercased().hasPrefix("kund"), "\(speakers) → \(name)")
                    XCTAssertTrue(SpeakerRoles.isInterviewer(name) || SpeakerRoles.speakerNumber(name) != nil, name)
                }
                XCTAssertEqual(Set(names.values).count, Set(speakers).count, "två talare fick samma namn: \(names)")
            }
        }
    }

    /// Rollerna får aldrig anonymiseras bort (fel i 0.5.2).
    func testRolesAreNotAnonymized() {
        for role in SpeakerRoles.names(for: ["A", "B", "C", "D"], interviewer: "A").values {
            XCTAssertTrue(NameDetector.isGenericSpeaker(role), role)
        }
        // Äldre transkriberingar har kvar "Kund N"; det är fortfarande en roll.
        XCTAssertTrue(NameDetector.isGenericSpeaker("Kund 1"))
    }

    func testAsksOnlyForUnnamedSpeakers() {
        XCTAssertTrue(SpeakerRoles.needsRoles(["Talare 1", "Talare 2"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Talare 1"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Intervjuare", "Talare 1"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Intervjuare", "Kund 1"]))
        XCTAssertFalse(SpeakerRoles.needsRoles(["Talare 1", "Anna"]))
    }

    func testSeveralInterviewersAreNumbered() {
        let names = SpeakerRoles.names(
            for: ["Talare 1", "Talare 2", "Talare 3", "Talare 4"], interviewers: ["Talare 1", "Talare 3"]
        )
        XCTAssertEqual(names, [
            "Talare 1": "Intervjuare 1", "Talare 2": "Talare 2", "Talare 3": "Intervjuare 2", "Talare 4": "Talare 4",
        ])
        for role in names.values {
            XCTAssertTrue(NameDetector.isGenericSpeaker(role), role)
        }
    }

    /// Att lägga till eller ta bort en intervjuare i efterhand utgår från rollnamnen.
    func testRolesCanBeChangedAfterwards() {
        let speakers = ["Intervjuare", "Talare 2", "Talare 3"]
        let added = SpeakerRoles.names(for: speakers, interviewers: ["Intervjuare", "Talare 2"])
        XCTAssertEqual(added, ["Intervjuare": "Intervjuare 1", "Talare 2": "Intervjuare 2", "Talare 3": "Talare 3"])
        // Den som inte längre är intervjuare får det lägsta lediga numret.
        let removed = SpeakerRoles.names(for: ["Intervjuare 1", "Intervjuare 2", "Talare 3"], interviewers: ["Intervjuare 1"])
        XCTAssertEqual(removed, ["Intervjuare 1": "Intervjuare", "Intervjuare 2": "Talare 1", "Talare 3": "Talare 3"])
    }

    /// Äldre transkriberingar med "Kund N" får "Talare N" när rollerna ändras.
    func testLegacyKundBecomesTalare() {
        let names = SpeakerRoles.names(for: ["Intervjuare", "Kund 1", "Kund 2"], interviewers: ["Intervjuare"])
        XCTAssertEqual(names, ["Intervjuare": "Intervjuare", "Kund 1": "Talare 1", "Kund 2": "Talare 2"])
    }

    func testRecognizesInterviewerRoles() {
        XCTAssertTrue(SpeakerRoles.isInterviewer("Intervjuare"))
        XCTAssertTrue(SpeakerRoles.isInterviewer("Intervjuare 2"))
        XCTAssertFalse(SpeakerRoles.isInterviewer("Talare 1"))
        XCTAssertFalse(SpeakerRoles.isInterviewer("Intervjuaren Anna"))
    }
}

import Foundation
import XCTest
@testable import TranskriberaCore

final class SpeakerMoveTests: XCTestCase {
    func testTargetsAreTheOtherSpeakersInOrder() {
        XCTAssertEqual(SpeakerMove.targets(speakers: ["Intervjuare", "Talare 1", "Talare 2"], current: "Talare 1"), ["Intervjuare", "Talare 2"])
        XCTAssertEqual(SpeakerMove.targets(speakers: ["Talare 1"], current: "Talare 1"), [])
        XCTAssertEqual(SpeakerMove.targets(speakers: ["Talare 1", "Talare 2"], current: nil), ["Talare 1", "Talare 2"])
    }

    /// Övriga talare heter "Talare N", aldrig "Kund N" (Nicklas 2026-11-10).
    func testNewNameIsTalareAlsoWithRoles() {
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Intervjuare", "Talare 1", "Talare 3"]), "Talare 4")
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Intervjuare"]), "Talare 1")
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Intervjuare 1", "Intervjuare 2", "Talare 2"]), "Talare 3")
        // Äldre transkribering med "Kund N": nya talare får ändå "Talare N".
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Intervjuare", "Kund 1", "Kund 2"]), "Talare 1")
    }

    func testNewNameWithoutRoles() {
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Talare 1", "Talare 2"]), "Talare 3")
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Talare 1", "Talare 4"]), "Talare 5")
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: ["Anna", "Bertil"]), "Talare 1")
        XCTAssertEqual(SpeakerMove.suggestedNewName(existing: []), "Talare 1")
    }

    func testNewNameIsNeverTaken() {
        for existing in [["Talare 1", "Talare 2"], ["Intervjuare", "Talare 1"], ["Talare 2", "Talare 1", "Intervjuare"], ["Intervjuare", "Kund 1"]] {
            XCTAssertFalse(existing.contains(SpeakerMove.suggestedNewName(existing: existing)))
        }
    }

    func testClearingUncertaintyRemovesTheMark() throws {
        let words = [
            WordTimingData(word: "Varje", start: 0, end: 0.3, probability: 0.9, uncertainSpeaker: true),
            WordTimingData(word: "dag.", start: 0.3, end: 0.6, probability: 0.9, uncertainSpeaker: true),
        ]
        let data = try JSONEncoder().encode(words)
        XCTAssertTrue(WordTimingData.hasUncertainSpeaker(inEncoded: data))

        let cleared = try XCTUnwrap(SpeakerMove.clearingUncertainty(data))
        XCTAssertFalse(WordTimingData.hasUncertainSpeaker(inEncoded: cleared))
        let decoded = try JSONDecoder().decode([WordTimingData].self, from: cleared)
        XCTAssertEqual(decoded.map(\.word), ["Varje", "dag."], "orden och tiderna ska finnas kvar")
        XCTAssertEqual(decoded.map(\.start), [0, 0.3])
    }

    func testClearingUncertaintyLeavesCertainWordsAlone() throws {
        XCTAssertNil(SpeakerMove.clearingUncertainty(nil))
        let data = try JSONEncoder().encode([WordTimingData(word: "Ja.", start: 0, end: 0.2, probability: 1)])
        XCTAssertEqual(SpeakerMove.clearingUncertainty(data), data)
        let broken = Data(#"{"uncertainSpeaker":true"#.utf8)
        XCTAssertEqual(SpeakerMove.clearingUncertainty(broken), broken, "oläsliga ordtider ska inte försvinna")
    }

    func testUndoOnlyWhileTheMoveStillHolds() {
        let undo = SpeakerMove.Undo(entries: [.init(index: 3, speaker: "Talare 1", wordsData: nil)], speaker: "Talare 2")
        XCTAssertTrue(undo.canUndo(currentSpeakers: [3: "Talare 2"]))
        XCTAssertFalse(undo.canUndo(currentSpeakers: [3: "Intervjuare"]), "talaren har fått en roll sedan bytet")
        XCTAssertFalse(undo.canUndo(currentSpeakers: [:]), "segmentet finns inte längre")
        XCTAssertFalse(SpeakerMove.Undo(entries: [], speaker: "Talare 2").canUndo(currentSpeakers: [:]))
    }
}

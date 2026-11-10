import SwiftData
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Byte av talare på ett stycke eller en rad: bara de valda segmenten flyttas, ⚠ försvinner,
/// stycken från samma talare slås ihop och bytet går att ångra. Texterna är påhittade.
@MainActor
final class SpeakerMoveAppTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func word(_ text: String, _ start: Double, uncertain: Bool? = nil) -> WordTimingData {
        WordTimingData(word: text, start: start, end: start + 1, probability: 0.9, uncertainSpeaker: uncertain)
    }

    /// Intervjuare frågar, kunden svarar, ett kort svar har hamnat hos intervjuaren (med ⚠), intervjuaren fortsätter.
    private func transcript() -> Transcript {
        let t = Transcript(title: "Prov", mediaFileName: "x.m4a", originalFileName: "x.m4a", isVideo: false, duration: 8, modelName: "M0")
        context.insert(t)
        t.replaceSegments(with: [
            SegmentData(start: 0, end: 2, text: "Hur ofta?", speaker: "Intervjuare", words: [word("Hur", 0), word("ofta?", 1)]),
            SegmentData(start: 2, end: 4, text: "Ganska ofta.", speaker: "Talare 1", words: [word("Ganska", 2), word("ofta.", 3)]),
            SegmentData(start: 4, end: 6, text: "Varje dag.", speaker: "Intervjuare", words: [word("Varje", 4, uncertain: true), word("dag.", 5, uncertain: true)]),
            SegmentData(start: 6, end: 8, text: "Okej.", speaker: "Intervjuare", words: [word("Okej.", 6)]),
        ], in: context)
        return t
    }

    private func speakers(_ t: Transcript) -> [String?] { t.sortedSegments.map(\.speaker) }

    private func paragraphCount(_ t: Transcript) -> Int {
        AnalysisExporter.paragraphRanges(t.segmentData).count
    }

    func testMovingOneRowChangesOnlyThatRowAndClearsTheMark() throws {
        let t = transcript()
        XCTAssertTrue(t.sortedSegments[2].isSpeakerUncertain)
        let undo = try XCTUnwrap(t.moveSegments([2], to: "Talare 1"))
        XCTAssertEqual(speakers(t), ["Intervjuare", "Talare 1", "Talare 1", "Intervjuare"])
        XCTAssertFalse(t.sortedSegments[2].isSpeakerUncertain, "⚠ ska bort när användaren själv valt talare")
        XCTAssertEqual(t.sortedSegments[2].words.map(\.word), ["Varje", "dag."], "ordtiderna ska finnas kvar")
        XCTAssertEqual(undo.speaker, "Talare 1")
    }

    func testParagraphsFromTheSameSpeakerMerge() {
        let t = transcript()
        XCTAssertEqual(paragraphCount(t), 3)
        _ = t.moveSegments([2], to: "Talare 1")
        XCTAssertEqual(paragraphCount(t), 3, "svaret följer med talarens stycke; intervjuaren får ett eget efter")
        _ = t.moveSegments([2, 3], to: "Intervjuare")
        _ = t.moveSegments([1], to: "Intervjuare")
        XCTAssertEqual(paragraphCount(t), 1, "allt hos samma talare blir ett stycke")
    }

    func testUndoGivesBackSpeakerAndMark() throws {
        let t = transcript()
        let undo = try XCTUnwrap(t.moveSegments([2], to: "Talare 1"))
        XCTAssertTrue(t.canUndo(undo))
        t.undo(undo)
        XCTAssertEqual(speakers(t), ["Intervjuare", "Talare 1", "Intervjuare", "Intervjuare"])
        XCTAssertTrue(t.sortedSegments[2].isSpeakerUncertain)
    }

    func testNewSpeakerAppearsInTheList() throws {
        let t = transcript()
        let name = SpeakerMove.suggestedNewName(existing: t.speakers)
        XCTAssertEqual(name, "Talare 2")
        _ = try XCTUnwrap(t.moveSegments([3], to: name))
        XCTAssertEqual(t.speakers, ["Intervjuare", "Talare 1", "Talare 2"])
    }

    func testUndoIsRefusedAfterARename() throws {
        let t = transcript()
        let undo = try XCTUnwrap(t.moveSegments([2], to: "Talare 1"))
        t.renameSpeaker("Talare 1", to: "Maria")
        XCTAssertFalse(t.canUndo(undo))
        t.undo(undo)
        XCTAssertEqual(speakers(t), ["Intervjuare", "Maria", "Maria", "Intervjuare"], "Ångra får inte ge tillbaka ett namn som inte finns")
    }

    func testNothingToUndoWhenNothingChanged() {
        let t = transcript()
        XCTAssertNil(t.moveSegments([0], to: "Intervjuare"))
        XCTAssertNil(t.moveSegments([1], to: "  "))
    }
}

import SwiftData
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Rollvalet ("Vem av talarna är du?") går att ångra: talarna återställs exakt som de var.
/// Texterna är påhittade.
@MainActor
final class RoleChoiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func transcript() -> Transcript {
        let t = Transcript(title: "Prov", mediaFileName: "x.m4a", originalFileName: "x.m4a", isVideo: false, duration: 6, modelName: "M0")
        context.insert(t)
        t.replaceSegments(with: [
            SegmentData(start: 0, end: 2, text: "Hej.", speaker: "Talare 1"),
            SegmentData(start: 2, end: 4, text: "Hallå.", speaker: "Talare 2"),
            SegmentData(start: 4, end: 6, text: "Ja.", speaker: "Talare 1"),
        ], in: context)
        return t
    }

    func testChoosingAnInterviewerCanBeUndone() {
        let t = transcript()
        let before = t.speakerSnapshot
        t.setInterviewer("Talare 1")
        XCTAssertNotEqual(t.speakerSnapshot, before)
        XCTAssertEqual(t.sortedSegments.map(\.speaker), ["Intervjuare", "Kund 1", "Intervjuare"])
        t.restoreSpeakers(before)
        XCTAssertEqual(t.sortedSegments.map(\.speaker), ["Talare 1", "Talare 2", "Talare 1"])
    }

    func testRestoreIgnoresASnapshotFromAnotherText() {
        let t = transcript()
        t.restoreSpeakers(["Annan"])
        XCTAssertEqual(t.sortedSegments.map(\.speaker), ["Talare 1", "Talare 2", "Talare 1"])
    }
}

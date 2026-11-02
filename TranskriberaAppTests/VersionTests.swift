import SwiftData
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Sparade versioner av texten: den förra sparas vid "Transkribera igen", högst 4 behålls och
/// den äldsta raderas (aldrig den nya), och byte mellan versioner tappar ingenting.
/// Texterna är påhittade.
@MainActor
final class VersionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private func output(_ text: String, speaker: String = "Talare 1") -> TranscriptionOutput {
        TranscriptionOutput(
            segments: [SegmentData(start: 0, end: 2, text: text, speaker: speaker,
                                   words: [WordTimingData(word: text, start: 0, end: 2, probability: 0.9)])],
            language: "sv"
        )
    }

    private func transcript() -> Transcript {
        let t = Transcript(title: "Prov", mediaFileName: "x.m4a", originalFileName: "x.m4a", isVideo: false, duration: 2, modelName: "M0")
        context.insert(t)
        t.addNewVersion(output("första"), previousModelName: "", in: context, now: Date(timeIntervalSince1970: 1_000))
        return t
    }

    private func texts(_ t: Transcript) -> [String] { t.sortedSegments.map(\.text) }

    func testFirstTranscriptionHasOneVersionAndNoPicker() {
        let t = transcript()
        XCTAssertEqual(t.versionCount, 1)
        XCTAssertTrue(t.versions.isEmpty)
        XCTAssertNil(t.versionLabel)
    }

    func testRerunSavesThePreviousVersionWithItsCorrections() {
        let t = transcript()
        t.sortedSegments[0].updateText("första, rättad")
        t.renameSpeaker("Talare 1", to: "Maria")
        t.addNewVersion(output("andra"), previousModelName: "M0", in: context, now: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(texts(t), ["andra"])
        XCTAssertEqual(t.versionCount, 2)
        let saved = t.versions[0].segments
        XCTAssertEqual(saved.map(\.text), ["första, rättad"])
        XCTAssertEqual(saved.map(\.speaker), ["Maria"])
        XCTAssertEqual(t.versions[0].modelName, "M0")
    }

    func testSwitchingBackAndForthLosesNothing() {
        let t = transcript()
        t.sortedSegments[0].updateText("första, rättad")
        t.addNewVersion(output("andra"), previousModelName: "M0", in: context, now: Date(timeIntervalSince1970: 2_000))
        let first = t.versions[0]
        t.switchTo(first, in: context)
        XCTAssertEqual(texts(t), ["första, rättad"])
        XCTAssertTrue(t.isViewingOlderVersion)
        XCTAssertEqual(t.versionCount, 2)
        // Rättning i den äldre versionen sparas i den versionen.
        t.sortedSegments[0].updateText("första, rättad igen")
        t.switchTo(t.versions[0], in: context)
        XCTAssertEqual(texts(t), ["andra"])
        XCTAssertFalse(t.isViewingOlderVersion)
        t.switchTo(t.versions[0], in: context)
        XCTAssertEqual(texts(t), ["första, rättad igen"])
    }

    func testTheFifthVersionDeletesTheOldestAndNothingElse() {
        let t = transcript()
        for (i, name) in ["andra", "tredje", "fjärde"].enumerated() {
            t.addNewVersion(output(name), previousModelName: "M", in: context, now: Date(timeIntervalSince1970: Double(2_000 + i * 1_000)))
        }
        XCTAssertEqual(t.versionCount, 4)
        t.addNewVersion(output("femte"), previousModelName: "M", in: context, now: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(t.versionCount, 4)
        XCTAssertEqual(texts(t), ["femte"])
        let kept = t.versions.sorted { $0.date < $1.date }.map { $0.segments.first?.text }
        XCTAssertEqual(kept, ["andra", "tredje", "fjärde"]) // "första" (den äldsta) är borta
        let all = (try? context.fetch(FetchDescriptor<TranscriptVersion>())) ?? []
        XCTAssertEqual(all.count, 3, "Raderade versioner ska inte ligga kvar i databasen")
    }

    func testSwitchingNeverChangesTheNumberOfVersions() {
        let t = transcript()
        for (i, name) in ["andra", "tredje", "fjärde"].enumerated() {
            t.addNewVersion(output(name), previousModelName: "M", in: context, now: Date(timeIntervalSince1970: Double(2_000 + i * 1_000)))
        }
        for _ in 0..<6 {
            t.switchTo(t.versions.min { $0.date < $1.date }!, in: context)
            XCTAssertEqual(t.versionCount, 4)
        }
    }

    func testWordTimesAndModelFollowTheVersion() {
        let t = transcript()
        t.addNewVersion(output("andra"), previousModelName: "M0", in: context, now: Date(timeIntervalSince1970: 2_000))
        t.modelName = "M1"
        t.switchTo(t.versions[0], in: context)
        XCTAssertEqual(t.modelName, "M0")
        XCTAssertEqual(t.sortedSegments[0].words.count, 1)
        XCTAssertEqual(t.language, "sv")
    }

    func testDeletingATranscriptDeletesItsVersions() {
        let t = transcript()
        t.addNewVersion(output("andra"), previousModelName: "M0", in: context, now: Date(timeIntervalSince1970: 2_000))
        context.delete(t)
        try? context.save()
        XCTAssertEqual(((try? context.fetch(FetchDescriptor<TranscriptVersion>())) ?? []).count, 0)
    }
}

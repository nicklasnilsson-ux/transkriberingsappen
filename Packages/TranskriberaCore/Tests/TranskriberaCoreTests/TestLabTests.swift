import XCTest
@testable import TranskriberaCore

final class DecoderTuningTests: XCTestCase {
    /// Vanliga transkriberingar får inte ändras av Testlabbet. Värdena är WhisperKit 1.1.1:s
    /// och FluidAudio 0.17.7:s egna standardvärden, utom antal omkörningar (3), som appen
    /// alltid har använt. Ändras något här ändras alla transkriberingar.
    func testProductionMatchesWhatTheAppHasAlwaysUsed() {
        let tuning = DecoderTuning.production
        XCTAssertEqual(tuning.compressionRatioThreshold, 2.4)
        XCTAssertEqual(tuning.logProbThreshold, -1.0)
        XCTAssertEqual(tuning.windowClipTime, 1.0)
        XCTAssertEqual(tuning.temperatureFallbackCount, 3)
        XCTAssertTrue(tuning.repairsGaps)
        XCTAssertEqual(tuning.seamGapRepairMinGapSeconds, 1.5)
        XCTAssertEqual(tuning.maxTokensPerChunk, 150)
        XCTAssertEqual(tuning, DecoderTuning())
        XCTAssertEqual(tuning.differences, [])
    }

    func testDifferencesAreSpelledOut() {
        var tuning = DecoderTuning.production
        tuning.compressionRatioThreshold = nil
        tuning.maxTokensPerChunk = 300
        XCTAssertEqual(tuning.differences, ["upprepningsspärr av", "max 300 bitar per fönster"])
    }
}

final class TestLabPlanTests: XCTestCase {
    let plan = TestLabPlan.standard

    func testRunsHaveUniqueNumberedIDsInOrder() {
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        for (index, run) in plan.enumerated() {
            XCTAssertTrue(run.id.hasPrefix(String(format: "%02d-", index + 1)), run.id)
            XCTAssertNil(run.id.rangeOfCharacter(from: CharacterSet(charactersIn: "åäöÅÄÖ /:")), run.id)
        }
    }

    /// Referensen körs två gånger med KB (för bruset) och en gång med Pianissimo, utan ändringar.
    func testReferencesChangeNothing() {
        let references = plan.filter { $0.differences.isEmpty }
        XCTAssertEqual(references.map(\.id), ["01-kb-referens", "02-kb-referens-igen", "10-pianissimo-referens"])
    }

    /// Varje försök ändrar en sak, utom de två som uttryckligen kombinerar spärrarna.
    func testEachExperimentChangesOneThing() {
        let combined: Set = ["05-kb-utan-bada-sparrarna", "09-kb-allt-lost"]
        for run in plan where !run.differences.isEmpty && !combined.contains(run.id) {
            XCTAssertEqual(run.differences.count, 1, "\(run.id): \(run.differences)")
        }
        for id in combined {
            XCTAssertGreaterThan(plan.first { $0.id == id }?.differences.count ?? 0, 1, id)
        }
    }
}

final class TestLabReportTests: XCTestCase {
    func testSummaryLineHasOneFieldPerColumn() {
        var report = TestLabReport(
            run: TestLabRun(id: "01-x", title: "KB; test", engine: .kbLargeStrict),
            appVersion: "0.6.0",
            startedAt: Date(timeIntervalSince1970: 0)
        )
        report.seconds = .init(total: 210.24, transcription: 120, gapCheck: 90)
        report.words = 2500
        report.whisperSegments = [
            .init(start: 0, end: 5, words: 10, temperature: 0, averageLogProbability: -0.2, compressionRatio: 1.4, noSpeechProbability: 0.01),
            .init(start: 5, end: 9, words: 3, temperature: 0.4, averageLogProbability: -1.3, compressionRatio: 2.6, noSpeechProbability: 0.2)
        ]
        let columns = TestLabReport.summaryHeader.split(separator: ";", omittingEmptySubsequences: false).count
        let fields = report.summaryLine.split(separator: ";", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, columns)
        XCTAssertEqual(fields[1], "KB, test")
        XCTAssertEqual(fields[3], "210,2")
        XCTAssertEqual(fields[8], "1")
    }

    func testReportCarriesNoText() throws {
        let report = TestLabReport(run: TestLabPlan.standard[0], appVersion: "0.6.0", startedAt: Date())
        let json = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))
        XCTAssertFalse(json.contains("\"text\""))
    }
}

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
        XCTAssertNil(tuning.stylePrompt)
        XCTAssertTrue(tuning.stylePromptInGapCheck)
        XCTAssertEqual(tuning, DecoderTuning())
        XCTAssertEqual(tuning.differences, [])
    }

    func testStylePromptIsReported() {
        var tuning = DecoderTuning.production
        tuning.stylePrompt = "Eh, mm."
        XCTAssertEqual(tuning.differences, ["ledtråd \"Eh, mm.\""])
        tuning.stylePromptInGapCheck = false
        XCTAssertEqual(tuning.differences.count, 2)
    }

    func testDifferencesAreSpelledOut() {
        var tuning = DecoderTuning.production
        tuning.compressionRatioThreshold = nil
        tuning.maxTokensPerChunk = 300
        XCTAssertEqual(tuning.differences, ["upprepningsspärr av", "max 300 bitar per fönster"])
    }
}

final class TestLabTimingPlanTests: XCTestCase {
    let plan = TestLabPlan.timing

    func testRunsHaveUniqueNumberedIDsInOrder() {
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        for (index, run) in plan.enumerated() {
            XCTAssertTrue(run.id.hasPrefix(String(format: "%02d-", index + 1)), run.id)
            XCTAssertNil(run.id.rangeOfCharacter(from: CharacterSet(charactersIn: "åäöÅÄÖ /:")), run.id)
        }
    }

    /// Varje modell mäts en gång utan och en gång med talare, och inget annat ändras,
    /// så att tiderna gäller en vanlig transkribering.
    func testEveryModelWithAndWithoutSpeakers() {
        for engine in TestLabRun.Engine.allCases where engine.isInModelPicker {
            let runs = plan.filter { $0.engine == engine }
            XCTAssertEqual(Set(runs.map(\.speakers)), [.none, .own], engine.rawValue)
        }
        for run in plan {
            XCTAssertTrue(run.engine.isInModelPicker, run.id)
            XCTAssertEqual(run.tuning, .production, run.id)
            XCTAssertEqual(run.differences.count, 1, "\(run.id): \(run.differences)")
        }
    }

    /// Listorna som visas i Testlabbet. De gamla (jämför inställningar, precision) är borttagna
    /// respektive dolda sedan 2026-11-13; ingen ska komma tillbaka utan att någon valt det.
    func testOfferedListsAreTheCurrentOnes() {
        XCTAssertEqual(TestLabPlan.Kind.offered, [.crossCheck, .timing])
        XCTAssertEqual(TestLabPlan.Kind.allCases.count, 3, "crossCheck, timing och den dolda precisionslistan")
        XCTAssertEqual(TestLabPlan.Kind.timing.runs, TestLabPlan.timing)
        XCTAssertEqual(TestLabPlan.Kind.crossCheck.runs, TestLabPlan.crossCheck)
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
        XCTAssertEqual(fields[15], "1")
    }

    /// Hela kedjan = ljudet + körningen (med talare) + anonymiseringen, utan inläsningen av
    /// modellen, och räknas om till sekunder per timme ljud.
    func testWholeProcessPerHour() {
        var report = TestLabReport(run: TestLabPlan.timing[1], appVersion: "0.9.20", startedAt: Date())
        report.seconds = .init(total: 20, transcription: 9, gapCheck: 0, modelLoad: 30, audio: 3, speakers: 11, anonymization: 1)
        report.audioMinutes = 18
        XCTAssertEqual(report.seconds?.wholeProcess, 24)
        XCTAssertEqual(try XCTUnwrap(report.wholeProcessPerHour), 80, accuracy: 0.001)
        let header = TestLabReport.summaryHeader.split(separator: ";", omittingEmptySubsequences: false)
        let fields = report.summaryLine.split(separator: ";", omittingEmptySubsequences: false)
        XCTAssertEqual(fields.count, header.count)
        XCTAssertEqual(fields[header.firstIndex(of: "sekunder hela kedjan")!], "24,0")
        XCTAssertEqual(fields[header.firstIndex(of: "sekunder per timme ljud")!], "80,0")
    }

    func testReportCarriesNoText() throws {
        let report = TestLabReport(run: TestLabPlan.timing[0], appVersion: "0.6.0", startedAt: Date())
        let json = try XCTUnwrap(String(data: report.encoded(), encoding: .utf8))
        XCTAssertFalse(json.contains("\"text\""))
    }

    /// 2026-11-13: samma Pianissimo i 8, 16 och 32 bitar, och inget annat som skiljer.
    func testPrecisionListComparesOnlyThePrecision() {
        let plan = TestLabPlan.Kind.precision.runs
        XCTAssertEqual(plan.map(\.engine), [.pianissimo, .pianissimoFP16, .pianissimoFP32])
        XCTAssertEqual(Set(plan.map(\.id)).count, 3)
        XCTAssertEqual(plan[0].differences, [], "Referensen är en vanlig transkribering")
        XCTAssertEqual(plan[1].differences, ["kodaren i 16 bitar i stället för 8"])
        XCTAssertEqual(plan[2].differences, ["hela modellen i 32 bitar"])
        XCTAssertTrue(plan.allSatisfy { $0.tuning == .production && $0.speakers == .shared && !$0.carefulSeams })
    }

    /// 2026-11-13: korskollen är en vanlig Pianissimo plus KB Large, och bara den listan korskollar.
    func testCrossCheckListIsPianissimoCheckedByKBLarge() {
        let plan = TestLabPlan.Kind.crossCheck.runs
        XCTAssertEqual(plan.map(\.engine), [.pianissimo])
        XCTAssertEqual(plan[0].differences, ["ord att lyssna på markerade med KB Large"])
        XCTAssertTrue(plan.allSatisfy { $0.crossCheck && $0.tuning == .production && $0.speakers == .shared })
        for kind in TestLabPlan.Kind.allCases where kind != .crossCheck {
            XCTAssertFalse(kind.runs.contains(where: \.crossCheck), kind.title)
        }
    }
}

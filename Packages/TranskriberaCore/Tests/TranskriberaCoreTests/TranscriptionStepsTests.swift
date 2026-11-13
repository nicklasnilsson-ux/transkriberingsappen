import XCTest
@testable import TranskriberaCore

final class TranscriptionStepsTests: XCTestCase {
    func testWhisperWithSpeakersAndModelHasFiveSteps() {
        let plan = TranscriptionStep.plan(needsModel: true, checksGaps: true, identifiesSpeakers: true)
        XCTAssertEqual(plan, [.model, .audio, .transcribe, .gapCheck, .speakers])
        XCTAssertEqual(TranscriptionStep.label(for: .model, in: plan), "Steg 1 av 5")
        XCTAssertEqual(TranscriptionStep.label(for: .speakers, in: plan), "Steg 5 av 5")
    }

    func testPianissimoWithLoadedModelSkipsModelAndGapCheck() {
        let plan = TranscriptionStep.plan(needsModel: false, checksGaps: false, identifiesSpeakers: false)
        XCTAssertEqual(plan, [.audio, .transcribe])
        XCTAssertEqual(TranscriptionStep.label(for: .transcribe, in: plan), "Steg 2 av 2")
        XCTAssertNil(TranscriptionStep.label(for: .gapCheck, in: plan))
    }

    func testCrossCheckIsTheLastStep() {
        let plan = TranscriptionStep.plan(needsModel: false, checksGaps: false, identifiesSpeakers: true, crossChecks: true)
        XCTAssertEqual(plan, [.audio, .transcribe, .speakers, .crossCheck])
        XCTAssertEqual(TranscriptionStep.label(for: .crossCheck, in: plan), "Steg 4 av 4")
    }

    func testNoLabelForASingleStepOrNoPlan() {
        XCTAssertNil(TranscriptionStep.label(for: .transcribe, in: [.transcribe]))
        XCTAssertNil(TranscriptionStep.label(for: .model, in: []))
    }
}

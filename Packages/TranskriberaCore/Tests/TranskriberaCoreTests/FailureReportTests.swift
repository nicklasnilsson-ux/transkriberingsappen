import XCTest
@testable import TranskriberaCore

final class FailureReportTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824
    private let nicklasError = "Unable to compute the asynchronous prediction using ML Program. It can be an invalid input data or broken/unsupported model."

    func testNicklasErrorIsRecognisedAsModelFailure() {
        XCTAssertTrue(FailureExplainer.isModelComputeFailure(nicklasError))
        XCTAssertFalse(FailureExplainer.isModelComputeFailure("Filen innehåller inget ljud"))
    }

    func testEightGigabyteMacIsLowMemory() {
        XCTAssertTrue(FailureExplainer.isLowMemory(8 * gib))
        XCTAssertFalse(FailureExplainer.isLowMemory(16 * gib))
        XCTAssertFalse(FailureExplainer.isLowMemory(0))
    }

    func testMessageNamesStepMemoryAndKeepsTechnicalText() {
        let text = FailureExplainer.message(step: .recognize, technical: nicklasError, physicalMemory: 8 * gib)
        XCTAssertTrue(text.contains("Taligenkänning"))
        XCTAssertTrue(text.contains("8 GB"))
        XCTAssertTrue(text.contains("ladda ned modellen igen"))
        XCTAssertTrue(text.contains(nicklasError))
    }

    func testOtherErrorsGetNoModelAdvice() {
        let text = FailureExplainer.message(step: .prepareAudio, technical: "Filen är trasig", physicalMemory: 8 * gib)
        XCTAssertFalse(text.contains("Core ML"))
        XCTAssertTrue(text.contains("Filen är trasig"))
    }

    func testEveryStepHasALabel() {
        for step in FailureStep.allCases { XCTAssertFalse(step.label.isEmpty) }
    }

    func testLogEntryIsOneLineAndTrimKeepsNewest() {
        let line = FailureExplainer.logEntry(
            date: Date(timeIntervalSince1970: 0), appVersion: "1", model: "Pianissimo",
            step: .recognize, physicalMemory: 8 * gib, technical: "a\nb"
        )
        XCTAssertFalse(line.contains("\n"))
        let log = (1...300).map { "rad \($0)" }.joined(separator: "\n") + "\n"
        let trimmed = FailureExplainer.trimmedLog(log, keeping: 200)
        XCTAssertTrue(trimmed.hasSuffix("rad 300\n"))
        XCTAssertFalse(trimmed.contains("rad 100\n"))
        XCTAssertTrue(trimmed.hasPrefix("rad 101\n"))
    }
}

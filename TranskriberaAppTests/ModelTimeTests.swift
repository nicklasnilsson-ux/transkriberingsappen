import XCTest
@testable import Transkribera

/// Varje modell som erbjuds i väljaren ska visa en uppmätt tid, och inga dolda modeller
/// ska ha en tid som aldrig mätts. Se docs/KONTROLLER.md.
final class ModelTimeTests: XCTestCase {
    func testEveryOfferedModelHasTimeText() {
        for model in WhisperModel.offered {
            let text = model.processingTimeText
            XCTAssertNotNil(text, "\(model.displayName) saknar tid")
            XCTAssertTrue(text?.hasPrefix("Ca ") ?? false)
            XCTAssertTrue(text?.hasSuffix("för en timmes ljud") ?? false)
        }
    }

    func testOnlyOfferedModelsHaveTimeText() {
        let offered = Set(WhisperModel.offered)
        for model in WhisperModel.allCases where !offered.contains(model) {
            XCTAssertNil(model.processingTimeText, "\(model.displayName) har en tid utan mätning")
        }
    }

    func testOrderMatchesMeasurement() {
        // Uppmätt: Pianissimo < Turbo < KB Large ordagrann.
        XCTAssertEqual(WhisperModel.pianissimo.processingTimeText, "Ca 40 sekunder för en timmes ljud")
        XCTAssertEqual(WhisperModel.largeV3Turbo.processingTimeText, "Ca 3 minuter för en timmes ljud")
        XCTAssertEqual(WhisperModel.kbLargeStrict.processingTimeText, "Ca 12 minuter för en timmes ljud")
    }
}

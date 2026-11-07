import XCTest
import TranskriberaCore
@testable import Transkribera

/// Tidsmätningen i Testlabbet ska mäta precis de modeller som väljaren visar. Visas en ny
/// modell i väljaren utan att labbet kan köra den, skulle tiden för den saknas tyst.
final class TestLabTimingTests: XCTestCase {
    func testEnginesAreTheModelsInThePicker() {
        XCTAssertEqual(Set(TestLabRun.Engine.allCases.map(\.model)), Set(WhisperModel.offered))
    }

    func testTimingPlanCoversEveryModelInThePicker() {
        XCTAssertEqual(Set(TestLabPlan.timing.map(\.engine.model)), Set(WhisperModel.offered))
    }
}

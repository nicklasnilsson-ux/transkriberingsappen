import XCTest
import TranskriberaCore
@testable import Transkribera

/// Tidsmätningen i Testlabbet ska mäta precis de modeller som väljaren visar. Visas en ny
/// modell i väljaren utan att labbet kan köra den, skulle tiden för den saknas tyst.
final class TestLabTimingTests: XCTestCase {
    func testEnginesAreTheModelsInThePickerPlusThePianissimoVersions() {
        let versions = Set(PianissimoVersion.allCases.map(\.model))
        XCTAssertEqual(Set(TestLabRun.Engine.allCases.map(\.model)), Set(WhisperModel.offered).union(versions))
    }

    /// `isInModelPicker` styr vilka motorer tidsmätningen kräver; den måste följa väljaren.
    func testIsInModelPickerFollowsThePicker() {
        let inPicker = TestLabRun.Engine.allCases.filter(\.isInModelPicker).map(\.model)
        XCTAssertEqual(Set(inPicker), Set(WhisperModel.offered))
    }

    func testTimingPlanCoversEveryModelInThePicker() {
        XCTAssertEqual(Set(TestLabPlan.timing.map(\.engine.model)), Set(WhisperModel.offered))
    }
}

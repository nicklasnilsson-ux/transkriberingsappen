import XCTest
@testable import TranskriberaCore

final class RecordingStartDiagnosisTests: XCTestCase {
    private let domain = RecordingStartDiagnosis.screenCaptureKitErrorDomain

    func testUserDeclinedIsPermissionEvenIfPreflightSaysGranted() {
        let result = RecordingStartDiagnosis.classify(
            errorDomain: domain, errorCode: RecordingStartDiagnosis.userDeclinedCode,
            errorDescription: "x", preflightGranted: true)
        XCTAssertEqual(result, .permissionDenied)
    }

    func testMissingPreflightIsPermission() {
        let result = RecordingStartDiagnosis.classify(
            errorDomain: "NSCocoaErrorDomain", errorCode: 1, errorDescription: "x", preflightGranted: false)
        XCTAssertEqual(result, .permissionDenied)
    }

    /// Felet som tidigare göms: tillåtelse finns, men något annat gick fel. Det får inte
    /// visas som "tillåtelse saknas", och felkoden ska synas.
    func testOtherErrorWithPermissionKeepsTheRealError() {
        let result = RecordingStartDiagnosis.classify(
            errorDomain: domain, errorCode: -3805, errorDescription: "Stream stopped", preflightGranted: true)
        guard case .other(let detail) = result else { return XCTFail("borde vara .other") }
        XCTAssertTrue(detail.contains("-3805"))
        XCTAssertTrue(detail.contains(domain))
    }
}

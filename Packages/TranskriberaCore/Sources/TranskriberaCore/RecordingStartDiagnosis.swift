import Foundation

/// Vad ett misslyckat försök att starta mötesinspelningen beror på.
/// Förut fick alla fel vid start texten "tillåtelse saknas", även när något helt annat var fel.
public enum RecordingStartDiagnosis: Equatable, Sendable {
    /// macOS nekar appen att spela in skärm- och systemljud.
    case permissionDenied
    /// Något annat gick fel. Texten innehåller felkoden så att den går att felsöka.
    case other(detail: String)

    /// ScreenCaptureKits felkod för "användaren har inte tillåtit" (SCStreamError.userDeclined).
    public static let userDeclinedCode = -3801
    public static let screenCaptureKitErrorDomain = "com.apple.ScreenCaptureKit.SCStreamErrorDomain"

    /// - Parameters:
    ///   - preflightGranted: svaret från `CGPreflightScreenCaptureAccess()` när felet inträffade.
    public static func classify(
        errorDomain: String,
        errorCode: Int,
        errorDescription: String,
        preflightGranted: Bool
    ) -> RecordingStartDiagnosis {
        if errorDomain == screenCaptureKitErrorDomain, errorCode == userDeclinedCode {
            return .permissionDenied
        }
        if !preflightGranted {
            return .permissionDenied
        }
        return .other(detail: "\(errorDescription) (felkod \(errorCode), \(errorDomain))")
    }
}

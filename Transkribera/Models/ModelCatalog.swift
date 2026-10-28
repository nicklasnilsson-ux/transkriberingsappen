import Foundation

/// Whisper-modellerna som appen erbjuder. `variant` är namnet i
/// https://huggingface.co/argmaxinc/whisperkit-coreml (utan prefixet "openai_whisper-").
enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case largeV3Turbo = "large-v3-v20240930_turbo"
    case largeV3TurboCompressed = "large-v3-v20240930_626MB"

    var id: String { rawValue }
    var variant: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .largeV3Turbo: return "Large v3 Turbo"
        case .largeV3TurboCompressed: return "Large v3 Turbo (komprimerad)"
        }
    }

    var summary: String {
        switch self {
        case .tiny: return "75 MB · Snabbast men lägst kvalitet, mest för test"
        case .base: return "145 MB · Snabb, godtagbar kvalitet"
        case .small: return "480 MB · Balans mellan fart och kvalitet"
        case .largeV3Turbo: return "1,6 GB · Bäst kvalitet"
        case .largeV3TurboCompressed: return "630 MB · Nästan bäst kvalitet, mindre minne · Rekommenderas"
        }
    }

    static let `default`: WhisperModel = .largeV3TurboCompressed
}

/// Språk som visas i språkväljaren. Whisper stöder fler – lägg till vid behov.
struct Language: Identifiable, Hashable {
    /// ISO-kod som Whisper förstår, eller `nil` för automatisk identifiering.
    let code: String?
    let name: String

    var id: String { code ?? "auto" }

    static let automatic = Language(code: nil, name: "Automatiskt (identifiera språk)")

    static let all: [Language] = [
        automatic,
        Language(code: "sv", name: "Svenska"),
        Language(code: "en", name: "Engelska"),
        Language(code: "no", name: "Norska"),
        Language(code: "da", name: "Danska"),
        Language(code: "fi", name: "Finska"),
        Language(code: "de", name: "Tyska"),
        Language(code: "fr", name: "Franska"),
        Language(code: "es", name: "Spanska"),
        Language(code: "it", name: "Italienska"),
        Language(code: "nl", name: "Nederländska"),
        Language(code: "pl", name: "Polska"),
        Language(code: "pt", name: "Portugisiska"),
        Language(code: "ar", name: "Arabiska"),
        Language(code: "tr", name: "Turkiska"),
        Language(code: "uk", name: "Ukrainska"),
        Language(code: "ru", name: "Ryska"),
        Language(code: "zh", name: "Kinesiska"),
        Language(code: "ja", name: "Japanska")
    ]

    static func displayName(for code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }
}

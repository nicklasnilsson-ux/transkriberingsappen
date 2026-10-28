import Foundation

/// Whisper-modellerna som appen erbjuder, i den ordning de visas i väljaren:
/// först KBLab:s svenska modeller, sedan OpenAI:s flerspråkiga.
enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case kbBase = "kb-whisper-base"
    case kbSmall = "kb-whisper-small"
    case kbMedium = "kb-whisper-medium"
    case kbLarge = "kb-whisper-large"
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case largeV3Turbo = "large-v3-v20240930_turbo"
    case largeV3TurboCompressed = "large-v3-v20240930_626MB"

    enum Family: String, CaseIterable, Identifiable {
        case kb, openAI

        var id: String { rawValue }

        var title: String {
            switch self {
            case .kb: return "Svenska – KB-Whisper från Kungliga biblioteket"
            case .openAI: return "Flerspråkiga – OpenAI Whisper"
            }
        }

        var models: [WhisperModel] { WhisperModel.allCases.filter { $0.family == self } }
    }

    /// Var modellen laddas ner ifrån.
    enum Source {
        /// Namnet i https://huggingface.co/argmaxinc/whisperkit-coreml (utan prefixet "openai_whisper-").
        case whisperKit(variant: String)
        /// En zip-fil i releasen som `.github/workflows/kb-whisper-models.yml` publicerar.
        case kbRelease(asset: String)
    }

    var id: String { rawValue }

    var family: Family {
        switch self {
        case .kbBase, .kbSmall, .kbMedium, .kbLarge: return .kb
        default: return .openAI
        }
    }

    var source: Source {
        switch family {
        case .kb: return .kbRelease(asset: "\(rawValue).zip")
        case .openAI: return .whisperKit(variant: rawValue)
        }
    }

    var displayName: String {
        switch self {
        case .kbBase: return "KB Base"
        case .kbSmall: return "KB Small"
        case .kbMedium: return "KB Medium"
        case .kbLarge: return "KB Large"
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .largeV3Turbo: return "Large v3 Turbo"
        case .largeV3TurboCompressed: return "Large v3 Turbo (komprimerad)"
        }
    }

    /// Ungefärlig nedladdningsstorlek.
    var downloadSize: String {
        switch self {
        case .kbBase: return "135 MB"
        case .kbSmall: return "450 MB"
        case .kbMedium: return "1,4 GB"
        case .kbLarge: return "1,3 GB"
        case .tiny: return "75 MB"
        case .base: return "145 MB"
        case .small: return "480 MB"
        case .largeV3Turbo: return "1,6 GB"
        case .largeV3TurboCompressed: return "630 MB"
        }
    }

    /// Relativ hastighet på Apple Silicon, 1 (långsammast) – 5 (snabbast).
    var speed: Int {
        switch self {
        case .tiny, .base, .kbBase: return 5
        case .small, .kbSmall: return 4
        case .largeV3Turbo, .largeV3TurboCompressed: return 3
        case .kbMedium: return 2
        case .kbLarge: return 1
        }
    }

    /// Noggrannhet på svenska, 1–5. Bygger på KBLab:s mätningar av ordfelfrekvens
    /// (FLEURS, Common Voice, NST): https://kb-labb.github.io/posts/2025-03-07-welcome-KB-Whisper/
    var swedishAccuracy: Int {
        switch self {
        case .kbLarge: return 5
        case .kbMedium, .kbSmall: return 4
        case .kbBase, .largeV3Turbo, .largeV3TurboCompressed: return 3
        case .small: return 2
        case .tiny, .base: return 1
        }
    }

    /// Andel felaktiga ord (WER) på svensk testdata, enligt KBLab:s mätning på FLEURS:
    /// https://kb-labb.github.io/posts/2025-03-07-welcome-KB-Whisper/
    /// `nil` = inte uppmätt av KBLab.
    var swedishWordErrorRate: Double? {
        switch self {
        case .kbBase: return 9.1
        case .kbSmall: return 7.3
        case .kbMedium: return 6.6
        case .kbLarge: return 5.4
        case .tiny: return 59.2
        case .base: return 39.6
        case .small: return 20.6
        case .largeV3Turbo, .largeV3TurboCompressed: return nil
        }
    }

    /// T.ex. "7 av 100 ord fel på svenska".
    var swedishErrorText: String {
        guard let wer = swedishWordErrorRate else {
            return "Ej uppmätt på svenska (OpenAI Large v3: 8 av 100 ord fel)"
        }
        return "\(Int(wer.rounded())) av 100 ord fel på svenska"
    }

    /// Kort etikett om språkstöd.
    var languageNote: String {
        switch family {
        case .kb: return "Bäst för svenska"
        case .openAI: return "99 språk"
        }
    }

    /// En mening om vad modellen är bra på.
    var characteristic: String {
        switch self {
        case .kbBase:
            return "Snabbast av KB-modellerna. Bra för snabba utkast eller äldre Mac-datorer."
        case .kbSmall:
            return "Välj den här för vardagsbruk, t.ex. möten och intervjuer. Gör färre fel än OpenAI:s sex gånger större Large v3."
        case .kbMedium:
            return "Lite färre fel än Small men tre gånger så stor och långsammare. Passar om datorn har för lite minne för Large."
        case .kbLarge:
            return "Färst fel, särskilt på namn, facktermer, dialekter och dåligt ljud. Tar 3–5 gånger så lång tid som Small. Välj den när varje ord måste stämma."
        case .tiny:
            return "Minsta modellen, bra för att snabbt testa appen. Gör många fel på svenska."
        case .base:
            return "Snabb, men gör många fel på svenska. Fungerar hyggligt på engelska."
        case .small:
            return "Bra balans mellan fart och kvalitet för engelska och andra stora språk."
        case .largeV3Turbo:
            return "Bästa valet för andra språk än svenska och för blandade språk. Snabb för sin storlek."
        case .largeV3TurboCompressed:
            return "Samma som Large v3 Turbo men komprimerad: mindre nedladdning och minne, nästan lika bra."
        }
    }

    /// Kort sammanfattning på en rad, t.ex. under väljaren.
    var summary: String {
        "\(downloadSize) · \(languageNote) · \(characteristic)"
    }

    /// Ungefär hur mycket minne modellen behöver medan den körs.
    var minimumMemoryGB: Int {
        switch self {
        case .kbLarge: return 16
        default: return 8
        }
    }

    /// Varning om datorn har mindre minne än modellen behöver, annars `nil`.
    var memoryWarning: String? {
        let installedGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        guard installedGB < minimumMemoryGB else { return nil }
        return "Din Mac har \(installedGB) GB minne. Modellen kan bli seg, så prova KB Medium eller Small."
    }

    var isRecommended: Bool { self == .default }

    /// Sant för modeller som bara är tränade för svenska.
    var isSwedishOnly: Bool { family == .kb }

    static let `default`: WhisperModel = .kbSmall
}

/// Språk som visas i språkväljaren. Whisper stöder fler – lägg till vid behov.
struct Language: Identifiable, Hashable {
    /// ISO-kod som Whisper förstår, eller `nil` för automatisk identifiering.
    let code: String?
    let name: String

    var id: String { code ?? "auto" }

    static let automatic = Language(code: nil, name: "Identifiera automatiskt")

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

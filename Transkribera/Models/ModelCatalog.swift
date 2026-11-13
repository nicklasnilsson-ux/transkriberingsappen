import Foundation

/// Alla modeller som koden kan köra. Väljaren visar bara `offered`: Pianissimo, KB Large
/// ordagrann och Large v3 Turbo. De övriga är dolda men kvar, så att redan nedladdade
/// modeller och koden fungerar. Alla utom Pianissimo körs med WhisperKit; Pianissimo
/// körs med FluidAudio.
enum WhisperModel: String, CaseIterable, Identifiable, Codable {
    case kbBase = "kb-whisper-base"
    case kbSmall = "kb-whisper-small"
    case kbMedium = "kb-whisper-medium"
    case kbLarge = "kb-whisper-large"
    case kbMediumStrict = "kb-whisper-medium-strict"
    case kbLargeStrict = "kb-whisper-large-strict"
    case pianissimo = "pianissimo-sv"
    /// Test 2026-11-13: Pianissimo med kodaren i 16 bitar i stället för 8 (`scripts/pianissimo/finish.py
    /// --encoder fp16`). Dold; används när experimentet "Pianissimo i 16 bitar" är på.
    case pianissimoFP16 = "pianissimo-sv-fp16"
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case largeV3Turbo = "large-v3-v20240930_turbo"
    case largeV3TurboCompressed = "large-v3-v20240930_626MB"

    enum Family: String, CaseIterable, Identifiable {
        case klang, kb, openAI

        var id: String { rawValue }

        var title: String {
            switch self {
            case .kb: return "Svenska – KB-Whisper från Kungliga biblioteket"
            case .klang: return "Svenska – Pianissimo från Klang"
            case .openAI: return "Flerspråkiga – OpenAI Whisper"
            }
        }

        var models: [WhisperModel] { WhisperModel.offered.filter { $0.family == self } }
    }

    /// Modellerna som visas i väljaren, i visningsordning. Pianissimo först (snabbast och
    /// standard), KB Large ordagrann när ljudet är dåligt, Large v3 Turbo för andra
    /// språk. Dölj en modell här tills dess nedladdning är publicerad;
    /// scripts/check-models.sh stoppar bygget om en visad modell saknas.
    static let offered: [WhisperModel] = [.pianissimo, .kbLargeStrict, .largeV3Turbo]

    /// Sant för modeller som finns kvar i koden men inte visas i väljaren.
    var isHidden: Bool { !Self.offered.contains(self) }

    /// Modellen en sparad inställning ska ge: den sparade om den visas i väljaren,
    /// annars standardmodellen (okänt värde, eller en dold modell från en äldre version).
    static func resolved(_ raw: String?) -> WhisperModel {
        guard let raw, let model = WhisperModel(rawValue: raw), offered.contains(model) else { return .default }
        return model
    }

    /// Den dolda modellen en sparad inställning pekar på, om någon. Används för att
    /// berätta att inställningen har bytts mot standardmodellen.
    static func hiddenModel(_ raw: String?) -> WhisperModel? {
        guard let raw, let model = WhisperModel(rawValue: raw), model.isHidden else { return nil }
        return model
    }

    /// Var modellen laddas ner ifrån.
    enum Source {
        /// Namnet i https://huggingface.co/argmaxinc/whisperkit-coreml (utan prefixet "openai_whisper-").
        case whisperKit(variant: String)
        /// En zip-fil i releasen som `.github/workflows/kb-whisper-models.yml` publicerar.
        case kbRelease(asset: String)
        /// En zip-fil i releasen som `.github/workflows/pianissimo-model.yml` publicerar.
        case pianissimoRelease(asset: String)
    }

    var id: String { rawValue }

    var family: Family {
        switch self {
        case .kbBase, .kbSmall, .kbMedium, .kbLarge, .kbMediumStrict, .kbLargeStrict: return .kb
        case .pianissimo, .pianissimoFP16: return .klang
        default: return .openAI
        }
    }

    var source: Source {
        switch family {
        case .kb: return .kbRelease(asset: "\(rawValue).zip")
        case .klang: return .pianissimoRelease(asset: "\(rawValue).zip")
        case .openAI: return .whisperKit(variant: rawValue)
        }
    }

    var displayName: String {
        switch self {
        case .kbBase: return "KB Base"
        case .kbSmall: return "KB Small"
        case .kbMedium: return "KB Medium"
        case .kbLarge: return "KB Large"
        case .kbMediumStrict: return "KB Medium ordagrann"
        case .kbLargeStrict: return "KB Large ordagrann"
        case .pianissimo: return "Pianissimo"
        case .pianissimoFP16: return "Pianissimo 16 bitar"
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
        case .kbMedium, .kbMediumStrict: return "1,4 GB"
        case .kbLarge, .kbLargeStrict: return "1,3 GB"
        case .pianissimo: return "650 MB"
        case .pianissimoFP16: return "1,2 GB"
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
        case .tiny, .base, .kbBase, .pianissimo, .pianissimoFP16: return 5
        case .small, .kbSmall: return 4
        case .largeV3Turbo, .largeV3TurboCompressed: return 3
        case .kbMedium, .kbMediumStrict: return 2
        case .kbLarge, .kbLargeStrict: return 1
        }
    }

    /// Ungefärlig tid för hela processen (transkribering och talarigenkänning) per timme ljud,
    /// uppmätt med Testlabbets Tidsmätning på en Mac med M4-chip (18 minuters inspelning,
    /// 3 talare, 2026-11-07). Talarigenkänningen tog bara cirka 2 sekunder per 18 minuter,
    /// så en och flera talare ger samma text. `nil` = inte uppmätt.
    /// Ändra siffrorna bara efter en ny mätning (se docs/KONTROLLER.md).
    var processingTimeText: String? {
        switch self {
        case .pianissimo: return "Ca 40 sekunder för en timmes ljud"
        case .largeV3Turbo: return "Ca 3 minuter för en timmes ljud"
        case .kbLargeStrict: return "Ca 12 minuter för en timmes ljud"
        default: return nil
        }
    }

    /// Noggrannhet på svenska, 1–5. Bygger på KBLab:s mätningar av ordfelfrekvens
    /// (FLEURS, Common Voice, NST): https://kb-labb.github.io/posts/2025-03-07-welcome-KB-Whisper/
    var swedishAccuracy: Int {
        switch self {
        case .kbLarge, .kbLargeStrict: return 5
        case .kbMedium, .kbMediumStrict, .kbSmall, .pianissimo, .pianissimoFP16: return 4
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
        case .kbMediumStrict: return 6.8
        case .kbLargeStrict: return 5.3
        case .pianissimo: return 6.5  // Klangs mätning på FLEURS (KB Large: 5,1 i samma mätning)
        case .pianissimoFP16: return nil
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

    /// Kort etikett om vad modellen är bäst på. Bara påståenden som mätningarna står bakom:
    /// Pianissimo är snabbast (10 mot 221 s för 18 min, Tidsmätning), KB Large klarar
    /// svagt ljud bättre (vibe-vs-var-app: 9 mot 16 ordfel på 15 meningar med dåligt ljud).
    /// På ren svenska är ordfelen lika (82,0 mot 82,4 % ord rätt), så ingen är "bäst för svenska".
    /// scripts/test_model_texts.py vaktar formuleringarna.
    var languageNote: String {
        switch self {
        case .pianissimo: return "Snabbast"
        case .kbLargeStrict, .kbLarge: return "Bäst på svagt ljud"
        default: return isSwedishOnly ? "Svenska" : "99 språk"
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
            return "Färre fel, särskilt på dåligt ljud. Tar 3–5 gånger så lång tid som Small. Välj den när ljudet är dåligt eller du vill ha några färre ordfel."
        case .kbMediumStrict:
            return "Som Medium, men skriver mer ordagrant och stryker mindre. Bra för intervjuer om datorn har för lite minne för Large."
        case .kbLargeStrict:
            return "Välj den när ljudet är dåligt eller du vill ha några färre ordfel. Tar längre tid och behöver mer minne."
        case .pianissimo:
            return "Snabbast och ger en komplett text. Välj den till de flesta svenska intervjuer och möten, även långa. Namn i ordlistan rättas i efterhand."
        case .pianissimoFP16:
            return "Test: Pianissimo med kodaren i 16 bitar i stället för 8. Dubbelt så stor nedladdning."
        case .tiny:
            return "Minsta modellen, bra för att snabbt testa appen. Gör många fel på svenska."
        case .base:
            return "Snabb, men gör många fel på svenska. Fungerar hyggligt på engelska."
        case .small:
            return "Bra balans mellan fart och kvalitet för engelska och andra stora språk."
        case .largeV3Turbo:
            return "För andra språk än svenska och för blandade språk. Snabb för sin storlek."
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
        case .kbLarge, .kbLargeStrict: return 16
        default: return 8
        }
    }

    /// Varning om datorn har mindre minne än modellen behöver, annars `nil`.
    var memoryWarning: String? {
        let installedGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        guard installedGB < minimumMemoryGB else { return nil }
        return "Din Mac har \(installedGB) GB minne. Modellen kan bli seg, så prova Pianissimo."
    }

    var isRecommended: Bool { self == .default }

    /// Sant för modeller som bara är tränade för svenska.
    var isSwedishOnly: Bool { family != .openAI }

    /// Sant för Pianissimo, som körs med FluidAudio i stället för WhisperKit.
    var usesParakeet: Bool { family == .klang }

    static let `default`: WhisperModel = .pianissimo
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

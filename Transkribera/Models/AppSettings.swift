import Foundation
import TranskriberaCore
import TranskriberaSpeakers

/// Nycklar för inställningar som lagras med @AppStorage.
enum SettingsKey {
    static let model = "whisperModel"
    static let language = "language"
    static let identifySpeakers = "identifySpeakers"
    static let wordTimestamps = "wordTimestamps"
    static let task = "task"
    static let recordMicrophone = "recordMicrophone"
    static let exportTimestamps = "exportTimestamps"
    static let anonymize = "anonymize"
    static let anonymizeNames = "anonymizeNames"
    static let anonymizeIdentifiers = "anonymizeIdentifiers"
    static let anonymizeSensitive = "anonymizeSensitive"
    static let anonymizeOrganizations = "anonymizeOrganizations"
    static let anonymizeUncertainNames = "anonymizeUncertainNames"
    static let anonymizeAlwaysHide = "anonymizeAlwaysHide"
    static let anonymizeNeverHide = "anonymizeNeverHide"
    /// Gammal inställning (heltal, 0 = automatiskt). Flyttas till `speakers` vid start.
    static let speakerCount = "speakerCount"
    /// `SpeakerCount.rawValue`, t.ex. "auto", "3" eller "2-4".
    static let speakers = "speakers"
    static let vocabulary = "vocabulary"
    static let betaUpdates = "betaUpdates"
    static let transcriptLayout = "transcriptLayout"
    static let pianissimoCarefulSeams = "pianissimoCarefulSeams"
    static let levelVolume = "levelVolume"
    static let sortformerDiarization = "sortformerDiarization"
    static let rescueShortReplies = "rescueShortReplies"
    /// `CrossCheckSource.rawValue`.
    static let crossCheck = "crossCheck"
    /// Experiment: vilken Pianissimo som används, `PianissimoVersion.rawValue`.
    static let pianissimoVersion = "pianissimoVersion"
    /// Textstorlek på läsytan i punkter, ett av `ReadingTextSize.steps`.
    static let readingTextSize = "readingTextSize"
    /// Fråga innan Transkribera igen (på som standard). Gäller bara när det finns plats för
    /// fler versioner; när den äldsta raderas frågar appen alltid (se `RetranscribeDialog`).
    static let askBeforeRetranscribe = "askBeforeRetranscribe"
    /// Uppspelningshastighet, ett av `PlaybackSpeed.steps` (1 = normal). Gäller alla filer.
    static let playbackSpeed = "playbackSpeed"
}

enum SpeakerCountSetting {
    /// Flyttar den gamla heltalsinställningen till den nya, så att ett valt antal talare
    /// finns kvar efter uppdateringen.
    static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: SettingsKey.speakers) == nil,
              defaults.object(forKey: SettingsKey.speakerCount) != nil else { return }
        let legacy = SpeakerCount(legacyCount: defaults.integer(forKey: SettingsKey.speakerCount))
        defaults.set(legacy.rawValue, forKey: SettingsKey.speakers)
    }

    static func current(_ defaults: UserDefaults = .standard) -> SpeakerCount {
        if let raw = defaults.string(forKey: SettingsKey.speakers), let count = SpeakerCount(rawValue: raw) {
            return count
        }
        return SpeakerCount(legacyCount: defaults.integer(forKey: SettingsKey.speakerCount))
    }
}

/// Hur transkriberingen visas: löpande stycken per talare (standard) eller
/// ett segment per rad med egen tidskod.
enum TranscriptLayout: String, CaseIterable, Identifiable {
    case paragraphs
    case segments

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paragraphs: "Stycken"
        case .segments: "Rader"
        }
    }
}

/// Anonymisering är på som standard. Originaltexten sparas alltid; det är bara
/// visning, kopiering och export som använder den anonymiserade texten.
enum AnonymizationSettings {
    static func options(_ defaults: UserDefaults = .standard) -> AnonymizationOptions? {
        func flag(_ key: String, _ fallback: Bool = true) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        guard flag(SettingsKey.anonymize) else { return nil }
        return options(
            names: flag(SettingsKey.anonymizeNames),
            identifiers: flag(SettingsKey.anonymizeIdentifiers),
            sensitiveTopics: flag(SettingsKey.anonymizeSensitive),
            organizations: flag(SettingsKey.anonymizeOrganizations, false),
            uncertainNames: flag(SettingsKey.anonymizeUncertainNames, false),
            alwaysHide: defaults.string(forKey: SettingsKey.anonymizeAlwaysHide) ?? "",
            neverHide: defaults.string(forKey: SettingsKey.anonymizeNeverHide) ?? ""
        )
    }

    /// Bygger inställningarna från värdena i @AppStorage, så att vyer som visar
    /// anonymiserad text räknar om när något ändras.
    static func options(
        names: Bool,
        identifiers: Bool,
        sensitiveTopics: Bool,
        organizations: Bool,
        uncertainNames: Bool,
        alwaysHide: String,
        neverHide: String
    ) -> AnonymizationOptions {
        AnonymizationOptions(
            names: names,
            identifiers: identifiers,
            sensitiveTopics: sensitiveTopics,
            organizations: organizations,
            uncertainNames: uncertainNames,
            alwaysHide: TextCleaning.wordList(alwaysHide),
            neverHide: TextCleaning.wordList(neverHide)
        )
    }
}

/// Vad filen transkriberades med. Det är utgångsläget i filens inställningsruta, inte
/// standardinställningarna för nästa transkribering.
struct FileBaseline: Equatable {
    var modelRaw: String
    var language: String
    var identifySpeakers: Bool

    init(modelName: String, language: String?, hasSpeakers: Bool) {
        let base = RerunChange.baseModelName(modelName)
        let model = WhisperModel.allCases.first { $0.displayName == base }
        // En modell som inte längre visas i väljaren ersätts av standardmodellen, som annars.
        modelRaw = WhisperModel.resolved(model?.rawValue).rawValue
        self.language = language ?? "auto"
        identifySpeakers = hasSpeakers
    }
}

/// Val som bara gäller en omtagning av en fil (modell, språk, talare). De ändrar inte
/// standardinställningarna för nästa transkribering.
struct TranscriptionOverrides: Equatable {
    var modelRaw: String?
    /// "auto" = automatisk språkidentifiering.
    var language: String?
    var identifySpeakers: Bool?
    var speakerCount: SpeakerCount?

    var isEmpty: Bool { self == TranscriptionOverrides() }

    /// Fyller i det som inte ändrats med det filen har, så att "Transkribera igen" gör
    /// det chipsen visar och inte tyst byter till standardinställningarna.
    func filled(with file: FileBaseline) -> TranscriptionOverrides {
        var o = self
        o.modelRaw = o.modelRaw ?? file.modelRaw
        o.language = o.language ?? file.language
        o.identifySpeakers = o.identifySpeakers ?? file.identifySpeakers
        if o.identifySpeakers == true { o.speakerCount = o.speakerCount ?? .automatic }
        return o
    }

    func applied(to options: TranscriptionOptions) -> TranscriptionOptions {
        var o = options
        if let modelRaw {
            o.model = WhisperModel.resolved(modelRaw)
            // Experimentet "Pianissimo-version" gäller även när man kör om.
            if o.model == .pianissimo { o.model = PianissimoVersion.current().model }
        }
        if let language { o.languageCode = language == "auto" ? nil : language }
        if let identifySpeakers { o.identifySpeakers = identifySpeakers }
        if let speakerCount { o.speakerCount = speakerCount }
        return o
    }
}

/// Inställningar som skickas med varje transkribering.
struct TranscriptionOptions {
    var model: WhisperModel
    /// `nil` = automatisk språkidentifiering.
    var languageCode: String?
    var identifySpeakers: Bool
    /// Antal talare, exakt eller som spann. Standard: automatiskt, minst 2.
    var speakerCount: SpeakerCount = .automatic
    /// Namn och fackord som brukar förekomma. Ges till modellen som ledtråd.
    var vocabulary: String
    var wordTimestamps: Bool
    /// Översätt till engelska istället för att transkribera.
    var translateToEnglish: Bool
    /// Experiment: Pianissimo provar flera sätt att skarva 15-sekundersfönstren.
    var carefulSeams = false
    /// Svaga röster förstärks innan ljudet transkriberas. Hjälpte KB-Whisper (cirka
    /// 2–3 procentenheter färre ordfel mot Klang i två intervjuer) men inte Pianissimo,
    /// som jämnar ut volymen själv, så den gäller bara Whisper-modellerna.
    var levelVolume = true
    /// Talaridentifiering med Nemotron 3 Diarization (FluidAudio), byggd för korta repliker. Används när antal talare är automatiskt, annars SpeakerKit.
    var sortformerDiarization = true
    /// Experiment "Fånga korta svar": korta repliker som saknas i texten transkriberas för
    /// sig och läggs in (`ShortReplyRescue`). Bara med Pianissimo och "Skilj på vem som pratar".
    var rescueShortReplies = false
    /// Experiment "Korskolla": ljudet transkriberas en gång till, och där körningarna hörde
    /// olika får ordet en prickad understrykning (`CrossCheck`). Bara Pianissimo.
    var crossCheck = CrossCheckSource.off
    /// Taligenkänningens spärrar och gränser. Ändras bara av Testlabbet.
    var tuning = DecoderTuning.production

    var appliesLevelVolume: Bool { levelVolume && !model.usesParakeet }
    var appliesShortReplyRescue: Bool { rescueShortReplies && identifySpeakers && model.usesParakeet }
    /// Kontrollen som körs, eller `nil`.
    var appliedCrossCheck: CrossCheckSource? {
        guard model.usesParakeet, !translateToEnglish, crossCheck != .off else { return nil }
        return crossCheck
    }

    /// Modellens namn som sparas med transkriberingen, med experimenten som användes,
    /// så att olika körningar går att skilja åt vid en jämförelse.
    var modelLabel: String {
        var extras: [String] = []
        if carefulSeams, model.usesParakeet { extras.append("noggranna skarvar") }
        if appliesLevelVolume { extras.append("jämnad volym") }
        if appliesShortReplyRescue { extras.append("korta svar") }
        if let check = appliedCrossCheck { extras.append("korskollad med \(check.label)") }
        extras += tuning.differences
        if identifySpeakers {
            if sortformerDiarization, speakerCount.exact == nil { extras.append("Nemotron 3") }
        }
        return extras.isEmpty ? model.displayName : "\(model.displayName) (\(extras.joined(separator: ", ")))"
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> TranscriptionOptions {
        var model = WhisperModel.resolved(defaults.string(forKey: SettingsKey.model))
        if model == .pianissimo { model = PianissimoVersion.current(defaults).model }
        let language = defaults.string(forKey: SettingsKey.language) ?? "sv"
        return TranscriptionOptions(
            model: model,
            languageCode: language == "auto" ? nil : language,
            identifySpeakers: defaults.object(forKey: SettingsKey.identifySpeakers) as? Bool ?? false,
            speakerCount: SpeakerCountSetting.current(defaults),
            vocabulary: defaults.string(forKey: SettingsKey.vocabulary) ?? "",
            wordTimestamps: defaults.object(forKey: SettingsKey.wordTimestamps) as? Bool ?? true,
            translateToEnglish: defaults.string(forKey: SettingsKey.task) == "translate",
            carefulSeams: defaults.bool(forKey: SettingsKey.pianissimoCarefulSeams),
            levelVolume: defaults.object(forKey: SettingsKey.levelVolume) as? Bool ?? true,
            sortformerDiarization: (defaults.object(forKey: SettingsKey.sortformerDiarization) as? Bool ?? true) && ShortReplyDiarizer.isSupported,
            rescueShortReplies: defaults.bool(forKey: SettingsKey.rescueShortReplies),
            crossCheck: CrossCheckSource(rawValue: defaults.string(forKey: SettingsKey.crossCheck) ?? "") ?? .off
        )
    }
}

/// Vem som lyssnar en gång till i experimentet "Korskolla" (`CrossCheck`).
///
/// Bara KB Large ordagrann (beslut Nicklas 2026-11-13). På mötet 2026-11-12 fångade den flest
/// innebördsfel; Pianissimo i repliker och en vanlig omkörning av Pianissimo hör för likt
/// Pianissimo, och mindre KB-modeller hör sämre än Pianissimo (FLEURS: KB Medium 6,6 %,
/// KB Small 7,3 %, Pianissimo 6,5 %, KB Large 5,1 %). Ett sparat "pianissimoReplies" läses som av.
enum CrossCheckSource: String, CaseIterable, Identifiable {
    case off
    /// KB Large ordagrann. Cirka 25 gånger längre tid än Pianissimo.
    case kbLarge

    var id: String { rawValue }

    /// Modellen som lyssnar en gång till.
    var model: WhisperModel { .kbLargeStrict }

    var label: String {
        switch self {
        case .off: return "Av"
        case .kbLarge: return "KB Large"
        }
    }
}

/// Experiment 2026-11-13: vilken Pianissimo som används. Den vanliga har kodaren förminskad till
/// 8 bitar, vilket aldrig mätts på svenska. Testlabbets lista "Pianissimo: 8, 16 och 32 bitar"
/// jämför dem på flera filer på en gång.
enum PianissimoVersion: String, CaseIterable, Identifiable {
    case standard
    case fp16
    case fp32

    var id: String { rawValue }

    static func current(_ defaults: UserDefaults = .standard) -> PianissimoVersion {
        PianissimoVersion(rawValue: defaults.string(forKey: SettingsKey.pianissimoVersion) ?? "") ?? .standard
    }

    var model: WhisperModel {
        switch self {
        case .standard: return .pianissimo
        case .fp16: return .pianissimoFP16
        case .fp32: return .pianissimoFP32
        }
    }

    var label: String {
        switch self {
        case .standard: return "Vanlig (8 bitar)"
        case .fp16: return "16 bitar"
        case .fp32: return "32 bitar"
        }
    }
}

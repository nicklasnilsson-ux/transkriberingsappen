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
    static let communityDiarization = "communityDiarization"
    static let sortformerDiarization = "sortformerDiarization"
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
    /// Experiment: talaridentifiering med pyannote community-1 (FluidAudio) i stället för SpeakerKit.
    var communityDiarization = false
    /// Talaridentifiering med Nemotron 3 Diarization (FluidAudio), byggd för korta repliker. Går före community-1 när antal talare är automatiskt.
    var sortformerDiarization = true

    var appliesLevelVolume: Bool { levelVolume && !model.usesParakeet }

    /// Modellens namn som sparas med transkriberingen, med experimenten som användes,
    /// så att olika körningar går att skilja åt vid en jämförelse.
    var modelLabel: String {
        var extras: [String] = []
        if carefulSeams, model.usesParakeet { extras.append("noggranna skarvar") }
        if appliesLevelVolume { extras.append("jämnad volym") }
        if identifySpeakers {
            if sortformerDiarization, speakerCount.exact == nil {
                extras.append("Nemotron 3")
            } else if communityDiarization {
                extras.append("ny talaridentifiering")
            }
        }
        return extras.isEmpty ? model.displayName : "\(model.displayName) (\(extras.joined(separator: ", ")))"
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> TranscriptionOptions {
        let model = defaults.string(forKey: SettingsKey.model).flatMap(WhisperModel.init(rawValue:)) ?? .default
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
            communityDiarization: defaults.bool(forKey: SettingsKey.communityDiarization) && CommunityDiarizer.isSupported,
            sortformerDiarization: (defaults.object(forKey: SettingsKey.sortformerDiarization) as? Bool ?? true) && ShortReplyDiarizer.isSupported
        )
    }
}

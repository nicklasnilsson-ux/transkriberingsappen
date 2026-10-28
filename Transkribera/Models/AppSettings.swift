import Foundation
import TranskriberaCore

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
    static let speakerCount = "speakerCount"
    static let vocabulary = "vocabulary"
    static let betaUpdates = "betaUpdates"
    static let transcriptLayout = "transcriptLayout"
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
    /// Antal talare om det är känt, annars `nil` (räknas ut automatiskt).
    var numberOfSpeakers: Int?
    /// Namn och fackord som brukar förekomma. Ges till modellen som ledtråd.
    var vocabulary: String
    var wordTimestamps: Bool
    /// Översätt till engelska istället för att transkribera.
    var translateToEnglish: Bool

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> TranscriptionOptions {
        let model = defaults.string(forKey: SettingsKey.model).flatMap(WhisperModel.init(rawValue:)) ?? .default
        let language = defaults.string(forKey: SettingsKey.language) ?? "sv"
        return TranscriptionOptions(
            model: model,
            languageCode: language == "auto" ? nil : language,
            identifySpeakers: defaults.object(forKey: SettingsKey.identifySpeakers) as? Bool ?? false,
            numberOfSpeakers: defaults.integer(forKey: SettingsKey.speakerCount) > 0 ? defaults.integer(forKey: SettingsKey.speakerCount) : nil,
            vocabulary: defaults.string(forKey: SettingsKey.vocabulary) ?? "",
            wordTimestamps: defaults.object(forKey: SettingsKey.wordTimestamps) as? Bool ?? true,
            translateToEnglish: defaults.string(forKey: SettingsKey.task) == "translate"
        )
    }
}

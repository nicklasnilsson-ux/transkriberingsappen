import Foundation

/// Nycklar för inställningar som lagras med @AppStorage.
enum SettingsKey {
    static let model = "whisperModel"
    static let language = "language"
    static let identifySpeakers = "identifySpeakers"
    static let wordTimestamps = "wordTimestamps"
    static let task = "task"
    static let recordMicrophone = "recordMicrophone"
    static let exportTimestamps = "exportTimestamps"
}

/// Inställningar som skickas med varje transkribering.
struct TranscriptionOptions {
    var model: WhisperModel
    /// `nil` = automatisk språkidentifiering.
    var languageCode: String?
    var identifySpeakers: Bool
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
            wordTimestamps: defaults.object(forKey: SettingsKey.wordTimestamps) as? Bool ?? true,
            translateToEnglish: defaults.string(forKey: SettingsKey.task) == "translate"
        )
    }
}

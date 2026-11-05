import Foundation

/// Det inställningskortet överst i sidopanelen visar om nästa transkribering.
/// Rad 1 är alltid modell och språk. Rad 2 finns bara när något mer än standard är på,
/// så att läget syns utan att man öppnar kortet (Nicklas 2026-11-05).
public struct NextTranscriptionSummary: Equatable, Sendable {
    public var modelName: String
    public var languageName: String
    public var identifySpeakers: Bool
    public var hasVocabulary: Bool
    public var modelDownloaded: Bool

    public init(modelName: String, languageName: String, identifySpeakers: Bool, hasVocabulary: Bool, modelDownloaded: Bool) {
        self.modelName = modelName
        self.languageName = languageName
        self.identifySpeakers = identifySpeakers
        self.hasVocabulary = hasVocabulary
        self.modelDownloaded = modelDownloaded
    }

    /// "Pianissimo · Svenska"
    public var title: String { "\(modelName) · \(languageName)" }

    /// "Skiljer talare · Ordlista", eller nil när inget av det är på och modellen finns.
    public var detail: String? {
        var parts: [String] = []
        if identifySpeakers { parts.append("Skiljer talare") }
        if hasVocabulary { parts.append("Ordlista") }
        if !modelDownloaded { parts.append("Laddas ner första gången") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Hela läget i ord, för VoiceOver.
    public var accessibilityText: String {
        [title, detail].compactMap { $0 }.joined(separator: ", ")
    }
}

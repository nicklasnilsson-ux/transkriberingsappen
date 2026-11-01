import Foundation

/// Skiljer valen inför en omtagning sig från det filen transkriberades med?
/// Då görs "Transkribera igen" framträdande (blå); annars är den grå.
public enum RerunChange {
    /// Modellens visningsnamn utan eventuella experiment i parentes, t.ex. "KB Large (jämnad volym)" → "KB Large".
    public static func baseModelName(_ label: String) -> String {
        label.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? label
    }

    /// `nil` på ett val betyder att det inte ändrats (gäller filens värde).
    public static func isChanged(
        modelOnFile: String, chosenModel: String?,
        languageOnFile: String?, chosenLanguage: String?,
        identifiedSpeakersOnFile: Bool, chosenIdentify: Bool?,
        speakerCountOnFile: Int, chosenExactSpeakers: Int?
    ) -> Bool {
        if let chosenModel, chosenModel != baseModelName(modelOnFile) { return true }
        if let chosenLanguage, chosenLanguage != languageOnFile { return true }
        if let chosenIdentify, chosenIdentify != identifiedSpeakersOnFile { return true }
        if let chosenExactSpeakers, chosenExactSpeakers != speakerCountOnFile { return true }
        return false
    }
}

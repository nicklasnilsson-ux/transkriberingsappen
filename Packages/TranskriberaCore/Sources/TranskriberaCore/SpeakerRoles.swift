import Foundation

/// Roller i en intervju: en intervjuare och en eller flera kunder.
public enum SpeakerRoles {
    public static let interviewer = "Intervjuare"
    public static let customerPrefix = "Kund"

    /// Nya namn när `interviewer` är intervjuaren: den blir "Intervjuare" och övriga
    /// "Kund 1", "Kund 2" … i den ordning de först hörs. `speakers` ska vara i den ordningen.
    public static func names(for speakers: [String], interviewer: String) -> [String: String] {
        var names: [String: String] = [:]
        var customer = 0
        for speaker in speakers where names[speaker] == nil {
            if speaker == interviewer {
                names[speaker] = Self.interviewer
            } else {
                customer += 1
                names[speaker] = "\(customerPrefix) \(customer)"
            }
        }
        return names
    }

    /// Sant om talarna bara har talaridentifieringens namn ("Talare 1" …). Då frågar appen
    /// vem som är intervjuaren; har användaren själv döpt dem lämnas de i fred.
    public static func needsRoles(_ speakers: [String]) -> Bool {
        speakers.count >= 2 && speakers.allSatisfy {
            $0.range(of: #"^Talare \d+$"#, options: .regularExpression) != nil
        }
    }
}

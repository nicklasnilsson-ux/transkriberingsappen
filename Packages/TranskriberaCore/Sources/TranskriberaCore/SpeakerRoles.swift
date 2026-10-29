import Foundation

/// Roller i en intervju: en eller flera intervjuare och en eller flera kunder.
public enum SpeakerRoles {
    public static let interviewer = "Intervjuare"
    public static let customerPrefix = "Kund"

    /// Nya namn när `interviewer` är intervjuaren: den blir "Intervjuare" och övriga
    /// "Kund 1", "Kund 2" … i den ordning de först hörs. `speakers` ska vara i den ordningen.
    public static func names(for speakers: [String], interviewer: String) -> [String: String] {
        names(for: speakers, interviewers: [interviewer])
    }

    /// Som ovan med flera intervjuare: en ensam heter "Intervjuare", flera "Intervjuare 1",
    /// "Intervjuare 2" … Övriga blir kunder.
    public static func names(for speakers: [String], interviewers: Set<String>) -> [String: String] {
        let interviewerCount = Set(speakers).intersection(interviewers).count
        var names: [String: String] = [:]
        var interviewer = 0
        var customer = 0
        for speaker in speakers where names[speaker] == nil {
            if interviewers.contains(speaker) {
                interviewer += 1
                names[speaker] = interviewerCount == 1 ? Self.interviewer : "\(Self.interviewer) \(interviewer)"
            } else {
                customer += 1
                names[speaker] = "\(customerPrefix) \(customer)"
            }
        }
        return names
    }

    /// Sant för talare som redan har fått rollen intervjuare ("Intervjuare", "Intervjuare 2").
    public static func isInterviewer(_ speaker: String) -> Bool {
        speaker.range(of: "^\(interviewer)(?: \\d+)?$", options: .regularExpression) != nil
    }

    /// Sant om talarna bara har talaridentifieringens namn ("Talare 1" …). Då frågar appen
    /// vem som är intervjuaren; har användaren själv döpt dem lämnas de i fred.
    public static func needsRoles(_ speakers: [String]) -> Bool {
        speakers.count >= 2 && speakers.allSatisfy {
            $0.range(of: #"^Talare \d+$"#, options: .regularExpression) != nil
        }
    }
}

import Foundation

/// Roller i en intervju: en eller flera intervjuare. Övriga talare heter "Talare 1", "Talare 2" …
/// (inte "Kund": alla intervjuer har inte kunder, och "Talare" är det mer öppna ordet).
public enum SpeakerRoles {
    public static let interviewer = "Intervjuare"
    /// Prefix för talare som inte är intervjuare. Samma ord som talaridentifieringen använder.
    public static let speakerPrefix = "Talare"
    /// Rollordet som äldre versioner (före 0.9.35) gav övriga talare. Finns kvar i sparade
    /// transkriberingar och ska fortsätta räknas som en roll, men sätts aldrig av appen längre.
    public static let legacyCustomerPrefix = "Kund" // kund-ok: äldre transkriberingar

    /// Nya namn när `interviewer` är intervjuaren. Övriga heter "Talare N".
    public static func names(for speakers: [String], interviewer: String) -> [String: String] {
        names(for: speakers, interviewers: [interviewer])
    }

    /// Som ovan med flera intervjuare: en ensam heter "Intervjuare", flera "Intervjuare 1",
    /// "Intervjuare 2" … i den ordning de först hörs. `speakers` ska vara i den ordningen.
    ///
    /// Övriga talare som redan heter "Talare N" behåller sitt nummer, så att "Talare 3" aldrig
    /// plötsligt blir en annan person när någon görs till intervjuare. Övriga (t.ex. en intervjuare
    /// som inte längre är det, eller "Kund 1" från en äldre version) får det lägsta lediga numret.
    public static func names(for speakers: [String], interviewers: Set<String>) -> [String: String] {
        let ordered = speakers.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let interviewerCount = Set(ordered).intersection(interviewers).count
        var names: [String: String] = [:]
        var taken = Set<Int>()
        for speaker in ordered where !interviewers.contains(speaker) {
            if let number = speakerNumber(speaker), taken.insert(number).inserted {
                names[speaker] = speaker
            }
        }
        var interviewer = 0
        var next = 1
        for speaker in ordered where names[speaker] == nil {
            if interviewers.contains(speaker) {
                interviewer += 1
                names[speaker] = interviewerCount == 1 ? Self.interviewer : "\(Self.interviewer) \(interviewer)"
            } else {
                while taken.contains(next) { next += 1 }
                taken.insert(next)
                names[speaker] = "\(speakerPrefix) \(next)"
            }
        }
        return names
    }

    /// Numret i "Talare N", annars nil.
    public static func speakerNumber(_ speaker: String) -> Int? {
        guard speaker.range(of: "^\(speakerPrefix) \\d+$", options: .regularExpression) != nil else { return nil }
        return Int(speaker.dropFirst(speakerPrefix.count + 1))
    }

    /// Sant för talare som redan har fått rollen intervjuare ("Intervjuare", "Intervjuare 2").
    public static func isInterviewer(_ speaker: String) -> Bool {
        speaker.range(of: "^\(interviewer)(?: \\d+)?$", options: .regularExpression) != nil
    }

    /// Sant om talarna bara har talaridentifieringens namn ("Talare 1" …). Då frågar appen
    /// vem som är intervjuaren; har användaren själv döpt dem lämnas de i fred.
    public static func needsRoles(_ speakers: [String]) -> Bool {
        speakers.count >= 2 && speakers.allSatisfy { speakerNumber($0) != nil }
    }
}

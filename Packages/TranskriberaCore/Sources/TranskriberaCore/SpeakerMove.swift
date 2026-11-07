import Foundation

/// Byte av talare på ett stycke eller en rad, när talaridentifieringen har lagt något hos fel talare.
/// Bara de valda segmenten ändras; byter man namn på en talare ändras den överallt (se `Transcript.renameSpeaker`).
public enum SpeakerMove {
    /// Talarna man kan flytta till: alla utom den nuvarande, i den ordning de först hörs.
    public static func targets(speakers: [String], current: String?) -> [String] {
        speakers.filter { $0 != current }
    }

    /// Förslag på namn till en ny talare. Har talarna roller blir det nästa kund ("Kund 3"),
    /// annars nästa "Talare N". Namnet finns aldrig redan.
    public static func suggestedNewName(existing: [String]) -> String {
        let usesRoles = existing.contains { SpeakerRoles.isInterviewer($0) || number(in: $0, prefix: SpeakerRoles.customerPrefix) != nil }
        let prefix = usesRoles ? SpeakerRoles.customerPrefix : "Talare"
        var next = (existing.compactMap { number(in: $0, prefix: prefix) }.max() ?? 0) + 1
        while existing.contains("\(prefix) \(next)") { next += 1 }
        return "\(prefix) \(next)"
    }

    /// Ordtiderna utan ⚠: den som flyttar har själv bestämt vem som pratar.
    /// Lämnas orörda om inget ord är osäkert eller om de inte går att läsa.
    public static func clearingUncertainty(_ data: Data?) -> Data? {
        guard let data, WordTimingData.hasUncertainSpeaker(inEncoded: data),
              var words = try? JSONDecoder().decode([WordTimingData].self, from: data) else { return data }
        for index in words.indices { words[index].uncertainSpeaker = nil }
        return (try? JSONEncoder().encode(words)) ?? data
    }

    /// Ett byte av talare som går att ångra: segmenten som de var före bytet.
    public struct Undo: Equatable, Sendable {
        public struct Entry: Equatable, Sendable {
            public var index: Int
            public var speaker: String?
            public var wordsData: Data?

            public init(index: Int, speaker: String?, wordsData: Data?) {
                self.index = index
                self.speaker = speaker
                self.wordsData = wordsData
            }
        }

        public let entries: [Entry]
        /// Talaren segmenten flyttades till.
        public let speaker: String

        public init(entries: [Entry], speaker: String) {
            self.entries = entries
            self.speaker = speaker
        }

        /// Ångra går bara så länge segmenten fortfarande hör till talaren de flyttades till. Har talaren
        /// bytt namn eller fått en roll sedan dess skulle Ångra ge tillbaka ett namn som inte längre finns.
        public func canUndo(currentSpeakers: [Int: String?]) -> Bool {
            !entries.isEmpty && entries.allSatisfy { entry in
                guard let current = currentSpeakers[entry.index] else { return false }
                return current == speaker
            }
        }
    }

    private static func number(in name: String, prefix: String) -> Int? {
        let start = prefix + " "
        guard name.hasPrefix(start) else { return nil }
        return Int(name.dropFirst(start.count))
    }
}

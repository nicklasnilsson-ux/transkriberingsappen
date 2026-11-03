import Foundation

/// Vad ett sparat stycke hade innan rättningen, så att "Ångra" kan ge tillbaka det exakt.
/// Texten räcker inte: en rättning slänger ordtiderna (och därmed ⚠-märket), och de ska med tillbaka.
public struct EditUndo: Equatable, Sendable {
    /// Ett segment som det var: texten och de JSON-kodade ordtiderna.
    public struct Entry: Equatable, Sendable {
        public var index: Int
        public var text: String
        public var wordsData: Data?

        public init(index: Int, text: String, wordsData: Data?) {
            self.index = index
            self.text = text
            self.wordsData = wordsData
        }
    }

    /// Bara de segment som rättningen ändrade, som de var före den.
    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// Jämför stycket före och efter en rättning. `nil` om ingenting ändrades (då finns inget att ångra).
    public static func changes(before: [Entry], after: [Entry]) -> EditUndo? {
        let afterByIndex = Dictionary(after.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let changed = before.filter { entry in
            guard let now = afterByIndex[entry.index] else { return false }
            return now.text != entry.text || now.wordsData != entry.wordsData
        }
        return changed.isEmpty ? nil : EditUndo(entries: changed)
    }
}

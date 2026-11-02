import Foundation

/// Sökning som ignorerar skiftläge men respekterar å/ä/ö (så "for" inte matchar "för").
public enum TextSearch {
    public static let options: String.CompareOptions = [.caseInsensitive]

    public static func matches(_ text: String, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return text.range(of: query, options: options, locale: Locale(identifier: "sv_SE")) != nil
    }

    /// Alla träffar för `query` i `text`, i ordning.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: query,
                options: options,
                range: searchStart..<text.endIndex,
                locale: Locale(identifier: "sv_SE")
              ) {
            result.append(range)
            searchStart = range.upperBound
        }
        return result
    }

    /// Antal träffar i en samling texter.
    public static func countMatches(of query: String, in texts: [String]) -> Int {
        texts.reduce(0) { $0 + ranges(of: query, in: $1).count }
    }

    /// Alla träffar i en samling texter, i läsordning: vilken text och vilken träff i den texten.
    /// Används för att stega mellan träffarna som ⌘F i en webbläsare, medan hela texten visas.
    public static func hits<ID: Hashable>(of query: String, in items: [(id: ID, text: String)]) -> [SearchHit<ID>] {
        items.flatMap { item in
            ranges(of: query, in: item.text).indices.map { SearchHit(id: item.id, occurrence: $0) }
        }
    }

    /// Nästa (eller förra) träffen, runt till början igen efter den sista.
    public static func step(from index: Int, count: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        let next = forward ? index + 1 : index - 1
        return ((next % count) + count) % count
    }

    /// "3 av 12", "Inga träffar".
    public static func positionLabel(index: Int, count: Int) -> String {
        count == 0 ? "Inga träffar" : "\(min(index, count - 1) + 1) av \(count)"
    }
}

/// En sökträff: texten den finns i och vilken träff i ordningen i just den texten.
public struct SearchHit<ID: Hashable>: Hashable {
    public let id: ID
    public let occurrence: Int

    public init(id: ID, occurrence: Int) {
        self.id = id
        self.occurrence = occurrence
    }
}

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
}

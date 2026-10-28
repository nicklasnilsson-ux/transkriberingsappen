import SwiftUI
import TranskriberaCore

/// Bygger en AttributedString för ett segment med sökträffar och det ord
/// som just nu spelas upp markerade.
enum SegmentText {
    static func attributed(
        text: String,
        query: String,
        words: [WordTimingData],
        currentTime: Double?
    ) -> AttributedString {
        var attributed = AttributedString(text)

        // Markera ordet som spelas upp (karaoke-stil) med hjälp av ordtidsstämplarna.
        if let currentTime,
           let activeIndex = words.firstIndex(where: { currentTime >= $0.start && currentTime < $0.end }),
           let range = rangeOfWord(at: activeIndex, words: words, in: text),
           let attributedRange = Range(range, in: attributed) {
            attributed[attributedRange].foregroundColor = .accentColor
            attributed[attributedRange].underlineStyle = .single
        }

        // Platshållare från anonymiseringen, t.ex. "[PERSON 1]".
        if let placeholderRegex {
            for match in placeholderRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text), let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].foregroundColor = .secondary
                    attributed[attributedRange].backgroundColor = Color.secondary.opacity(0.15)
                }
            }
        }

        for range in TextSearch.ranges(of: query, in: text) {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].backgroundColor = .yellow.opacity(0.55)
                attributed[attributedRange].foregroundColor = .black
            }
        }
        return attributed
    }

    private static let placeholderRegex = try? NSRegularExpression(pattern: Anonymizer.placeholderPattern)

    /// Hittar ord nr `index` i texten genom att söka ordens text i tur och ordning.
    private static func rangeOfWord(at index: Int, words: [WordTimingData], in text: String) -> Range<String.Index>? {
        var cursor = text.startIndex
        for (i, word) in words.enumerated() {
            let needle = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            guard let range = text.range(of: needle, range: cursor..<text.endIndex) else {
                return nil
            }
            if i == index { return range }
            cursor = range.upperBound
        }
        return nil
    }
}

import SwiftUI
import TranskriberaCore

/// Orden i ett segment som har en annan tolkning (`CrossCheck`), med segmentets nummer för länken.
struct Alternatives {
    let segmentIndex: Int
    let words: [WordTimingData]

    /// `nil` när segmentet inte har några, eller när texten som visas inte är originalet
    /// (anonymiserad eller rättad): då stämmer orden inte med texten.
    @MainActor
    init?(_ segment: TranscriptSegment, displayText: String) {
        guard segment.alternativeCount > 0,
              displayText.trimmingCharacters(in: .whitespacesAndNewlines) == segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        segmentIndex = segment.index
        words = segment.words
    }
}

/// Bygger en AttributedString för ett segment med sökträffar och det ord
/// som just nu spelas upp markerade.
enum SegmentText {
    static func attributed(
        text: String,
        query: String,
        words: [WordTimingData],
        currentTime: Double?,
        currentOccurrence: Int? = nil,
        alternatives: Alternatives? = nil
    ) -> AttributedString {
        var attributed = AttributedString(text)

        // Experimentet Korskolla: ord som den andra körningen hörde annorlunda är prickat
        // understrukna och går att klicka på (menyn öppnas av `CrossCheckMenu`).
        if let alternatives {
            let ranges = CrossCheck.wordRanges(alternatives.words, in: text)
            for (index, word) in alternatives.words.enumerated() where word.alternative != nil {
                let last = min(alternatives.words.count - 1, index + max(1, word.alternativeLength ?? 1) - 1)
                guard let lower = ranges[index]?.lowerBound, let upper = ranges[last]?.upperBound,
                      let range = Range(lower..<upper, in: attributed),
                      let link = CrossCheck.link(segment: alternatives.segmentIndex, word: index) else { continue }
                attributed[range].link = link
                attributed[range].underlineStyle = Text.LineStyle(pattern: .dot, color: .accentColor)
            }
        }

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
                    attributed[attributedRange].foregroundColor = Color.textSecondary
                    attributed[attributedRange].backgroundColor = Color.textSecondary.opacity(0.15)
                }
            }
        }

        // Den träff man har stegat till är orange, som ⌘F i Safari; övriga träffar gula.
        for (index, range) in TextSearch.ranges(of: query, in: text).enumerated() {
            if let attributedRange = Range(range, in: attributed) {
                attributed[attributedRange].backgroundColor = index == currentOccurrence
                    ? .orange
                    : .yellow.opacity(0.55)
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

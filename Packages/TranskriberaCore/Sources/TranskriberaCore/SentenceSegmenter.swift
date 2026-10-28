import Foundation

/// Delar en lång följd av ord i segment, för modeller som (till skillnad från
/// Whisper) bara ger ord med tider och ingen egen uppdelning.
///
/// Ett segment slutar vid punkt, frågetecken eller utropstecken, vid en paus i talet,
/// eller när det blivit för långt.
public enum SentenceSegmenter {
    /// Paus (sekunder) mellan två ord som alltid ger ett nytt segment.
    static let pauseThreshold = 1.0
    /// Längsta segment i ord innan det delas vid nästa kommatecken, eller tvingas.
    static let softMaxWords = 25
    static let hardMaxWords = 40

    /// `words` ska vara i tidsordning. Orden får ha ett inledande mellanslag som i Whisper.
    public static func segments(from words: [WordTimingData]) -> [SegmentData] {
        var result: [SegmentData] = []
        var current: [WordTimingData] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = TextCleaning.clean(current.map(\.word).joined())
            if !text.isEmpty {
                result.append(SegmentData(start: first.start, end: last.end, text: text, words: current))
            }
            current = []
        }

        for word in words {
            if let previous = current.last, word.start - previous.end >= pauseThreshold {
                flush()
            }
            current.append(word)

            let trimmed = word.word.trimmingCharacters(in: .whitespaces)
            let endsSentence = trimmed.last.map { ".?!…".contains($0) } ?? false
            let endsClause = trimmed.last.map { ",;:".contains($0) } ?? false
            if endsSentence
                || (endsClause && current.count >= softMaxWords)
                || current.count >= hardMaxWords {
                flush()
            }
        }
        flush()
        return result
    }
}

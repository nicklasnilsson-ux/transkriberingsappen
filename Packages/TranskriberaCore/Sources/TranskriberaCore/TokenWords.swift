import Foundation

/// En del av ett ord från taligenkänningen (en SentencePiece-token) med tider.
public struct TimedToken: Hashable, Sendable {
    /// Tokentexten. Ett nytt ord börjar med mellanslag eller "▁".
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Bygger ord med tider av tokens från Parakeet (Pianissimo).
///
/// FluidAudio låter en token utan egen längd räcka fram till nästa token. Skiljetecknet
/// sist i en replik får därför ett slut efter pausen, inne i nästa talares tur, och då
/// hamnade ordet ("enkelt.") hos fel talare. Här bestämmer skiljetecken aldrig ordets
/// slut, och en token får som längst vara `maxTokenDuration` lång.
public enum TokenWords {
    static let maxTokenDuration = 0.4

    public static func words(from tokens: [TimedToken]) -> [WordTimingData] {
        var words: [WordTimingData] = []
        for token in tokens {
            let startsWord = token.text.hasPrefix(" ") || token.text.hasPrefix("▁")
            let piece = startsWord ? String(token.text.dropFirst()) : token.text
            guard !piece.isEmpty, piece != "<blank>", piece != "<pad>" else { continue }
            let end = min(token.end, token.start + maxTokenDuration)

            if words.isEmpty || (startsWord && !isPunctuation(piece)) {
                words.append(WordTimingData(word: " " + piece, start: token.start, end: max(end, token.start), probability: 1))
            } else {
                words[words.count - 1].word += piece
                if !isPunctuation(piece) {
                    words[words.count - 1].end = max(words[words.count - 1].end, end)
                }
            }
        }
        return words
    }

    static func isPunctuation(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }
}

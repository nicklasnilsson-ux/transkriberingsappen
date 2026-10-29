import Foundation

/// Rättar namn ur ordlistan som modellen hört nästan rätt, t.ex. "Fotnox" → "Fortnox".
///
/// Pianissimo kan inte få ordlistan som ledtråd, så namnen rättas i efterhand. Bara namn
/// (ord i listan som börjar med versal) rättas, och bara ord mitt i en mening som själva
/// börjar med versal: annars skulle vanliga ord som "visa" bli "Visma". Fackord med gemen
/// rättas inte, eftersom böjningar ("kunden", "kunder") ligger lika nära varandra som
/// hörfel.
public enum VocabularyCorrection {
    /// Kortare namn än så rättas inte, eftersom för många vanliga ord ligger nära dem.
    static let minimumLength = 5

    public static func apply(_ segments: [SegmentData], vocabulary: [String]) -> [SegmentData] {
        let names = vocabulary.filter(isName)
        guard !names.isEmpty else { return segments }

        return segments.map { segment in
            var output = segment
            if segment.words.isEmpty {
                let tokens = segment.text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                output.text = correctTokens(tokens, names: names).joined(separator: " ")
            } else {
                let words = correctTokens(segment.words.map(\.word), names: names)
                if words != segment.words.map(\.word) {
                    for index in words.indices { output.words[index].word = words[index] }
                    output.text = TextCleaning.clean(words.joined())
                }
            }
            return output
        }
    }

    /// Rättar en följd av ord (med mellanslag och skiljetecken kvar runt orden).
    static func correctTokens(_ tokens: [String], names: [String]) -> [String] {
        var result = tokens
        var sentenceStart = true
        for (index, token) in tokens.enumerated() {
            let parts = split(token)
            if !parts.core.isEmpty {
                if !sentenceStart, let name = match(parts.core, names: names) {
                    result[index] = parts.prefix + name + parts.suffix
                }
                sentenceStart = parts.suffix.contains { ".?!…".contains($0) }
            }
        }
        return result
    }

    /// Namnet som `word` sannolikt är ett hörfel för, eller nil.
    static func match(_ word: String, names: [String]) -> String? {
        guard let first = word.first, first.isUppercase, word.allSatisfy(\.isLetter) else { return nil }
        let lower = word.lowercased()
        var best: (name: String, distance: Int)?
        var tie = false
        for name in names {
            let target = name.lowercased()
            guard target != lower else { return word == name ? nil : name }
            guard target.first == lower.first else { continue }
            let allowed = target.count >= 8 ? 2 : 1
            guard abs(target.count - lower.count) <= allowed else { continue }
            let distance = editDistance(Array(lower), Array(target))
            guard distance <= allowed else { continue }
            if let current = best {
                if distance < current.distance {
                    best = (name, distance)
                    tie = false
                } else if distance == current.distance {
                    tie = true
                }
            } else {
                best = (name, distance)
            }
        }
        return tie ? nil : best?.name
    }

    static func isName(_ term: String) -> Bool {
        guard let first = term.first, first.isUppercase else { return false }
        return term.count >= minimumLength && term.allSatisfy(\.isLetter)
    }

    /// Delar "  Fotnox," i mellanslag före, själva ordet och skiljetecken efter.
    static func split(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let prefix = String(token.prefix { $0.isWhitespace })
        let rest = token.dropFirst(prefix.count)
        let core = String(rest.prefix { !$0.isPunctuation && !$0.isWhitespace })
        let suffix = String(rest.dropFirst(core.count))
        return (prefix, core, suffix)
    }

    /// Levenshtein-avstånd: antal tecken som måste läggas till, tas bort eller bytas.
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[b.count]
    }
}

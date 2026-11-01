import Foundation

/// Redigering i den anonymiserade texten utan att originalet skrivs över.
///
/// Texten som visas är originalet med platshållare ("[PERSON 1]") i stället för de dolda
/// uppgifterna. När den rättas här räknas ändringen tillbaka till originalet: allt utanför det
/// som rättats behålls ordagrant, och en platshållare som inte rörts ger tillbaka den dolda
/// uppgiften. Rör man en platshållare ersätts hela den uppgiften med det man skrev.
public struct AnonymizedEditing: Sendable {
    /// En bit av den visade texten och motsvarande bit av originalet.
    struct Piece {
        var shown: Range<Int>
        var original: Range<Int>
        var isPlaceholder: Bool
    }

    private let shown: [Character]
    private let original: [Character]
    private let pieces: [Piece]

    /// `nil` om den visade texten inte går att koppla tillbaka till originalet. Då ska stycket
    /// inte kunna rättas med anonymiseringen på.
    public init?(original: String, shown: String) {
        let orig = Array(original)
        let show = Array(shown)
        if orig == show {
            self.original = orig
            self.shown = show
            self.pieces = [Piece(shown: 0..<show.count, original: 0..<orig.count, isPlaceholder: false)]
            return
        }
        guard let pieces = Self.match(original: orig, shown: show) else { return nil }
        self.original = orig
        self.shown = show
        self.pieces = pieces
    }

    /// Originalet med `edited` (den rättade visade texten) inlagd.
    public func originalText(applying edited: String) -> String {
        let new = Array(edited)
        if new == shown { return String(original) }

        // Den del som ändrats: det som är olika mellan början och slutet.
        var prefix = 0
        let limit = min(shown.count, new.count)
        while prefix < limit && shown[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix && shown[shown.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        var start = prefix
        var end = shown.count - suffix
        // En platshållare som rörs byts ut i sin helhet.
        for piece in pieces where piece.isPlaceholder {
            let touched = start == end
                ? (piece.shown.lowerBound < start && start < piece.shown.upperBound)
                : (piece.shown.lowerBound < end && piece.shown.upperBound > start)
            if touched {
                start = min(start, piece.shown.lowerBound)
                end = max(end, piece.shown.upperBound)
            }
        }

        let delta = new.count - shown.count
        let replacement = Array(new[start..<(end + delta)])
        let originalStart = mapBoundary(start)
        let originalEnd = mapBoundary(end)
        return String(original[..<originalStart]) + String(replacement) + String(original[originalEnd...])
    }

    // MARK: - Koppling

    /// Läget i originalet för ett läge i den visade texten. Lägen inne i en platshållare
    /// förekommer inte här, eftersom ändringen vidgats till hela platshållare.
    private func mapBoundary(_ position: Int) -> Int {
        for piece in pieces {
            if piece.isPlaceholder {
                if position == piece.shown.lowerBound { return piece.original.lowerBound }
                if position == piece.shown.upperBound { return piece.original.upperBound }
            } else if piece.shown.contains(position) || position == piece.shown.upperBound {
                return piece.original.lowerBound + (position - piece.shown.lowerBound)
            }
        }
        return original.count
    }

    /// Delar den visade texten vid platshållarna och letar upp de bitar av originalet som
    /// ligger mellan texten före och efter. `nil` om det är tvetydigt eller inte stämmer.
    static func match(original: [Character], shown: [Character]) -> [Piece]? {
        guard let regex = try? NSRegularExpression(pattern: Anonymizer.placeholderPattern) else { return nil }
        let shownString = String(shown)
        let matches = regex.matches(in: shownString, range: NSRange(shownString.startIndex..., in: shownString))
        // Platshållarnas lägen i tecken (inte UTF-16).
        var spans: [Range<Int>] = []
        for match in matches {
            guard let range = Range(match.range, in: shownString) else { return nil }
            let lower = shownString.distance(from: shownString.startIndex, to: range.lowerBound)
            let upper = shownString.distance(from: shownString.startIndex, to: range.upperBound)
            spans.append(lower..<upper)
        }
        if spans.isEmpty { return nil }

        var pieces: [Piece] = []
        var shownCursor = 0
        var originalCursor = 0
        for (index, span) in spans.enumerated() {
            let literal = Array(shown[shownCursor..<span.lowerBound])
            // Texten före platshållaren finns ordagrant i originalet.
            guard originalCursor + literal.count <= original.count,
                  Array(original[originalCursor..<(originalCursor + literal.count)]) == literal else { return nil }
            if !literal.isEmpty {
                pieces.append(Piece(
                    shown: shownCursor..<span.lowerBound,
                    original: originalCursor..<(originalCursor + literal.count),
                    isPlaceholder: false
                ))
            }
            originalCursor += literal.count

            // Den dolda uppgiften slutar där texten efter platshållaren börjar.
            let nextLiteralEnd = index + 1 < spans.count ? spans[index + 1].lowerBound : shown.count
            let following = Array(shown[span.upperBound..<nextLiteralEnd])
            let hiddenEnd: Int
            if index + 1 == spans.count {
                // Sista platshållaren: det som följer är resten av originalet.
                guard following.count <= original.count - originalCursor,
                      Array(original[(original.count - following.count)...]) == following else { return nil }
                hiddenEnd = original.count - following.count
            } else {
                // Mellan två platshållare måste texten emellan vara unik och icke-tom.
                guard !following.isEmpty,
                      let found = Self.firstIndex(of: following, in: original, from: originalCursor + 1) else { return nil }
                hiddenEnd = found
            }
            guard hiddenEnd > originalCursor else { return nil }
            pieces.append(Piece(
                shown: span,
                original: originalCursor..<hiddenEnd,
                isPlaceholder: true
            ))
            originalCursor = hiddenEnd
            shownCursor = span.upperBound
        }
        // Texten efter sista platshållaren.
        if shownCursor < shown.count {
            pieces.append(Piece(
                shown: shownCursor..<shown.count,
                original: originalCursor..<original.count,
                isPlaceholder: false
            ))
        }
        return pieces
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character], from start: Int) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count, start <= haystack.count - needle.count else { return nil }
        for i in start...(haystack.count - needle.count) where Array(haystack[i..<(i + needle.count)]) == needle {
            return i
        }
        return nil
    }
}

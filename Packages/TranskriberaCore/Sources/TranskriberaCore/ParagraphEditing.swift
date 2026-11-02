import Foundation

/// Ett stycke rättas i ett enda textfält med samma löpande text som i visningsläget, så att
/// radbrytningen och höjden blir desamma. När det sparas förs ändringen tillbaka till de
/// segment som stycket består av, så att varje segment behåller sin tidskod.
///
/// Orden i den gamla och den nya texten paras ihop (längsta gemensamma följd). Ord som finns
/// kvar stannar i sitt segment. Nya ord som ersätter gamla hamnar där de gamla låg, och nya
/// ord som bara läggs till hamnar i segmentet före. Flera rättningar på olika ställen i
/// stycket hamnar därför var och en i rätt segment.
public enum ParagraphEditing {
    /// Styckets text som den visas: segmenten utan omgivande blanktecken, tomma hoppas över,
    /// åtskilda av ett mellanslag. Samma regel som visningen av stycket.
    public static func join(_ texts: [String]) -> String {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Segmentens texter efter att stycket rättats till `edited`. Segment som inte rörts
    /// behålls ordagrant. Ett segment vars alla ord tagits bort blir tomt.
    public static func split(_ texts: [String], edited: String) -> [String] {
        var oldWords: [String] = []
        var oldSegment: [Int] = []
        var segments: [Int] = []
        for (index, text) in texts.enumerated() {
            let words = Self.words(text)
            guard !words.isEmpty else { continue }
            segments.append(index)
            oldWords += words
            oldSegment += Array(repeating: index, count: words.count)
        }
        let newWords = Self.words(edited)
        guard let firstSegment = segments.first, oldWords != newWords else { return texts }

        let n = oldWords.count
        let m = newWords.count
        // lcs[i][j] = längsta gemensamma följd av oldWords[i...] och newWords[j...].
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = oldWords[i] == newWords[j]
                        ? lcs[i + 1][j + 1] + 1
                        : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var owner = Array(repeating: firstSegment, count: m)
        var pendingNew: [Int] = []
        var pendingOld: [Int] = []
        var lastSegment = firstSegment
        func flush() {
            // Nya ord som ersätter gamla hör till de gamlas segment, tillägg till segmentet före.
            let segment = pendingOld.first.map { oldSegment[$0] } ?? lastSegment
            for j in pendingNew { owner[j] = segment }
            pendingNew = []
            pendingOld = []
        }
        var i = 0
        var j = 0
        while i < n || j < m {
            if i < n, j < m, oldWords[i] == newWords[j] {
                flush()
                owner[j] = oldSegment[i]
                lastSegment = oldSegment[i]
                i += 1
                j += 1
            } else if j < m, i >= n || lcs[i][j + 1] >= lcs[i + 1][j] {
                pendingNew.append(j)
                j += 1
            } else {
                pendingOld.append(i)
                i += 1
            }
        }
        flush()

        var result = texts
        for segment in segments {
            let words = (0..<m).filter { owner[$0] == segment }.map { newWords[$0] }
            let before = (0..<n).filter { oldSegment[$0] == segment }.map { oldWords[$0] }
            if words != before { result[segment] = words.joined(separator: " ") }
        }
        return result
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

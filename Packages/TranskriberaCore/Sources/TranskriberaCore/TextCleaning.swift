import Foundation

public enum TextCleaning {
    /// Tar bort Whispers specialtokens (t.ex. "<|sv|>", "<|0.00|>") och onödiga mellanslag.
    public static func clean(_ text: String) -> String {
        let withoutTokens = text.replacingOccurrences(
            of: #"<\|[^|]*\|>"#,
            with: "",
            options: .regularExpression
        )
        let collapsed = withoutTokens.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Delar upp en lista som användaren skrivit, med komma, semikolon eller radbrytning mellan orden.
    public static func wordList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whisper hittar ibland på text i tystnad, t.ex. "[Musik]" eller "(tystnad)".
    /// Returnerar true om segmentet bara består av en sådan markering.
    public static func isNonSpeechMarker(_ text: String) -> Bool {
        let trimmed = clean(text)
        guard !trimmed.isEmpty else { return true }
        let pattern = #"^[\[\(\*♪].*[\]\)\*♪]$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

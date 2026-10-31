import Foundation

/// Export anpassad för analys, t.ex. när transkriberingar från användartester
/// ska tematiseras av Claude: en Markdown-fil per session med ett kort huvud
/// och ett stycke per talarbyte, med en tidskod per stycke.
public enum AnalysisExporter {
    /// Nytt stycke när det är minst så här lång paus (sekunder), om talare saknas.
    static let pauseBreak: Double = 3
    /// Max antal segment per stycke om talare saknas.
    static let maxSegmentsWithoutSpeakers = 6

    struct Paragraph: Equatable {
        var start: Double
        var speaker: String?
        var text: String
        /// Osäkert vem som sa hela stycket (⚠ efter talaren).
        var uncertain = false
        /// Osäkert vem som sa någon del av stycket (⚠ framför just den delen).
        var hasUncertainPart = false
    }

    /// Står efter talarens namn när det är osäkert vem som sa repliken.
    public static let uncertainMark = "⚠"

    /// Rubriken över förklaringen av filen.
    public static let guideHeading = "Om den här filen"

    /// Förklarar filen för den som läser den, t.ex. en AI som ska analysera intervjun:
    /// vad ⚠, platshållare och roller betyder och vad en automatisk transkribering kan missa.
    /// Bara det som gäller filen tas med, och texten är en beskrivning, inga order.
    static func guide(speakers: [String], hasUncertainty: Bool, isAnonymized: Bool) -> [String] {
        var lines = [
            "Texten är en automatisk transkribering och kan innehålla hörfel, särskilt i namn, facktermer och korta ord.",
            "Enstaka småord och fyllnadsljud som ”eh” och ”mm” kan saknas, och ett talarbyte kan ligga några ord fel.",
            "Tidskoden i början av varje stycke är när stycket börjar (minuter:sekunder)."
        ]
        if hasUncertainty {
            lines.append("\(uncertainMark) betyder att det är osäkert vem som sa just den repliken (eller delen efter märket). Det säger inget om hur säker texten är. Märkta delar kan höra till grannens replik.")
        }
        if speakers.contains(where: { $0.hasPrefix("Intervjuare") || $0.hasPrefix("Kund") }) {
            lines.append("Intervjuare och Kund 1, Kund 2 … är roller, inte namn. Rollerna har bestämts av programmet och användaren.")
        }
        if isAnonymized {
            lines.append("Namn och andra uppgifter som kan identifiera någon är ersatta med platshållare som [PERSON 1] eller [PLATS 1]. Samma nummer är samma person eller plats i hela filen. Platshållarna är inga ord i originalet.")
        }
        return lines
    }

    /// Sant om texten innehåller platshållare från anonymiseringen, t.ex. "[PERSON 1]".
    static func isAnonymized(_ segments: [SegmentData]) -> Bool {
        segments.contains { $0.text.range(of: #"\[[A-ZÅÄÖ]+( \d+)?\]"#, options: .regularExpression) != nil }
    }

    public static func markdown(
        _ segments: [SegmentData],
        metadata: TranscriptMetadata,
        timeZone: TimeZone = .current,
        includeGuide: Bool = false
    ) -> String {
        let segments = segments.filter { !$0.text.trimmed.isEmpty }
        let paragraphs = paragraphs(segments)

        var out = "# \(metadata.title)\n\n"
        var header = [
            "- Datum: \(dateString(metadata.createdAt, timeZone: timeZone))",
            "- Längd: \(TimeFormatting.duration(metadata.duration))"
        ]
        let speakers = uniqueSpeakers(segments)
        if !speakers.isEmpty {
            header.append("- Talare: \(speakers.joined(separator: ", "))")
        }
        if let language = metadata.language {
            header.append("- Språk: \(language)")
        }
        if paragraphs.contains(where: { ($0.uncertain || $0.hasUncertainPart) && $0.speaker != nil }) {
            header.append("- \(uncertainMark) = osäkert vem som sa repliken")
        }
        out += header.joined(separator: "\n") + "\n\n"
        if includeGuide {
            let uncertain = paragraphs.contains { ($0.uncertain || $0.hasUncertainPart) && $0.speaker != nil }
            let lines = guide(speakers: speakers, hasUncertainty: uncertain, isAnonymized: isAnonymized(segments))
            out += "## \(guideHeading)\n\n" + lines.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        out += "---\n\n"

        out += paragraphs.map { paragraph in
            var line = "[\(TimeFormatting.short(paragraph.start))] "
            if let speaker = paragraph.speaker {
                line += "**\(speaker):** "
                if paragraph.uncertain { line += "\(uncertainMark) " }
            }
            return line + paragraph.text
        }.joined(separator: "\n\n")
        return out + "\n"
    }

    /// Filnamn för sessionen, utan tecken som inte fungerar i Finder.
    public static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden).joined(separator: "-").trimmed
        let base = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "Transkribering" : cleaned
        return "\(base).md"
    }

    /// Unika filnamn när flera sessioner exporteras till samma mapp.
    public static func uniqueFileNames(for titles: [String]) -> [String] {
        var used = Set<String>()
        return titles.map { title in
            let name = fileName(for: title)
            let base = String(name.dropLast(3))
            var candidate = name
            var counter = 2
            while used.contains(candidate.lowercased()) {
                candidate = "\(base) \(counter).md"
                counter += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    // MARK: - Stycken

    static func paragraphs(_ segments: [SegmentData]) -> [Paragraph] {
        paragraphRanges(segments).map { range in
            let parts = segments[range].filter { !$0.text.trimmed.isEmpty }
            let allUncertain = !parts.isEmpty && parts.allSatisfy(\.uncertainSpeaker)
            let anyUncertain = parts.contains(where: \.uncertainSpeaker)
            return Paragraph(
                start: segments[range.lowerBound].start,
                speaker: segments[range.lowerBound].speaker,
                text: allUncertain || !anyUncertain ? parts.map(\.text.trimmed).joined(separator: " ") : markedText(parts),
                uncertain: allUncertain,
                hasUncertainPart: anyUncertain
            )
        }
    }

    /// Texten med ⚠ framför varje osäker del, så att en kort replik i ett långt stycke
    /// märks ut för sig i stället för att hela stycket blir osäkert.
    static func markedText(_ parts: [SegmentData]) -> String {
        var out: [String] = []
        var previousUncertain = false
        for part in parts {
            if part.uncertainSpeaker && !previousUncertain { out.append(uncertainMark) }
            out.append(part.text.trimmed)
            previousUncertain = part.uncertainSpeaker
        }
        return out.joined(separator: " ")
    }

    /// Delar upp segmenten i stycken: ett nytt stycke vid varje talarbyte, eller
    /// vid pauser och efter ett visst antal segment om talare saknas. Används
    /// både av exporten och av styckevyn i appen. Tomma segment hamnar i
    /// stycket före och påbörjar aldrig ett eget (utom först).
    public static func paragraphRanges(_ segments: [SegmentData]) -> [Range<Int>] {
        let hasSpeakers = segments.contains { $0.speaker != nil }
        var ranges: [Range<Int>] = []
        var lastSpeaker: String?
        var countInParagraph = 0
        var previousEnd: Double?

        for (index, segment) in segments.enumerated() {
            let isEmpty = segment.text.trimmed.isEmpty
            let startsNew: Bool
            if ranges.isEmpty {
                startsNew = true
            } else if isEmpty {
                startsNew = false
            } else if hasSpeakers {
                startsNew = lastSpeaker != segment.speaker
            } else {
                let pause = segment.start - (previousEnd ?? segment.start)
                startsNew = pause >= pauseBreak || countInParagraph >= maxSegmentsWithoutSpeakers
            }

            if startsNew {
                ranges.append(index..<index + 1)
                lastSpeaker = segment.speaker
                countInParagraph = isEmpty ? 0 : 1
            } else {
                ranges[ranges.count - 1] = ranges[ranges.count - 1].lowerBound..<index + 1
                if !isEmpty { countInParagraph += 1 }
            }
            if !isEmpty { previousEnd = segment.end }
        }
        return ranges
    }

    static func uniqueSpeakers(_ segments: [SegmentData]) -> [String] {
        var seen = Set<String>()
        return segments.compactMap(\.speaker).filter { seen.insert($0).inserted }
    }

    static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

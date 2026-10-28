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
    }

    public static func markdown(
        _ segments: [SegmentData],
        metadata: TranscriptMetadata,
        timeZone: TimeZone = .current
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
        out += header.joined(separator: "\n") + "\n\n---\n\n"

        out += paragraphs.map { paragraph in
            var line = "[\(TimeFormatting.short(paragraph.start))] "
            if let speaker = paragraph.speaker {
                line += "**\(speaker):** "
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
        let hasSpeakers = segments.contains { $0.speaker != nil }
        var result: [Paragraph] = []
        var countInParagraph = 0
        var previousEnd: Double?

        for segment in segments {
            let text = segment.text.trimmed
            let startsNew: Bool
            if let last = result.last {
                if hasSpeakers {
                    startsNew = last.speaker != segment.speaker
                } else {
                    let pause = segment.start - (previousEnd ?? segment.start)
                    startsNew = pause >= pauseBreak || countInParagraph >= maxSegmentsWithoutSpeakers
                }
            } else {
                startsNew = true
            }

            if startsNew {
                result.append(Paragraph(start: segment.start, speaker: segment.speaker, text: text))
                countInParagraph = 1
            } else {
                result[result.count - 1].text += " " + text
                countInParagraph += 1
            }
            previousEnd = segment.end
        }
        return result
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

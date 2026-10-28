import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case plainText
    case markdown
    case srt
    case vtt
    case json

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plainText: return "Ren text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .srt: return "Undertexter (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        case .json: return "JSON (.json)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .json: return "json"
        }
    }
}

public struct ExportOptions: Sendable {
    /// Ta med tidsstämplar i .txt/.md.
    public var includeTimestamps: Bool
    /// Ta med talarnamn där de finns.
    public var includeSpeakers: Bool
    /// Max antal tecken per undertextrad innan segmentet delas (0 = dela aldrig).
    public var maxSubtitleCharacters: Int

    public init(includeTimestamps: Bool = true, includeSpeakers: Bool = true, maxSubtitleCharacters: Int = 84) {
        self.includeTimestamps = includeTimestamps
        self.includeSpeakers = includeSpeakers
        self.maxSubtitleCharacters = maxSubtitleCharacters
    }
}

public enum TranscriptExporter {
    public static func export(
        _ segments: [SegmentData],
        metadata: TranscriptMetadata,
        format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ) -> String {
        let segments = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch format {
        case .plainText: return plainText(segments, options: options)
        case .markdown: return markdown(segments, metadata: metadata, options: options)
        case .srt: return srt(subtitleCues(segments, options: options), options: options)
        case .vtt: return vtt(subtitleCues(segments, options: options), options: options)
        case .json: return json(segments, metadata: metadata)
        }
    }

    /// Hela texten utan tidsstämplar, med stycke vid talarbyte.
    public static func fullText(_ segments: [SegmentData]) -> String {
        plainText(segments, options: ExportOptions(includeTimestamps: false, includeSpeakers: true))
    }

    // MARK: - Text

    static func plainText(_ segments: [SegmentData], options: ExportOptions) -> String {
        if options.includeTimestamps {
            return segments.map { segment in
                var line = "[\(TimeFormatting.short(segment.start))] "
                if options.includeSpeakers, let speaker = segment.speaker {
                    line += "\(speaker): "
                }
                return line + segment.text.trimmed
            }.joined(separator: "\n") + "\n"
        }

        // Utan talare: dela upp i stycken om sex segment för läsbarhet.
        let hasSpeakers = options.includeSpeakers && segments.contains { $0.speaker != nil }
        guard hasSpeakers else {
            let chunks = stride(from: 0, to: segments.count, by: 6).map { start in
                segments[start..<min(start + 6, segments.count)].map { $0.text.trimmed }.joined(separator: " ")
            }
            return chunks.joined(separator: "\n\n") + "\n"
        }

        // Med talare: nytt stycke vid varje talarbyte.
        var paragraphs: [(speaker: String?, text: String)] = []
        for segment in segments {
            if let last = paragraphs.last, last.speaker == segment.speaker {
                paragraphs[paragraphs.count - 1].text += " " + segment.text.trimmed
            } else {
                paragraphs.append((segment.speaker, segment.text.trimmed))
            }
        }
        return paragraphs.map { paragraph in
            paragraph.speaker.map { "\($0): \(paragraph.text)" } ?? paragraph.text
        }.joined(separator: "\n\n") + "\n"
    }

    static func markdown(_ segments: [SegmentData], metadata: TranscriptMetadata, options: ExportOptions) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "sv_SE")
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var out = "# \(metadata.title)\n\n"
        var meta = ["**Datum:** \(dateFormatter.string(from: metadata.createdAt))",
                    "**Längd:** \(TimeFormatting.duration(metadata.duration))"]
        if let language = metadata.language { meta.append("**Språk:** \(language)") }
        out += meta.joined(separator: "  \n") + "\n\n---\n\n"

        var lastSpeaker: String? = nil
        for segment in segments {
            var line = ""
            if options.includeSpeakers, let speaker = segment.speaker, speaker != lastSpeaker {
                out += "\n### \(speaker)\n\n"
                lastSpeaker = speaker
            }
            if options.includeTimestamps {
                line += "`\(TimeFormatting.short(segment.start))` "
            }
            line += segment.text.trimmed
            out += line + "\n\n"
        }
        return out.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    // MARK: - Undertexter

    struct Cue: Equatable {
        var start: Double
        var end: Double
        var text: String
        var speaker: String?
    }

    /// Delar långa segment i kortare undertexter, med hjälp av ordtidsstämplar när de finns.
    static func subtitleCues(_ segments: [SegmentData], options: ExportOptions) -> [Cue] {
        var cues: [Cue] = []
        for segment in segments {
            let text = segment.text.trimmed
            let limit = options.maxSubtitleCharacters
            guard limit > 0, text.count > limit else {
                cues.append(Cue(start: segment.start, end: segment.end, text: text, speaker: segment.speaker))
                continue
            }
            guard !segment.words.isEmpty else {
                cues += splitByCharacters(text, start: segment.start, end: segment.end, limit: limit, speaker: segment.speaker)
                continue
            }
            var currentWords: [WordTimingData] = []
            var currentLength = 0
            func flush() {
                guard let first = currentWords.first, let last = currentWords.last else { return }
                let cueText = currentWords.map(\.word).joined().trimmed
                cues.append(Cue(start: first.start, end: last.end, text: cueText, speaker: segment.speaker))
                currentWords = []
                currentLength = 0
            }
            for word in segment.words {
                if currentLength + word.word.count > limit, !currentWords.isEmpty {
                    flush()
                }
                currentWords.append(word)
                currentLength += word.word.count
            }
            flush()
        }
        // Se till att varje undertext har positiv längd.
        return cues.map { cue in
            var cue = cue
            if cue.end <= cue.start { cue.end = cue.start + 0.5 }
            return cue
        }
    }

    /// Delar på ordgränser utan ordtidsstämplar (t.ex. efter redigering eller anonymisering)
    /// och fördelar tiden efter antal tecken.
    static func splitByCharacters(_ text: String, start: Double, end: Double, limit: Int, speaker: String?) -> [Cue] {
        var lines: [String] = []
        for word in text.split(separator: " ") {
            if let last = lines.last, last.count + 1 + word.count <= limit {
                lines[lines.count - 1] += " " + word
            } else {
                lines.append(String(word))
            }
        }
        let total = Double(lines.reduce(0) { $0 + $1.count })
        guard total > 0 else { return [] }
        var cues: [Cue] = []
        var cursor = start
        for (index, line) in lines.enumerated() {
            let lineEnd = index == lines.count - 1 ? end : cursor + (end - start) * Double(line.count) / total
            cues.append(Cue(start: cursor, end: lineEnd, text: line, speaker: speaker))
            cursor = lineEnd
        }
        return cues
    }

    static func srt(_ cues: [Cue], options: ExportOptions) -> String {
        cues.enumerated().map { index, cue in
            var text = cue.text
            if options.includeSpeakers, let speaker = cue.speaker { text = "\(speaker): \(text)" }
            return "\(index + 1)\n\(TimeFormatting.srt(cue.start)) --> \(TimeFormatting.srt(cue.end))\n\(text)\n"
        }.joined(separator: "\n")
    }

    static func vtt(_ cues: [Cue], options: ExportOptions) -> String {
        var out = "WEBVTT\n\n"
        out += cues.map { cue in
            var text = cue.text
            if options.includeSpeakers, let speaker = cue.speaker { text = "<v \(speaker)>\(text)" }
            return "\(TimeFormatting.vtt(cue.start)) --> \(TimeFormatting.vtt(cue.end))\n\(text)\n"
        }.joined(separator: "\n")
        return out
    }

    // MARK: - JSON

    struct JSONDocument: Encodable {
        var title: String
        var createdAt: Date
        var duration: Double
        var language: String?
        var model: String?
        var text: String
        var segments: [SegmentData]
    }

    static func json(_ segments: [SegmentData], metadata: TranscriptMetadata) -> String {
        let document = JSONDocument(
            title: metadata.title,
            createdAt: metadata.createdAt,
            duration: metadata.duration,
            language: metadata.language,
            model: metadata.model,
            text: segments.map { $0.text.trimmed }.joined(separator: " "),
            segments: segments
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string + "\n"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

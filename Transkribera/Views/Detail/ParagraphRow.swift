import SwiftData
import SwiftUI
import TranskriberaCore

/// Ett stycke i transkriberingen: segmenten från samma talare sammanslagna
/// till löpande text, med en tidskod och talarens namn.
struct ParagraphRow: View {
    let rows: [DisplaySegment]
    let query: String
    let activeID: PersistentIdentifier?
    let currentTime: Double?
    let isEditing: Bool
    let onSeek: (Double) -> Void

    private var start: Double { rows.first?.segment.start ?? 0 }
    private var isActive: Bool { rows.contains { $0.id == activeID } }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button { onSeek(start) } label: {
                Text(TimeFormatting.short(start))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 52, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Spela upp från \(TimeFormatting.short(start))")

            VStack(alignment: .leading, spacing: 4) {
                if let speaker = rows.first?.speaker {
                    Text(speaker)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(SpeakerPalette.color(for: speaker))
                }

                if isEditing {
                    // Varje segment rättas för sig, så att tidskoderna stämmer.
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { row in
                            SegmentEditor(segment: row.segment)
                        }
                    }
                } else {
                    Text(attributedText)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.06) : Color.clear)
        }
    }

    /// Segmentens text efter varandra, med sökträffar och det ord som spelas upp markerade.
    private var attributedText: AttributedString {
        var result = AttributedString()
        for row in rows {
            let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let active = row.id == activeID
            // Ordtidsstämplarna hör till originaltexten.
            let showsOriginal = row.text == row.segment.text
            if !result.characters.isEmpty { result += AttributedString(" ") }
            result += SegmentText.attributed(
                text: text,
                query: query,
                words: active && showsOriginal ? row.segment.words : [],
                currentTime: active ? currentTime : nil
            )
        }
        return result
    }
}

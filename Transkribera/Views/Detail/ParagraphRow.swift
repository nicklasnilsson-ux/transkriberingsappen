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
    /// Innehållet i ▾-menyn bredvid talarens namn.
    var speakerMenu: ((String) -> AnyView)? = nil

    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    private var start: Double { rows.first?.segment.start ?? 0 }
    private var isActive: Bool { rows.contains { $0.id == activeID } }

    /// Högst cirka 72 tecken per rad: bredden följer textstorleken.
    private var textWidth: CGFloat { ReadingTextSize.clamped(readingSize) * 40 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let speaker = rows.first?.speaker {
                    SpeakerLabel(name: speaker)
                    if let speakerMenu {
                        Menu { speakerMenu(speaker) } label: { Image(systemName: "chevron.down").font(.caption) }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Byt namn på talaren eller ange intervjuare")
                    }
                    if rows.contains(where: { $0.segment.isSpeakerUncertain }) {
                        UncertainSpeakerMark()
                    }
                }
                Button { onSeek(start) } label: {
                    Text(TimeFormatting.short(start))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .help("Spela upp från \(TimeFormatting.short(start))")
                if isActive {
                    Text("Spelas nu")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            if isEditing {
                // Varje segment rättas för sig, så att tidskoderna stämmer.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        SegmentEditor(segment: row.segment)
                    }
                }
                .frame(maxWidth: textWidth, alignment: .leading)
            } else {
                Text(attributedText)
                    .font(.system(size: ReadingTextSize.clamped(readingSize)))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: textWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .modifier(ActiveParagraphStyle(isActive: isActive))
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

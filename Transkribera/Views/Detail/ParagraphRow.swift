import SwiftData
import SwiftUI
import TranskriberaCore

/// Ett stycke i transkriberingen: segmenten från samma talare sammanslagna
/// till löpande text, med en tidskod och talarens namn.
struct ParagraphRow: View {
    let rows: [DisplaySegment]
    let query: String
    /// Träffen man har stegat till med sökfältets pilar, om den finns i det här stycket.
    var currentHit: SearchHit<PersistentIdentifier>? = nil
    let activeID: PersistentIdentifier?
    let currentTime: Double?
    let isEditing: Bool
    var session: EditSession? = nil
    /// Ett klick i texten öppnar stycket för rättning.
    var onBeginEdit: () -> Void = {}
    let onSeek: (Double) -> Void
    /// Innehållet i ▾-menyn bredvid talarens namn.
    var speakerMenu: ((String) -> AnyView)? = nil

    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard
    @State private var hovering = false

    private var start: Double { rows.first?.segment.start ?? 0 }
    private var isActive: Bool { rows.contains { $0.id == activeID } }

    /// Högst cirka 72 tecken per rad: bredden följer textstorleken.
    private var textWidth: CGFloat { ReadingTextSize.clamped(readingSize) * 40 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerLine
            paragraphText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .modifier(ActiveParagraphStyle(isActive: isActive))
        .onHover { hovering = $0 }
    }

    private var headerLine: some View {
        HStack(spacing: 6) {
            if let speaker = rows.first?.speaker {
                speakerGroup(speaker)
            }
            timeButton
            if isActive {
                Text("Spelas nu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
            if !isEditing { EditHoverButton(visible: hovering, action: onBeginEdit) }
        }
    }

    @ViewBuilder
    private func speakerGroup(_ speaker: String) -> some View {
        SpeakerLabel(name: speaker)
        if let speakerMenu {
            Menu {
                speakerMenu(speaker)
            } label: {
                Icon(.chevronDown, size: 12)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Byt namn på talaren eller ange intervjuare")
        }
        if rows.contains(where: { $0.segment.isSpeakerUncertain }) {
            UncertainSpeakerMark()
        }
    }

    private var timeButton: some View {
        TimecodeButton(time: start, isActive: isActive) { onSeek(start) }
    }

    @ViewBuilder
    private var paragraphText: some View {
        let size = ReadingTextSize.clamped(readingSize)
        if isEditing {
            // Hela stycket i ett fält, med samma radbrytning som visningen. Ändringen förs
            // tillbaka till rätt segment när fältet lämnas, så att tidskoderna stämmer.
            ParagraphEditor(rows: rows, lineSpacing: 4, session: session)
                .id(rows.map(\.isAnonymized))
                .frame(maxWidth: textWidth, alignment: .leading)
                .modifier(EditSurface())
        } else {
            Text(attributedText)
                .font(.system(size: size))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: textWidth, alignment: .leading)
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
                currentTime: active ? currentTime : nil,
                currentOccurrence: currentHit?.id == row.id ? currentHit?.occurrence : nil
            )
        }
        return result
    }
}

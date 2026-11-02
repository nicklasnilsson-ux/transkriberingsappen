import AppKit
import SwiftUI
import TranskriberaCore

/// En rad i transkriberingen: tidsstämpel, talare och text.
struct SegmentRow: View {
    @Bindable var segment: TranscriptSegment
    /// Texten och talaren som visas (anonymiserade eller original).
    let displayText: String
    let displaySpeaker: String?
    let query: String
    let isActive: Bool
    let currentTime: Double?
    let isEditing: Bool
    /// Texten som visas är anonymiserad; då rättas den visade texten och ändringen förs tillbaka till originalet.
    var isAnonymized = false
    let onSeek: () -> Void

    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TimecodeButton(time: segment.start, isActive: isActive, minWidth: 52, action: onSeek)

            VStack(alignment: .leading, spacing: 3) {
                if let speaker = displaySpeaker {
                    HStack(spacing: 6) {
                        SpeakerLabel(name: speaker, font: .caption.weight(.semibold))
                        if segment.isSpeakerUncertain {
                            UncertainSpeakerMark()
                        }
                    }
                }

                if isEditing {
                    SegmentEditor(segment: segment, displayText: displayText, isAnonymized: isAnonymized, lineSpacing: 3)
                        .id(isAnonymized)
                        .modifier(EditSurface())
                } else {
                    // Ordtidsstämplarna hör till originaltexten.
                    let showsOriginal = displayText == segment.text
                    Text(SegmentText.attributed(
                        text: displayText,
                        query: query,
                        words: isActive && showsOriginal ? segment.words : [],
                        currentTime: isActive ? currentTime : nil
                    ))
                    .font(.system(size: ReadingTextSize.clamped(readingSize)))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .modifier(ActiveParagraphStyle(isActive: isActive))
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            if !isEditing { onSeek() }
        }
    }
}

/// Textfält för att rätta ett segment (radlayouten). Ändringen sparas när fältet lämnas.
/// Med anonymisering på rättas den anonymiserade texten och ändringen förs tillbaka till
/// originalet (se `AnonymizedEditing`), så att de dolda uppgifterna aldrig skrivs över.
struct SegmentEditor: View {
    @Bindable var segment: TranscriptSegment
    /// Texten som visas i fältet: anonymiserad eller original.
    let displayText: String
    let isAnonymized: Bool
    /// Samma radavstånd som i visningsläget, så att texten inte byter höjd.
    var lineSpacing: CGFloat = 4

    /// Fylls redan när vyn skapas, så att fältet aldrig är tomt en bildruta (det ändrade höjden).
    @State private var draft: String
    /// Det fältet utgår från: originalet och hur det visades. Uppdateras efter varje sparning.
    @State private var baseOriginal: String
    @State private var baseShown: String
    @State private var mapping: AnonymizedEditing?
    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    init(segment: TranscriptSegment, displayText: String, isAnonymized: Bool, lineSpacing: CGFloat = 4) {
        _segment = Bindable(wrappedValue: segment)
        self.displayText = displayText
        self.isAnonymized = isAnonymized
        self.lineSpacing = lineSpacing
        _draft = State(initialValue: displayText)
        _baseOriginal = State(initialValue: segment.text)
        _baseShown = State(initialValue: displayText)
        _mapping = State(initialValue: isAnonymized ? AnonymizedEditing(original: segment.text, shown: displayText) : nil)
    }

    /// Falskt om den anonymiserade texten inte går att föra tillbaka till originalet.
    private var isEditable: Bool { !isAnonymized || mapping != nil }

    var body: some View {
        EditableText(
            text: $draft,
            isEditable: isEditable,
            lineSpacing: lineSpacing,
            isFocused: $isFocused,
            commit: commit
        )
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard isEditable else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = baseShown
            return
        }
        guard trimmed != baseShown.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        if isAnonymized, let mapping {
            let newOriginal = mapping.originalText(applying: trimmed)
            segment.updateText(newOriginal)
            baseOriginal = newOriginal
            baseShown = trimmed
            self.mapping = AnonymizedEditing(original: newOriginal, shown: trimmed)
        } else {
            segment.updateText(trimmed)
            baseOriginal = trimmed
            baseShown = trimmed
        }
    }
}

/// Ett helt stycke i ett enda textfält, med samma löpande text som i visningsläget, så att
/// radbrytningen och höjden blir desamma. Ändringen förs tillbaka till rätt segment när fältet
/// lämnas (se `ParagraphEditing`), och med anonymisering på till originalet (`AnonymizedEditing`).
struct ParagraphEditor: View {
    let rows: [DisplaySegment]
    var lineSpacing: CGFloat = 4

    @State private var draft: String
    /// Hur segmenten visades och vad som var sparat när fältet senast sparades.
    @State private var baseShown: [String]
    @FocusState private var isFocused: Bool

    init(rows: [DisplaySegment], lineSpacing: CGFloat = 4) {
        self.rows = rows
        self.lineSpacing = lineSpacing
        let shown = rows.map(\.text)
        _baseShown = State(initialValue: shown)
        _draft = State(initialValue: ParagraphEditing.join(shown))
    }

    /// Med anonymisering på går stycket bara att rätta om varje segment kan föras tillbaka.
    private var isEditable: Bool {
        rows.allSatisfy { row in
            !row.isAnonymized || AnonymizedEditing(original: row.segment.text, shown: row.text) != nil
        }
    }

    var body: some View {
        EditableText(
            text: $draft,
            isEditable: isEditable,
            lineSpacing: lineSpacing,
            isFocused: $isFocused,
            commit: commit
        )
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard isEditable else { return }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            draft = ParagraphEditing.join(baseShown)
            return
        }
        let newShown = ParagraphEditing.split(baseShown, edited: draft)
        guard newShown != baseShown else { return }
        for (index, row) in rows.enumerated() where newShown[index] != baseShown[index] {
            if row.isAnonymized {
                guard let mapping = AnonymizedEditing(original: row.segment.text, shown: baseShown[index]) else { continue }
                row.segment.updateText(mapping.originalText(applying: newShown[index]))
            } else {
                row.segment.updateText(newShown[index])
            }
        }
        baseShown = newShown
    }
}

/// Textfältet som både styckes- och radredigeringen använder. Samma typsnitt och radavstånd
/// som visningen, ingen padding. Fokus syns som en tonad bakgrund som inte tar plats.
struct EditableText: View {
    @Binding var text: String
    let isEditable: Bool
    let lineSpacing: CGFloat
    var isFocused: FocusState<Bool>.Binding
    let commit: () -> Void

    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    var body: some View {
        Group {
            if isEditable {
                TextField("Text", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused.wrappedValue) { _, focused in
                        if !focused { commit() }
                    }
            } else {
                Text(text)
                    .help("Det här stycket kan inte rättas med anonymiseringen på. Slå av anonymiseringen för att rätta det.")
            }
        }
        .font(.system(size: ReadingTextSize.clamped(readingSize)))
        .lineSpacing(lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused.wrappedValue ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

/// Fältytan i redigeringsläget: bakgrund och kant som ritas utanför texten och inte tar någon
/// plats i layouten. Texten har därför exakt samma mått i visnings- och redigeringsläget, och
/// ingenting hoppar när man växlar. Läggs på en hel rad eller ett helt stycke, inte på varje segment.
struct EditSurface: ViewModifier {
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(Color.accentColor.opacity(0.07))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
            }
            .overlay {
                shape.strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
            }
    }
}

/// Aktivt stycke: en accentlinje på 3 pt till vänster och accent med 10 % opacitet som bakgrund.
struct ActiveParagraphStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background { Color.accentColor.opacity(isActive ? 0.10 : 0) }
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.accentColor).frame(width: 3).opacity(isActive ? 1 : 0)
            }
    }
}

/// Talarens namn i vanlig textfärg, semibold, med en färgprick före. Färgen bär ingen
/// information ensam (kontrast), den är bara en hjälp att se talarbyten.
struct SpeakerLabel: View {
    let name: String
    var font: Font = .callout.weight(.semibold)

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(SpeakerPalette.color(for: name))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name)
                .font(font)
                .foregroundStyle(.primary)
        }
    }
}

/// Ger varje talare en egen, stabil färg. Används bara till prickar och band, inte till text.
enum SpeakerPalette {
    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown, .indigo]

    static func color(for speaker: String) -> Color {
        let hash = speaker.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return colors[hash % colors.count]
    }
}

/// ⚠ bredvid talaren när det är osäkert vem som sa repliken.
struct UncertainSpeakerMark: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(Color.warning)
            .help("Osäkert vem som sa det här, t.ex. vid ett talarbyte utan paus. Lyssna för att kontrollera.")
            .accessibilityLabel("Osäker talare")
    }
}

/// Tidskoden som knapp. I vila ser den ut som text. När pekaren är över visas en play-ikon
/// och en mjuk bakgrund, så att det syns att den går att klicka på. Ikonens plats är reserverad
/// hela tiden, så att ingenting flyttar sig. Träffytan är lika stor i stycken och rader.
struct TimecodeButton: View {
    let time: Double
    let isActive: Bool
    var minWidth: CGFloat? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let emphasized = isActive || hovering
        Button(action: action) {
            HStack(spacing: 4) {
                Text(TimeFormatting.short(time))
                    .font(.system(.callout, design: .monospaced))
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .opacity(hovering ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(emphasized ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .frame(minWidth: minWidth, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(hovering ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Paddingen tas tillbaka, så att raden har samma mått som förut.
        .padding(.horizontal, -6)
        .padding(.vertical, -2)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if hovering {
                NSCursor.pop()
                hovering = false
            }
        }
        .help("Spela upp från \(TimeFormatting.short(time))")
        .accessibilityLabel("Spela upp från \(TimeFormatting.short(time))")
    }
}

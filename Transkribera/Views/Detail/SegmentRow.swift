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
                    SegmentEditor(segment: segment, lineSpacing: 3)
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
                    .modifier(EditSurface(isEditing: false))
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

/// Textfält för att rätta ett segment. Ändringen sparas när fältet lämnas.
struct SegmentEditor: View {
    @Bindable var segment: TranscriptSegment
    /// Samma radavstånd som i visningsläget, så att texten inte byter höjd.
    var lineSpacing: CGFloat = 4

    @State private var draft = ""
    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    var body: some View {
        TextField("Text", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: ReadingTextSize.clamped(readingSize)))
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(EditSurface(isEditing: true, focused: isFocused))
            .focused($isFocused)
            .onAppear { draft = segment.text }
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = segment.text
            return
        }
        segment.updateText(trimmed)
    }
}

/// Ytan runt en text. Samma padding i visnings- och redigeringsläget, så att bara kant och
/// bakgrund ändras när man går in i redigeringsläget och ingenting flyttar sig.
/// Den vänstra paddingen tas tillbaka, så att texten ligger kvar i linje med talarens namn.
struct EditSurface: ViewModifier {
    let isEditing: Bool
    var focused = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(shape.fill(isEditing ? Color.accentColor.opacity(0.08) : Color.clear))
            .overlay(
                shape.strokeBorder(
                    focused ? Color.accentColor : (isEditing ? Color.secondary.opacity(0.45) : Color.clear),
                    lineWidth: focused ? 2 : 1
                )
            )
            .padding(.leading, -6)
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

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
            Button(action: onSeek) {
                Text(TimeFormatting.short(segment.start))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 52, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Spela upp från \(TimeFormatting.short(segment.start))")

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
                    SegmentEditor(segment: segment)
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

/// Textfält för att rätta ett segment. Ändringen sparas när fältet lämnas.
struct SegmentEditor: View {
    @Bindable var segment: TranscriptSegment

    @State private var draft = ""
    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    var body: some View {
        TextField("Text", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: ReadingTextSize.clamped(readingSize)))
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

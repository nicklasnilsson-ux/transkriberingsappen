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
                    Text(speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SpeakerPalette.color(for: speaker))
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
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        }
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

    var body: some View {
        TextField("Text", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
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

/// Ger varje talare en egen, stabil färg.
enum SpeakerPalette {
    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown, .indigo]

    static func color(for speaker: String) -> Color {
        let hash = speaker.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return colors[hash % colors.count]
    }
}

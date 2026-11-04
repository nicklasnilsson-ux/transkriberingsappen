import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

/// Förbinder fälten i de öppna styckena med titelbaren: Spara och Avbryt går dit, och de sparade
/// styckena (för Ångra) går tillbaka. Ett fält är öppet i taget, eller alla när Redigera i titelbaren
/// används. En vanlig klass, så att inget ritas om när fälten registrerar sig.
final class EditSession {
    /// Vad ett öppet fält kan göra.
    struct Handlers {
        /// Sparar det som står i fältet.
        let save: () -> Void
        /// Förkastar det som står i fältet, så att det inte sparas när fältet försvinner.
        let discard: () -> Void
    }

    private var fields: [PersistentIdentifier: Handlers] = [:]
    /// Fältet tar fokus när det öppnas. Av när alla stycken öppnas på en gång.
    var autofocus = true

    /// Fältet har sparat en ändring; det som fanns före ligger i `EditUndo`.
    var onSaved: (EditUndo) -> Void = { _ in }
    /// Fältet tappade fokus eller Retur trycktes; stycket med det här id:t är klart.
    var onFinish: (PersistentIdentifier?) -> Void = { _ in }
    /// Esc trycktes i fältet.
    var onCancel: () -> Void = {}

    func register(_ id: PersistentIdentifier?, _ handlers: Handlers) {
        if let id { fields[id] = handlers }
    }

    func unregister(_ id: PersistentIdentifier?) {
        if let id { fields[id] = nil }
    }

    func saveAll() { for handlers in fields.values { handlers.save() } }
    func discardAll() { for handlers in fields.values { handlers.discard() } }
}

/// En rad i transkriberingen: tidsstämpel, talare och text.
struct SegmentRow: View {
    @Bindable var segment: TranscriptSegment
    /// Texten och talaren som visas (anonymiserade eller original).
    let displayText: String
    let displaySpeaker: String?
    let query: String
    /// Vilken träff i den här raden man har stegat till med sökfältets pilar.
    var currentOccurrence: Int? = nil
    let isActive: Bool
    let currentTime: Double?
    let isEditing: Bool
    /// Texten som visas är anonymiserad; då rättas den visade texten och ändringen förs tillbaka till originalet.
    var isAnonymized = false
    var session: EditSession? = nil
    /// Knappen Redigera vid raden öppnar den för rättning.
    var onBeginEdit: () -> Void = {}
    /// Alla rader är öppna (Redigera i titelbaren); Spara och Avbryt finns då bara i titelbaren.
    var editsAll = false
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
    let onSeek: () -> Void

    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard
    @State private var hovering = false

    /// Samma bredd som i styckevisningen.
    private var textWidth: CGFloat { ReadingTextSize.columnWidth(for: readingSize) }

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
                    SegmentEditor(segment: segment, displayText: displayText, isAnonymized: isAnonymized, lineSpacing: 3, session: session)
                        .id(isAnonymized)
                        .frame(maxWidth: textWidth, alignment: .leading)
                        .modifier(EditSurface())
                } else {
                    // Ordtidsstämplarna hör till originaltexten.
                    let showsOriginal = displayText == segment.text
                    Text(SegmentText.attributed(
                        text: displayText,
                        query: query,
                        words: isActive && showsOriginal ? segment.words : [],
                        currentTime: isActive ? currentTime : nil,
                        currentOccurrence: currentOccurrence
                    ))
                    .font(.system(size: ReadingTextSize.clamped(readingSize)))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: textWidth, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .modifier(ActiveParagraphStyle(isActive: isActive))
        .overlay(alignment: .topTrailing) {
            RowEditActions(
                isEditing: isEditing, editsAll: editsAll, hovering: hovering,
                onBeginEdit: onBeginEdit, onSave: onSave, onCancel: onCancel
            )
            .padding(.top, 6).padding(.trailing, 8)
        }
        .onHover { hovering = $0 }
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
    var session: EditSession? = nil

    /// Förkastat med Esc eller Avbryt: inget får sparas när fältet försvinner.
    @State private var discarded = false
    /// Fylls redan när vyn skapas, så att fältet aldrig är tomt en bildruta (det ändrade höjden).
    @State private var draft: String
    /// Det fältet utgår från: originalet och hur det visades. Uppdateras efter varje sparning.
    @State private var baseOriginal: String
    @State private var baseShown: String
    @State private var mapping: AnonymizedEditing?
    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    init(segment: TranscriptSegment, displayText: String, isAnonymized: Bool, lineSpacing: CGFloat = 4, session: EditSession? = nil) {
        _segment = Bindable(wrappedValue: segment)
        self.displayText = displayText
        self.isAnonymized = isAnonymized
        self.lineSpacing = lineSpacing
        self.session = session
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
            commit: commit,
            finish: { session?.onFinish(segment.persistentModelID) },
            cancel: { session?.onCancel() },
            autofocus: session?.autofocus ?? true
        )
        .onAppear {
            session?.register(segment.persistentModelID, .init(save: commit, discard: { discarded = true }))
        }
        .onDisappear {
            commit()
            session?.unregister(segment.persistentModelID)
        }
    }

    private func commit() {
        guard isEditable, !discarded else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = baseShown
            return
        }
        guard trimmed != baseShown.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        let before = [Self.entry(segment)]
        defer {
            if let undo = EditUndo.changes(before: before, after: [Self.entry(segment)]) { session?.onSaved(undo) }
        }
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

    private static func entry(_ segment: TranscriptSegment) -> EditUndo.Entry {
        EditUndo.Entry(index: segment.index, text: segment.text, wordsData: segment.wordsData)
    }
}

/// Ett helt stycke i ett enda textfält, med samma löpande text som i visningsläget, så att
/// radbrytningen och höjden blir desamma. Ändringen förs tillbaka till rätt segment när fältet
/// lämnas (se `ParagraphEditing`), och med anonymisering på till originalet (`AnonymizedEditing`).
struct ParagraphEditor: View {
    let rows: [DisplaySegment]
    var lineSpacing: CGFloat = 4
    var session: EditSession? = nil

    /// Förkastat med Esc eller Avbryt: inget får sparas när fältet försvinner.
    @State private var discarded = false
    @State private var draft: String
    /// Hur segmenten visades och vad som var sparat när fältet senast sparades.
    @State private var baseShown: [String]

    init(rows: [DisplaySegment], lineSpacing: CGFloat = 4, session: EditSession? = nil) {
        self.rows = rows
        self.lineSpacing = lineSpacing
        self.session = session
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
            commit: commit,
            finish: { session?.onFinish(rows.first?.segment.persistentModelID) },
            cancel: { session?.onCancel() },
            autofocus: session?.autofocus ?? true
        )
        .onAppear {
            session?.register(rows.first?.segment.persistentModelID, .init(save: commit, discard: { discarded = true }))
        }
        .onDisappear {
            commit()
            session?.unregister(rows.first?.segment.persistentModelID)
        }
    }

    private func entries() -> [EditUndo.Entry] {
        rows.map { EditUndo.Entry(index: $0.segment.index, text: $0.segment.text, wordsData: $0.segment.wordsData) }
    }

    private func commit() {
        guard isEditable, !discarded else { return }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            draft = ParagraphEditing.join(baseShown)
            return
        }
        let newShown = ParagraphEditing.split(baseShown, edited: draft)
        guard newShown != baseShown else { return }
        let before = entries()
        defer {
            if let undo = EditUndo.changes(before: before, after: entries()) { session?.onSaved(undo) }
        }
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
///
/// SwiftUI:s `TextField` bryr sig inte om `.lineSpacing`, så fältet blev lägre än texten i
/// visningen och allt hoppade (mätt av `EditModeHeightTests`). Därför används macOS egen
/// textvy (`ReadingTextView`) med samma radavstånd.
struct EditableText: View {
    @Binding var text: String
    let isEditable: Bool
    let lineSpacing: CGFloat
    let commit: () -> Void
    /// Fältet är klart: det tappade fokus eller Retur trycktes.
    var finish: () -> Void = {}
    /// Esc trycktes: förkasta.
    var cancel: () -> Void = {}
    var autofocus = true

    @State private var isFocused = false
    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

    var body: some View {
        let size = ReadingTextSize.clamped(readingSize)
        Group {
            if isEditable {
                ReadingTextView(
                    text: $text,
                    fontSize: size,
                    lineSpacing: lineSpacing,
                    isFocused: $isFocused,
                    commit: commit,
                    finish: finish,
                    cancel: cancel,
                    autofocus: autofocus
                )
            } else {
                Text(text)
                    .font(.system(size: size))
                    .lineSpacing(lineSpacing)
                    .help("Det här stycket kan inte rättas med anonymiseringen på. Slå av anonymiseringen för att rätta det.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

/// Redigerbar text i macOS egen textvy, med samma typsnitt, radhöjd och radavstånd som
/// SwiftUI:s `Text` i visningsläget. Höjden räknas som rader × radhöjd + radavstånd mellan
/// raderna, precis som `Text` gör. Retur sparar och stänger stycket; Esc förkastar det.
struct ReadingTextView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let lineSpacing: CGFloat
    @Binding var isFocused: Bool
    let commit: () -> Void
    var finish: () -> Void = {}
    var cancel: () -> Void = {}
    var autofocus = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        // TextKit 1, så att raderna går att räkna med layoutManager.
        let view = NSTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.setAccessibilityLabel("Text")
        apply(to: view)
        view.string = text
        // Fältet byts in när man klickar i stycket: markören ska stå i det direkt.
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard autofocus, let view, let window = view.window else { return }
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 0, length: 0))
            coordinator.parent.isFocused = true
        }
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text { view.string = text }
        apply(to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        return CGSize(width: width, height: Self.height(of: view, width: width, lineSpacing: lineSpacing))
    }

    private var font: NSFont { NSFont.systemFont(ofSize: fontSize) }

    private var attributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        // Samma radhöjd som Text, så att raderna hamnar på samma ställe.
        let lineHeight = Self.lineHeight(fontSize: fontSize)
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    }

    private func apply(to view: NSTextView) {
        view.font = font
        view.typingAttributes = attributes
        if let storage = view.textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    /// Rader × radhöjd + radavstånd mellan raderna (inte efter sista), som SwiftUI:s `Text`.
    static func height(of view: NSTextView, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        guard let layout = view.layoutManager, let container = view.textContainer else { return 0 }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        var lines = 0
        let glyphs = layout.glyphRange(for: container)
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
        if layout.extraLineFragmentTextContainer != nil { lines += 1 }
        lines = max(lines, 1)
        let rowHeight = Self.lineHeight(fontSize: Double(view.font?.pointSize ?? NSFont.systemFontSize))
        return CGFloat(lines) * rowHeight + CGFloat(lines - 1) * lineSpacing
    }

    private static var lineHeights: [Double: CGFloat] = [:]

    /// Höjden på en rad hos SwiftUI:s `Text` i den här storleken, mätt en gång per storlek.
    /// Den skiljer sig någon bråkdel från textvyns egen radhöjd, och det blev flera punkter
    /// i ett långt stycke (mätt av `EditModeHeightTests`).
    static func lineHeight(fontSize: Double) -> CGFloat {
        if let cached = lineHeights[fontSize] { return cached }
        let host = NSHostingView(rootView: Text("Åg").font(.system(size: fontSize)).fixedSize())
        let height = host.fittingSize.height
        lineHeights[fontSize] = height
        return height
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReadingTextView

        init(_ parent: ReadingTextView) { self.parent = parent }

        func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
            parent.commit()
            parent.finish()
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // Retur sparar och stänger stycket.
                parent.commit()
                parent.finish()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc förkastar det som skrivits i stycket.
                parent.cancel()
                return true
            default:
                return false
            }
        }
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
                shape.strokeBorder(Color.line, lineWidth: 1)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -3)
            }
    }
}

/// Knapparna vid ett stycke eller en rad: Redigera när musen står över det, och Avbryt och Spara medan det
/// rättas (de ersätter Redigera). När alla är öppna finns Spara och Avbryt bara i titelbaren.
struct RowEditActions: View {
    let isEditing: Bool
    let editsAll: Bool
    let hovering: Bool
    let onBeginEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if isEditing && !editsAll {
            HStack(spacing: 6) {
                Button("Avbryt", action: onCancel)
                    .buttonStyle(.bordered)
                    .help("Förkasta rättningen av stycket (Esc)")
                Button("Spara", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .help("Spara rättningen (⌘Retur)")
            }
            .controlSize(.small)
        } else {
            EditHoverButton(visible: hovering && !isEditing, action: onBeginEdit)
        }
    }
}

/// "Redigera" som visas när musen står över ett stycke eller en rad. Ett klick öppnar det för rättning.
/// Ett klick direkt i texten gör det inte, så att man kan markera och kopiera text som vanligt.
/// Knappen tar alltid plats (osynlig när musen är borta), så att ingenting flyttar sig.
struct EditHoverButton: View {
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Redigera")
        }
        // Samma stil och storlek som Avbryt och Spara, så att knapparna hör ihop (Nicklas 2026-11-04).
        .buttonStyle(.bordered)
        .controlSize(.small)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .help("Rätta det här stycket")
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
                .foregroundStyle(Color.textPrimary)
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
        Icon(.warning, size: 12)
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
                Icon(.play, size: 10)
                    .opacity(hovering ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(emphasized ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.textSecondary))
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

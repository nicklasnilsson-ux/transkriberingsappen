import AppKit
import Observation
import SwiftData
import SwiftUI
import TranskriberaCore
import UniformTypeIdentifiers

struct TranscriptDetailView: View {
    @Bindable var transcript: Transcript
    @Environment(TranscriptionQueue.self) private var queue
    @Environment(AppState.self) private var appState

    @State private var player: PlayerController?
    @State private var query = ""
    /// Träffen man har stegat till i sökfältet (som ⌘F i en webbläsare).
    @State private var hitIndex = 0
    /// Ökar varje gång texten ska skrollas till aktuell träff, även när det är samma träff igen.
    @State private var searchJump = 0
    /// Stycket (eller raden) som rättas just nu. Ett i taget; `nil` när inget rättas.
    @State private var editingID: PersistentIdentifier?
    /// Redigera i titelbaren: alla stycken är öppna på en gång.
    @State private var editsAll = false
    /// Den senaste sparade rättningen, så att den går att ångra tills ett nytt stycke öppnas.
    @State private var lastEdit: EditUndo?
    /// Menyn vid ett prickat understruket ord (experimentet Korskolla).
    @State private var crossCheckMenu = CrossCheckMenu()
    /// Det senaste bytet av talare på ett stycke eller en rad, så att det går att ångra.
    @State private var lastMove: SpeakerMove.Undo?
    /// Stycket eller raden som ska flyttas till en ny talare (frågan om namnet är öppen).
    @State private var newSpeakerTarget: NewSpeakerTarget?
    @State private var newSpeakerDraft = ""
    /// Kopplar fältet i det öppna stycket till titelbaren (Spara, Avbryt) och tillbaka.
    @State private var editSession = EditSession()
    /// Håller stycket du läser kvar på skärmen när redigeringsläget växlar.
    @State private var scrollAnchor = ScrollAnchor()
    @State private var followPlayback = true
    /// Segmentet som spelas. Byts bara när uppspelningen når nästa segment, inte vid varje tick.
    @State private var playbackFocus = PlaybackFocus()
    @State private var speakerToRename: String?
    @State private var newSpeakerName = ""
    @State private var copied = false
    @State private var copiedFailure = false
    /// "Inte nu" på frågan om vem som är intervjuaren, för den här visningen.
    @State private var rolesDismissed = false
    /// Det senaste rollvalet, så att det går att ångra tills man gör något annat.
    @State private var roleChoice: RoleChoice?
    @AppStorage(SettingsKey.exportTimestamps) private var exportTimestamps = true
    @AppStorage(SettingsKey.transcriptLayout) private var layout: TranscriptLayout = .paragraphs
    @AppStorage(SettingsKey.anonymize) private var anonymize = true
    @AppStorage(SettingsKey.anonymizeNames) private var anonymizeNames = true
    @AppStorage(SettingsKey.anonymizeIdentifiers) private var anonymizeIdentifiers = true
    @AppStorage(SettingsKey.anonymizeSensitive) private var anonymizeSensitive = true
    @AppStorage(SettingsKey.anonymizeOrganizations) private var anonymizeOrganizations = false
    @AppStorage(SettingsKey.anonymizeUncertainNames) private var anonymizeUncertainNames = false
    @AppStorage(SettingsKey.anonymizeAlwaysHide) private var alwaysHide = ""
    @AppStorage(SettingsKey.anonymizeNeverHide) private var neverHide = ""
    @State private var anonymized: AnonymizedState?

    @FocusState private var searchFocused: Bool
    @State private var confirmRetranscribe = false
    @AppStorage(SettingsKey.askBeforeRetranscribe) private var askBeforeRetranscribe = true
    @State private var overrides = TranscriptionOverrides()
    @State private var showRerunSettings = false
    /// Valen i rutan ska leva kvar när Transkribera igen väntar på bekräftelse.
    @State private var keepOverridesOnClose = false
    @AppStorage(MiniPlayerSize.storageKey) private var miniSizeRaw = MiniPlayerSize.small.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "detailTop"

    var body: some View {
        VStack(spacing: 0) {
            // Spelaren ligger fast under titelbaren; resten skrollar med texten.
            playerBar
            ScrollViewReader { proxy in
                mainScroll(proxy: proxy)
            }
        }
        .toolbar { detailToolbar }
        .background { searchShortcut }
        // Titeln står i titelbaren och byts namn på där (macOS 14 kan inte dölja fönstertiteln).
        .navigationTitle($transcript.title)
        .modifier(DetailLifecycle(
            transcript: transcript,
            player: $player,
            anonymizationKey: anonymizationInput(transcript.sortedSegments),
            refresh: refreshAnonymization
        ))
        .modifier(DetailDialogs(
            confirmRetranscribe: $confirmRetranscribe,
            speakerToRename: $speakerToRename,
            newSpeakerName: $newSpeakerName,
            newSpeakerTarget: $newSpeakerTarget,
            newSpeakerDraft: $newSpeakerDraft,
            transcript: transcript,
            onMoveToNewSpeaker: { target, name in move(target.indices, to: name) },
            onRetranscribe: { retranscribe() }
        ))
    }

    private func mainScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Color.clear.frame(height: 1).id(Self.topID)
                headerRow
                olderVersionStrip
                if hasText {
                    toolsRow
                    Divider()
                }
                noticeCard
                textArea(proxy: proxy)
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            // Ett klick utanför det öppna stycket sparar det. Klick i texten når aldrig hit.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { if isEditing { saveEditing() } })
            // Skrollvyn läses av, så att stycket du läser kan stå kvar när läget växlar.
            .background(ScrollOffsetObserver(onChange: { _ in }, anchor: scrollAnchor))
        }
        // Stycket vid fönstrets överkant står kvar på samma plats när läget växlar.
        .onChange(of: isEditing) { _, _ in
            if let anchor = scrollAnchor.currentAnchor() { scrollAnchor.restore(anchor) }
        }
        // Esc förkastar rättningen av stycket. Spara och klick utanför sparar.
        .onExitCommand { if isEditing { cancelEditing() } }
        .onAppear { connectEditSession() }
        // Sökfältet stegar till en träff: den hamnar mitt i fönstret.
        .onChange(of: searchJump) { _, _ in scrollToCurrentHit(proxy: proxy) }
        .background {
            if isEditing {
                Button("Avbryt") { cancelEditing() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
        }
    }

    // MARK: - Kort

    private var hasText: Bool { !transcript.segments.isEmpty }
    private var isEditing: Bool { editsAll || editingID != nil }
    private var isWorking: Bool { transcript.status == .queued || transcript.status == .transcribing }

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(Color.surface))
            .overlay(cardShape.strokeBorder(Color.line, lineWidth: 1))
    }

    /// Överst i texten: version och modell/språk/talare (där Transkribera igen finns), och metadatan till höger.
    /// Får de inte plats på en rad hamnar metadatan under.
    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                versionPicker
                settingsPill
                Spacer(minLength: 12)
                metaLine.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    versionPicker
                    settingsPill
                    Spacer(minLength: 0)
                }
                metaLine
            }
        }
    }

    /// Verktygen för hela texten. Finns också i ⋯-menyn i titelbaren, så att de går att nå
    /// när raden har skrollats bort.
    private var toolsRow: some View {
        HStack(spacing: 8) {
            layoutPicker
            speakersMenu
            anonymizeToggle
            Spacer(minLength: 8)
            copyButton
            exportMenu()
        }
    }

    private var fileBaseline: FileBaseline {
        FileBaseline(modelName: transcript.modelName, language: transcript.language, hasSpeakers: !transcript.speakers.isEmpty)
    }

    /// Blå knapp först när något val skiljer sig från det filen transkriberades med.
    private var rerunSettingsChanged: Bool {
        RerunChange.isChanged(
            modelOnFile: transcript.modelName,
            chosenModel: overrides.modelRaw.map { WhisperModel.resolved($0).displayName },
            languageOnFile: transcript.language,
            chosenLanguage: overrides.language,
            identifiedSpeakersOnFile: !transcript.speakers.isEmpty,
            chosenIdentify: overrides.identifySpeakers,
            speakerCountOnFile: transcript.speakers.count,
            chosenExactSpeakers: overrides.speakerCount?.exact
        )
    }

    private var modelChipText: String {
        overrides.modelRaw.map { WhisperModel.resolved($0).displayName } ?? RerunChange.baseModelName(transcript.modelName)
    }

    private var languageChipText: String {
        if let language = overrides.language { return language == "auto" ? "Automatiskt språk" : Language.displayName(for: language) }
        return transcript.language.map { Language.displayName(for: $0) } ?? "Språk"
    }

    private var speakersChipText: String? {
        if overrides.identifySpeakers == false { return "Ingen talarseparering" }
        if let count = overrides.speakerCount { return count.label }
        if overrides.identifySpeakers == true { return "Talare: automatiskt" }
        guard !transcript.speakers.isEmpty else { return nil }
        let n = transcript.speakers.count
        return n == 1 ? "1 talare" : "\(n) talare"
    }

    /// En enda knapp med de tre valen ("KB Large ordagrann · Svenska · 3 talare") som öppnar
    /// popovern. Accentkant när något är ändrat.
    private var settingsPill: some View {
        Button { showRerunSettings = true } label: {
            HStack(spacing: 6) {
                Text(settingsSummary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Icon(.chevronDown, size: 10)
            }
            .font(.app(.small))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.chip, in: Capsule())
            .overlay(Capsule().strokeBorder(overrides.isEmpty ? Color.clear : Color.accentColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .help("Modell, språk och talare. Klicka för att välja andra till nästa omtagning.")
        .popover(isPresented: $showRerunSettings, arrowEdge: .bottom) {
            RerunSettingsPopover(
                overrides: $overrides,
                file: fileBaseline,
                isChanged: rerunSettingsChanged,
                isWorking: isWorking,
                onRerun: {
                    keepOverridesOnClose = true
                    requestRetranscribe()
                }
            )
            .presentationRoot()
        }
        // Ändrade val kastas om rutan stängs utan att transkribera igen.
        .onChange(of: showRerunSettings) { _, isOpen in
            guard !isOpen else { return }
            if !keepOverridesOnClose { overrides = TranscriptionOverrides() }
            keepOverridesOnClose = false
        }
    }

    private var settingsSummary: String {
        [modelChipText, languageChipText, speakersChipText].compactMap { $0 }.joined(separator: " · ")
    }

    private var statusStyle: AnyShapeStyle {
        switch transcript.status {
        case .completed: AnyShapeStyle(Color.success)
        case .failed: AnyShapeStyle(Color.warning)
        default: AnyShapeStyle(Color.textSecondary)
        }
    }

    private var statusText: String {
        switch transcript.status {
        case .completed: "Klar"
        case .transcribing: "Transkriberar"
        case .queued: "I kö"
        case .failed: "Misslyckades"
        }
    }

    /// Status · datum · längd.
    private var metaLine: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if transcript.status == .completed {
                    Image(icon: .checkCircle).accessibilityHidden(true)
                }
                Text(statusText)
            }
            .foregroundStyle(statusStyle)
            Text("·")
            Text(transcript.liveVersionDate.formatted(date: .long, time: .shortened))
            Text("·")
            Text(TimeFormatting.duration(transcript.duration)).monospacedDigit()
        }
        .font(.app(.small))
        .foregroundStyle(Color.textSecondary)
        .lineLimit(1)
    }

    private var layoutPicker: some View {
        Picker("Visning", selection: $layout) {
            ForEach(TranscriptLayout.allCases) { layout in
                Text(layout.displayName).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Stycken: löpande text per talare med en tidskod per stycke. Rader: varje segment med egen tidskod.")
    }

    // MARK: - Versioner

    /// Versionsvalet, t.ex. "Version 2 av 4". Datumet och klockslaget bredvid är den visade versionens. Finns först när det finns fler än en
    /// version. Indigo bakgrund när en äldre version visas.
    @ViewBuilder
    private var versionPicker: some View {
        if let label = transcript.versionShortLabel {
            let older = transcript.isViewingOlderVersion
            // AppMenu: förklaringen om hur många versioner som sparas ritas av appen med tillräcklig
            // kontrast (macOS ritade den ljusgrå, Nicklas 2026-11-07).
            AppMenuButton(entries: { versionMenuEntries() }) {
                Text(label)
                    .monospacedDigit()
                    .fontWeight(older ? .semibold : .regular)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(older ? 0.15 : 0), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
            }
            .fixedSize()
            .disabled(isWorking)
            .help("Byt mellan sparade versioner av texten. Varje version har egna rättningar och talarnamn.")
        }
    }

    private func versionMenuEntries() -> [AppMenuEntry] {
        var entries: [AppMenuEntry] = transcript.versionInfos.reversed().map { info -> AppMenuEntry in
            .choice(versionMenuTitle(info), checked: info.id == transcript.id) { switchVersion(to: info.id) }
        }
        entries.append(.separator)
        entries.append(.note("De \(VersionHistory.capacity) senaste versionerna sparas. Äldre raderas."))
        return entries
    }

    private func versionMenuTitle(_ info: VersionInfo) -> String {
        let when = info.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        var title = "Version \(info.number) · \(when)"
        if !info.modelName.isEmpty { title += " · \(RerunChange.baseModelName(info.modelName))" }
        if info.number == transcript.versionCount { title += " (senaste)" }
        return title
    }

    private func switchVersion(to id: UUID) {
        guard id != transcript.id,
              let version = transcript.versions.first(where: { $0.id == id }),
              let context = transcript.modelContext else { return }
        saveEditing()
        transcript.switchTo(version, in: context)
        try? context.save()
    }

    private func showLatestVersion() {
        guard let latest = transcript.versions.max(by: { $0.date < $1.date }) else { return }
        switchVersion(to: latest.id)
    }

    /// Remsan under titelkortet när en äldre version visas. Rättningar sparas i den versionen.
    @ViewBuilder
    private var olderVersionStrip: some View {
        if transcript.isViewingOlderVersion, let label = transcript.versionLabel {
            HStack(spacing: 8) {
                Image(icon: .history)
                Text("Du tittar på en äldre version (\(label)). Rättningar sparas i den här versionen.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Visa senaste versionen") { showLatestVersion() }
                    .buttonStyle(.link)
                    .disabled(isWorking)
            }
            .font(.app(.regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Säger vilken text som rättas, eller att rättningen är sparad och går att ångra.
    /// Ligger före knapparna, så att ingenting flyttar sig när den visas.
    @ViewBuilder
    private var editStateLabel: some View {
        if isEditing {
            Text(anonymizationOptions != nil ? "Redigerar anonymiserad text" : "Redigerar originaltexten")
                .font(.app(.small, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .truncationMode(.tail)
                // Titeln får hellre kortas än den här texten.
                .layoutPriority(1)
        } else if lastEdit != nil {
            HStack(spacing: 6) {
                Label("Sparat", systemIcon: .saved)
                    .labelStyle(.titleAndIcon)
                    .font(.app(.small, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .lineLimit(1)
                Button("Ångra") { undoLastEdit() }
                    .help("Ge tillbaka stycket som det var före rättningen")
            }
            .layoutPriority(1)
        } else if let move = lastMove, transcript.canUndo(move) {
            HStack(spacing: 6) {
                Label("Flyttat till \(move.speaker)", systemIcon: .saved)
                    .labelStyle(.titleAndIcon)
                    .font(.app(.small, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button("Ångra") { undoLastMove() }
                    .help("Ge tillbaka talaren som det var före bytet")
            }
            .layoutPriority(1)
        }
    }

    private func openSearch() {
        searchFocused = true
    }

    private func closeSearch() {
        query = ""
        searchFocused = false
    }

    /// Sökfältet i titelbaren. Det är alltid synligt och krymper när fönstret är smalt.
    private var toolbarSearch: some View {
        HStack(spacing: 6) {
            Image(systemIcon: .search).foregroundStyle(Color.textSecondary)
            TextField("Sök i texten", text: $query, prompt: Text("Sök i texten"))
                .readablePrompt("Sök i texten")
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // Retur: nästa träff. Esc: stäng.
                .onSubmit { stepHit(forward: true) }
                .onExitCommand { closeSearch() }
                .onChange(of: query) { _, _ in
                    hitIndex = 0
                    searchJump += 1
                }
            if showSearch {
                let count = searchHits.count
                Text(TextSearch.positionLabel(index: hitIndex, count: count))
                    .font(.app(.small).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize()
                HStack(spacing: 2) {
                    Button { stepHit(forward: false) } label: {
                        Image(systemIcon: .previousHit).frame(width: 18, height: 16)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .help("Förra träffen (⇧⌘G)")
                    .accessibilityLabel("Förra träffen")
                    Button { stepHit(forward: true) } label: {
                        Image(systemIcon: .nextHit).frame(width: 18, height: 16)
                    }
                    .keyboardShortcut("g", modifiers: .command)
                    .help("Nästa träff (Retur eller ⌘G)")
                    .accessibilityLabel("Nästa träff")
                }
                .buttonStyle(.plain)
                .disabled(count == 0)
                Button("Stäng") { closeSearch() }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 140, idealWidth: 240, maxWidth: 360)
        .background(Color.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Sökfältet är aktivt när det står något i det.
    private var showSearch: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// ⌘F flyttar skrivmarkören till sökfältet i titelbaren.
    private var searchShortcut: some View {
        Button("Sök i texten") { openSearch() }
            .keyboardShortcut("f")
            .hidden()
            .disabled(!hasText)
    }

    /// Titelbaren: sök, Redigera och ⋯-menyn. Redigera ligger alltid kvar här.
    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            olderVersionBadge
            if hasText { toolbarSearch }
            editStateLabel
            editToggle
            moreMenu
        }
    }

    /// Märke i titelbaren när en äldre version visas, så att det syns även när raden överst har skrollat bort.
    @ViewBuilder
    private var olderVersionBadge: some View {
        if transcript.isViewingOlderVersion, let label = transcript.versionShortLabel {
            Label(label, systemIcon: .olderVersion)
                .labelStyle(.titleAndIcon)
                .font(.app(.small, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .fixedSize()
                .help("Du tittar på en äldre version. Rättningar sparas i den här versionen.")
        }
    }

    /// Samma åtgärder som verktygsraden, så att de går att nå även när den har skrollats bort.
    private var moreMenu: some View {
        Menu {
            if hasText {
                // Undermeny i stället för en inline-väljare: macOS ritar väljarens rubrik ljusgrå.
                Menu("Visning") {
                    ForEach(TranscriptLayout.allCases) { option in
                        Toggle(option.displayName, isOn: Binding(
                            get: { layout == option },
                            set: { if $0 { layout = option } }
                        ))
                    }
                }
                Toggle(isOn: $anonymize) {
                    Label("Anonymisera", systemIcon: anonymize ? .anonymize : .showNames)
                }
                if !transcript.speakers.isEmpty {
                    Menu("Talare") { speakersMenuContent }
                }
                Divider()
                Button("Kopiera text") { copyText() }
                Menu("Exportera") { exportMenuContent }
                Divider()
                Toggle("Följ uppspelning", isOn: $followPlayback)
            }
            Button("Transkribera igen") { requestRetranscribe() }
                .disabled(isWorking)
        } label: {
            Image(systemIcon: .more).accessibilityLabel("Fler val")
        }
        .menuIndicator(.hidden)
        .help("Fler val")
    }

    /// Alla träffar i den text som visas, i läsordning.
    private var searchHits: [SearchHit<PersistentIdentifier>] {
        guard showSearch else { return [] }
        let rows = displaySegments(transcript.sortedSegments) ?? []
        return TextSearch.hits(of: query, in: rows.map {
            (id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    private var currentHit: SearchHit<PersistentIdentifier>? {
        let hits = searchHits
        guard !hits.isEmpty else { return nil }
        return hits[min(hitIndex, hits.count - 1)]
    }

    private func stepHit(forward: Bool) {
        let count = searchHits.count
        guard count > 0 else { return }
        hitIndex = TextSearch.step(from: min(hitIndex, count - 1), count: count, forward: forward)
        searchJump += 1
    }

    /// Skrollar till stycket (eller raden) med aktuell träff. Hela texten visas hela tiden.
    private func scrollToCurrentHit(proxy: ScrollViewProxy) {
        guard let hit = currentHit else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            // Samma id som raderna har: styckets första segment, eller segmentet självt.
            if layout == .paragraphs, let rows = displaySegments(transcript.sortedSegments),
               let paragraph = Self.paragraphs(rows).first(where: { $0.contains { $0.id == hit.id } }) {
                proxy.scrollTo(paragraph.first?.id, anchor: .center)
            } else {
                proxy.scrollTo(hit.id, anchor: .center)
            }
        }
    }

    /// Redigera ⇄ Avbryt och Spara. Syns alltid i titelbaren. Redigera öppnar stycket som står
    /// överst i bild; man kan också klicka direkt i texten.
    @ViewBuilder
    private var editToggle: some View {
        if isEditing {
            Button("Avbryt") { cancelEditing() }
                .help("Förkasta rättningen (Esc)")
            Button("Spara") { saveEditing() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Spara rättningen (⌘Retur)")
        } else {
            Button {
                beginEditingAll()
            } label: {
                Label("Redigera", systemIcon: .edit)
                    .labelStyle(.titleAndIcon)
            }
            .help("Rätta hela texten direkt i transkriberingen. Du kan också hålla musen över ett stycke och välja Redigera för att rätta bara det")
            .disabled(!hasText)
        }
    }

    // MARK: - Rättning av ett stycke

    private func connectEditSession() {
        editSession.onSaved = { lastEdit = lastEdit?.merging($0) ?? $0 }
        // Bara det öppna stycket stänger sig självt. Ett som byts ut får inte stänga det nya.
        editSession.onFinish = { id in if editingID == id { editingID = nil } }
        editSession.onCancel = { cancelEditing() }
    }

    /// Öppnar ett stycke för rättning. Stycket som var öppet sparas först.
    private func beginEditing(_ id: PersistentIdentifier) {
        guard !editsAll, editingID != id else { return }
        editSession.saveAll()
        lastEdit = nil
        lastMove = nil
        editSession.autofocus = true
        editingID = id
    }

    /// Redigera i titelbaren: alla stycken blir öppna. Fälten tar inte fokus själva, man klickar där man vill skriva.
    private func beginEditingAll() {
        editSession.saveAll()
        lastEdit = nil
        lastMove = nil
        editSession.autofocus = false
        editingID = nil
        editsAll = true
    }

    /// Sparar det som är öppet och stänger det.
    private func saveEditing() {
        editSession.saveAll()
        editingID = nil
        editsAll = false
    }

    /// Förkastar det som skrivits. Hann fälten spara först (t.ex. när ett tappade fokus eller skrollade
    /// bort) läggs det tillbaka.
    private func cancelEditing() {
        guard isEditing else { return }
        editSession.discardAll()
        editingID = nil
        editsAll = false
        if lastEdit != nil { undoLastEdit() }
    }

    private func undoLastEdit() {
        guard let undo = lastEdit else { return }
        for entry in undo.entries {
            guard let segment = transcript.segments.first(where: { $0.index == entry.index }) else { continue }
            segment.text = entry.text
            segment.wordsData = entry.wordsData
        }
        lastEdit = nil
        try? transcript.modelContext?.save()
    }


    /// Anonymisera. Fylld med accentfärgen när anonymiseringen är på.
    private var anonymizeToggle: some View {
        Toggle(isOn: $anonymize) {
            Label("Anonymisera", icon: anonymize ? .visibilityOff : .visibility)
        }
        .toggleStyle(.button)
        .modifier(OnStateButtonStyle(isOn: anonymize))
        .help(anonymize
              ? "Namn och känsliga uppgifter är dolda. Klicka för att visa originalet."
              : "Dölj namn, personnummer och andra känsliga uppgifter")
    }

    @ViewBuilder
    private var speakersMenu: some View {
        if !transcript.speakers.isEmpty {
            Menu {
                speakersMenuContent
            } label: {
                Label("Talare", icon: .group)
            }
            .menuStyle(.button)
            .fixedSize()
            .help("Ge talarna riktiga namn")
        }
    }

    /// Innehållet i Talare-menyn, också som undermeny i ⋯-menyn.
    @ViewBuilder
    private var speakersMenuContent: some View {
        ForEach(transcript.speakers, id: \.self) { speaker in
            Button("Byt namn på \(speaker)…") { beginRename(speaker) }
        }
        Divider()
        // Utan rubrik (macOS ritar sektionsrubriker ljusgrå); varje rad säger själv vad den gäller.
        ForEach(transcript.speakers, id: \.self) { speaker in
            Toggle("\(speaker) är intervjuare", isOn: Binding(
                get: { SpeakerRoles.isInterviewer(speaker) },
                set: { transcript.setInterviewer(speaker, to: $0) }
            ))
        }
        Divider()
        Button("Visa talarturer i Finder (för felsökning)") {
            NSWorkspace.shared.open(AppPaths.speakerTurnsDirectory)
        }
    }

    private func copyText() {
        saveEditing()
        copyToPasteboard(TranscriptExporter.fullText(outputSegments))
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private var copyButton: some View {
        Button {
            copyText()
        } label: {
            Label(copied ? "Kopierat!" : "Kopiera text", icon: copied ? .check : .copy)
        }
        .help("Kopiera hela transkriberingen till urklipp")
        .disabled(!hasText)
    }

    /// Exportera är en neutral svart primärknapp (Pianissimo), ingen växel.
    private func exportMenu() -> some View {
        Menu {
            exportMenuContent
        } label: {
            HStack(spacing: 6) {
                Image(icon: .share)
                Text("Exportera")
                Icon(.chevronDown, size: 10)
            }
            .font(.app(.regular, weight: .medium))
            .foregroundStyle(Color.neutralButtonText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.neutralButton, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Spara som text, Markdown, undertexter eller JSON")
        .disabled(!hasText)
    }

    @ViewBuilder
    private var exportMenuContent: some View {
        ForEach(ExportFormat.allCases) { format in
            Button(format.displayName) { export(as: format) }
        }
        Divider()
        Button("Exportera för analys…") { appState.isAnalysisExportPresented = true }
            .help("En Markdown-fil per session, anpassad för analys i t.ex. Claude")
        Divider()
        Toggle("Ta med tidsstämplar (.txt och .md)", isOn: $exportTimestamps)
    }

    /// Spelaren, fast under titelbaren (se `PlayerBar`).
    @ViewBuilder
    private var playerBar: some View {
        if hasText, let player {
            PlayerBar(
                player: player,
                duration: transcript.duration,
                isVideo: transcript.isVideo,
                followPlayback: $followPlayback,
                miniSizeRaw: $miniSizeRaw,
                title: transcript.title
            )
            // Menyn Uppspelning (Spela/Pausa) styr spelaren i det fönster som är i fokus.
            .focusedSceneValue(\.player, player)
        }
    }

    private var showsRolesBanner: Bool {
        !rolesDismissed && hasText && SpeakerRoles.needsRoles(transcript.speakers)
    }

    private var showsAnonymizationBanner: Bool { anonymizationOptions != nil && hasText }

    /// Något gick inte som tänkt men texten blev klar, t.ex. att talarna inte kunde identifieras.
    private var completionNotice: String? {
        transcript.status == .completed && hasText ? transcript.errorMessage : nil
    }

    @ViewBuilder
    private var completionNoticeRow: some View {
        if let message = completionNotice {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(icon: .warning).foregroundStyle(Color.warning).accessibilityHidden(true)
                Text(message)
                Spacer(minLength: 8)
            }
            .font(.app(.regular))
        }
    }

    /// 5. Notiser samlade i en tonad ruta.
    @ViewBuilder
    private var noticeCard: some View {
        if showsRolesBanner || showsAnonymizationBanner || roleChoice != nil || completionNotice != nil {
            VStack(alignment: .leading, spacing: 8) {
                completionNoticeRow
                rolesBanner
                roleChoiceRow
                anonymizationBanner
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.notice, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Frågar först när något ska sparas eller raderas (se `RetranscribeDialog`).
    private func requestRetranscribe() {
        saveEditing()
        if !hasText {
            retranscribe(confirmed: false)
        } else if RetranscribeDialog.needsDialog(versionCount: transcript.versionCount, askSetting: askBeforeRetranscribe) {
            confirmRetranscribe = true
        } else {
            retranscribe()
        }
    }

    private func retranscribe(confirmed: Bool = true) {
        guard let confirmation = RetranscribeConfirmation(replacingText: hasText, confirmed: confirmed) else { return }
        queue.retranscribe(transcript, confirmation: confirmation, overrides: overrides.filled(with: fileBaseline))
        overrides = TranscriptionOverrides()
    }

    // MARK: - Text

    /// 6. Texten, eller förloppet, eller felet.
    @ViewBuilder
    private func textArea(proxy: ScrollViewProxy) -> some View {
        switch transcript.status {
        case .queued, .transcribing:
            card { TranscriptionProgressView(transcript: transcript) }
        case .failed where transcript.segments.isEmpty:
            card {
                ContentUnavailableView {
                    Label("Transkriberingen misslyckades", icon: .warning)
                } description: {
                    // Markerbar, så att felet går att kopiera även utan knappen.
                    Text(transcript.errorMessage ?? "Okänt fel.")
                        .textSelection(.enabled)
                } actions: {
                    HStack {
                        Button("Försök igen") { retranscribe(confirmed: false) }
                            .help("Transkribera filen igen med nuvarande inställningar")
                            .buttonStyle(.borderedProminent)
                        if let model = failedModelToRedownload {
                            Button("Ladda ned modellen igen") {
                                queue.transcriber.deleteDownloadedModel(model)
                                retranscribe(confirmed: false)
                            }
                            .help("Raderar \(model.displayName) från datorn, laddar ned den på nytt och försöker igen")
                            .disabled(queue.transcriber.isBusy)
                        }
                        Button(copiedFailure ? "Kopierat" : "Kopiera felinformation") { copyFailure() }
                            .help("Kopierar felet, appversionen och de senaste raderna i felloggen")
                    }
                }
            }
        default:
            textRows(proxy: proxy)
        }
    }

    /// Modellen som körningen använde, om felet kan bero på modellen (Core ML-fel).
    private var failedModelToRedownload: WhisperModel? {
        guard let message = transcript.errorMessage, FailureExplainer.isModelComputeFailure(message) else { return nil }
        let name = RerunChange.baseModelName(transcript.modelName)
        return WhisperModel.allCases.first { $0.displayName == name }
    }

    private func copyFailure() {
        let text = [
            "Transkribera \(ErrorLog.appVersion), \(FailureExplainer.gigabytes(ProcessInfo.processInfo.physicalMemory)) GB minne, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Modell: \(transcript.modelName)",
            transcript.errorMessage ?? "Okänt fel.",
            "Senaste raderna i felloggen:",
            ErrorLog.recentEntries()
        ].joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedFailure = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedFailure = false
        }
    }

    @ViewBuilder
    private func textRows(proxy: ScrollViewProxy) -> some View {
        let segments = transcript.sortedSegments
        if segments.isEmpty {
            ContentUnavailableView {
                Label("Ingen text hittades", icon: .warning)
            } description: {
                Text("Inspelningen innehöll inget tal som gick att skriva ut.")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else if let rows = displaySegments(segments) {
            // Uppspelningstiden (tio tick i sekunden) når aldrig listan. Den läses i en osynlig vy
            // som bara säger till när nästa segment börjar; listan byggs om då och inte vid varje
            // tick. Annars hackar skrollningen under uppspelning (0.9.25) eller fryser (0.9.7).
            let paragraphs = layout == .paragraphs ? Self.paragraphs(rows) : []
            let hit = currentHit
            PlaybackFocusReader(focus: playbackFocus) { activeID in
                switch layout {
                case .paragraphs:
                    paragraphRows(paragraphs: paragraphs, hit: hit, activeID: activeID, proxy: proxy)
                case .segments:
                    segmentRows(rows: rows, hit: hit, activeID: activeID, proxy: proxy)
                }
            }
            .background(PlaybackFocusTracker(player: player, segments: segments, focus: playbackFocus))
        } else if AnonymizationWait.isWaiting(segmentCount: segments.count, hasCurrentResult: false) {
            ProgressView("Anonymiserar…")
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func follow(_ id: some Hashable, proxy: ScrollViewProxy) {
        guard followPlayback, player?.isPlaying == true, !isEditing else { return }
        // Skrollar du själv följer texten inte med förrän du har släppt en stund; annars drar
        // appen tillbaka texten medan du skrollar.
        guard !scrollAnchor.userScrolledRecently() else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func segmentRows(rows: [DisplaySegment], hit: SearchHit<PersistentIdentifier>?, activeID: PersistentIdentifier?, proxy: ScrollViewProxy) -> some View {
        // Hela texten visas alltid; sökningen markerar och stegar mellan träffarna.
        // Talarna läses en gång här, inte per rad: varje läsning sorterar alla segment (0.9.33).
        let speakers = transcript.speakers
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    let segment = row.segment
                    SegmentRow(
                        segment: segment,
                        displayText: row.text,
                        displaySpeaker: row.speaker,
                        query: query,
                        currentOccurrence: hit?.id == row.id ? hit?.occurrence : nil,
                        isActive: segment.persistentModelID == activeID,
                        // Bara den spelade raden läser tiden (för ordet som spelas); övriga ritas inte om.
                        clock: segment.persistentModelID == activeID ? player : nil,
                        isEditing: editsAll || editingID == segment.persistentModelID,
                        isAnonymized: row.isAnonymized,
                        session: editSession,
                        onBeginEdit: { beginEditing(segment.persistentModelID) },
                        editsAll: editsAll,
                        onSave: { saveEditing() },
                        onCancel: { cancelEditing() },
                        onSeek: { player?.seek(to: segment.start) },
                        speakerMenu: { AnyView(speakerActions([row], noun: "raden", speakers: speakers)) },
                        menuSpeakers: speakers,
                        alternatives: row.alternatives
                    )
                    .equatable()
                    .id(segment.persistentModelID)
                    .background(RowFrameReporter(id: AnyHashable(segment.persistentModelID), anchor: scrollAnchor))
                    .contextMenu { segmentMenu(row, speakers: speakers) }
                    Divider()
                }
            }
        }
        .environment(\.openURL, OpenURLAction { openCrossCheck($0) })
        .onChange(of: activeID) { _, newValue in
            if let newValue { follow(newValue, proxy: proxy) }
        }
    }

    private func paragraphRows(paragraphs: [[DisplaySegment]], hit: SearchHit<PersistentIdentifier>?, activeID: PersistentIdentifier?, proxy: ScrollViewProxy) -> some View {
        // Hela texten visas alltid; sökningen markerar och stegar mellan träffarna.
        let activeParagraphID = paragraphs.first { paragraph in paragraph.contains { $0.id == activeID } }?.first?.id
        // Talarna läses en gång här, inte per stycke: varje läsning sorterar alla segment (0.9.33).
        let speakers = transcript.speakers

        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(paragraphs, id: \.first?.id) { paragraph in
                    // Bara det spelade stycket får spelaren och det aktiva id:t (se ParagraphRow ==).
                    let isActiveParagraph = activeParagraphID != nil && paragraph.first?.id == activeParagraphID
                    ParagraphRow(
                        rows: paragraph,
                        query: query,
                        currentHit: hit,
                        activeID: isActiveParagraph ? activeID : nil,
                        clock: isActiveParagraph ? player : nil,
                        isEditing: editsAll || editingID == paragraph.first?.segment.persistentModelID,
                        session: editSession,
                        onBeginEdit: {
                            if let id = paragraph.first?.segment.persistentModelID { beginEditing(id) }
                        },
                        editsAll: editsAll,
                        onSave: { saveEditing() },
                        onCancel: { cancelEditing() },
                        onSeek: { player?.seek(to: $0) },
                        speakerMenu: { _ in AnyView(speakerActions(paragraph, noun: "stycket", speakers: speakers)) },
                        menuSpeakers: speakers
                    )
                    .equatable()
                    .id(paragraph.first?.id)
                    .background(RowFrameReporter(id: AnyHashable(paragraph.first?.id), anchor: scrollAnchor))
                    .contextMenu { paragraphMenu(paragraph, speakers: speakers) }
                    Divider()
                }
            }
        }
        .environment(\.openURL, OpenURLAction { openCrossCheck($0) })
        .onChange(of: activeParagraphID) { _, newValue in
            if let newValue { follow(newValue, proxy: proxy) }
        }
    }

    /// Klick på ett prickat understruket ord (experimentet Korskolla): menyn med de två
    /// tolkningarna och Lyssna. Andra länkar öppnas som vanligt.
    private func openCrossCheck(_ url: URL) -> OpenURLAction.Result {
        guard let target = CrossCheck.parse(url) else { return .systemAction }
        let (segmentIndex, wordIndex) = (target.segment, target.word)
        guard !isEditing, let segment = transcript.segments.first(where: { $0.index == segmentIndex }) else { return .handled }
        let words = segment.words
        guard words.indices.contains(wordIndex), let alternative = words[wordIndex].alternative else { return .handled }
        let length = max(1, min(words[wordIndex].alternativeLength ?? 1, words.count - wordIndex))
        let current = TextCleaning.clean(words[wordIndex..<wordIndex + length].map(\.word).joined())
        var onListen: (() -> Void)?
        if let listening = CrossCheck.listeningRange(at: wordIndex, in: words), let player {
            onListen = { player.play(from: listening.lowerBound, to: listening.upperBound) }
        }
        crossCheckMenu.show(
            current: current,
            alternative: alternative,
            onKeep: {
                segment.keepWord(at: wordIndex)
                try? transcript.modelContext?.save()
            },
            onChoose: {
                segment.chooseAlternative(at: wordIndex)
                try? transcript.modelContext?.save()
            },
            onListen: onListen
        )
        return .handled
    }

    /// Delar upp raderna i stycken på samma sätt som "Exportera för analys".
    private static func paragraphs(_ rows: [DisplaySegment]) -> [[DisplaySegment]] {
        let data = rows.map { SegmentData(start: $0.segment.start, end: $0.segment.end, text: $0.text, speaker: $0.speaker) }
        return AnalysisExporter.paragraphRanges(data).map { Array(rows[$0]) }
    }

    @ViewBuilder
    private func paragraphMenu(_ paragraph: [DisplaySegment], speakers: [String]) -> some View {
        if let first = paragraph.first {
            let text = paragraph.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            Button("Spela upp stycket") { player?.seek(to: first.segment.start) }
            Button("Redigera stycket") { beginEditing(first.segment.persistentModelID) }
            Button("Kopiera stycket") { copyToPasteboard(text) }
            Button("Kopiera med tidsstämpel") {
                var line = "[\(TimeFormatting.short(first.segment.start))] "
                if let speaker = first.speaker { line += "\(speaker): " }
                copyToPasteboard(line + text)
            }
            if first.segment.speaker != nil {
                Divider()
                speakerActions(paragraph, noun: "stycket", speakers: speakers)
            }
        }
    }

    @ViewBuilder
    private func segmentMenu(_ row: DisplaySegment, speakers: [String]) -> some View {
        let segment = row.segment
        Button("Spela upp härifrån") { player?.seek(to: segment.start) }
        Button("Redigera raden") { beginEditing(segment.persistentModelID) }
        Button("Kopiera stycket") { copyToPasteboard(row.text) }
        Button("Kopiera med tidsstämpel") {
            copyToPasteboard("[\(TimeFormatting.short(segment.start))] \(row.text)")
        }
        if segment.speaker != nil {
            Divider()
            speakerActions([row], noun: "raden", speakers: speakers)
        }
    }

    // MARK: - Byta talare på ett stycke eller en rad

    /// ▾-menyn vid talarens namn och samma val i högerklicksmenyn: flytta bara det här stycket
    /// (eller raden) till en annan talare, byta namn på talaren överallt och ange intervjuare.
    @ViewBuilder
    private func speakerActions(_ rows: [DisplaySegment], noun: String, speakers: [String]) -> some View {
        let indices = rows.map(\.segment.index)
        let current = rows.first?.segment.speaker
        Menu("Flytta \(noun) till") {
            ForEach(SpeakerMove.targets(speakers: speakers, current: current), id: \.self) { speaker in
                Button(speaker) { move(indices, to: speaker) }
            }
            Divider()
            Button("Ny talare…") { beginNewSpeaker(indices, noun: noun) }
        }
        if let current {
            Divider()
            Button("Byt namn på \(current) (överallt)…") { beginRename(current) }
            interviewerButton(current)
        }
    }

    /// Flyttar segmenten till `speaker`. Stycken från samma talare slås ihop av sig själva.
    private func move(_ indices: [Int], to speaker: String) {
        if isEditing { saveEditing() }
        guard let undo = transcript.moveSegments(Set(indices), to: speaker) else { return }
        lastEdit = nil
        roleChoice = nil
        lastMove = undo
        try? transcript.modelContext?.save()
    }

    private func undoLastMove() {
        guard let move = lastMove else { return }
        transcript.undo(move)
        lastMove = nil
        try? transcript.modelContext?.save()
    }

    private func beginNewSpeaker(_ indices: [Int], noun: String) {
        newSpeakerDraft = SpeakerMove.suggestedNewName(existing: transcript.speakers)
        newSpeakerTarget = NewSpeakerTarget(indices: indices, noun: noun)
    }

    // MARK: - Roller

    /// Frågar vem som är intervjuaren när talarna bara heter "Talare 1", "Talare 2" …
    @ViewBuilder
    private var rolesBanner: some View {
        let speakers = transcript.speakers
        if !rolesDismissed, !isEditing, SpeakerRoles.needsRoles(speakers) {
            // Frågan och "Inte nu" på en rad; talarna under, i en flödeslayout som lägger chipen
            // på nya rader när det är många talare. Frågetexten och namnen trycks aldrig ihop.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(icon: .personQuestion)
                    Text("Vem är intervjuare?")
                        .fixedSize()
                    Spacer(minLength: 8)
                    Button("Inte nu") { rolesDismissed = true }
                        .buttonStyle(.link)
                }
                FlowLayout(spacing: 12, lineSpacing: 6) {
                    ForEach(speakers, id: \.self) { speaker in
                        HStack(spacing: 2) {
                            Circle().fill(SpeakerPalette.color(for: speaker)).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Button(speaker) { chooseInterviewer(speaker) }
                                .fixedSize()
                                .help("\(speaker) blir Intervjuare. Övriga talare behåller sina namn (Talare 1, Talare 2 …). Fler intervjuare kan du lägga till efteråt.")
                            Button {
                                if let first = transcript.sortedSegments.first(where: { $0.speaker == speaker }) {
                                    player?.seek(to: first.start)
                                }
                            } label: {
                                Image(icon: .playCircle)
                            }
                            .buttonStyle(.borderless)
                            .help("Lyssna på \(speaker)")
                        }
                    }
                }
            }
            .font(.app(.regular))
        }
    }

    /// Gör `speaker` till intervjuare. Förra läget sparas så att valet går att ångra.
    private func chooseInterviewer(_ speaker: String) {
        let before = transcript.speakerSnapshot
        transcript.setInterviewer(speaker)
        roleChoice = RoleChoice(speakers: [speaker], before: before)
    }

    /// Lägger till en intervjuare till efter valet ("Intervjuare 1", "Intervjuare 2" …).
    /// Ångra återställer fortfarande läget före det första valet.
    private func addInterviewer(_ speaker: String) {
        guard var choice = roleChoice else { return }
        transcript.setInterviewer(speaker, to: true)
        choice.speakers.append(speaker)
        roleChoice = choice
    }

    /// "Klart. Talare 1 är intervjuare." med Ångra, tills man gör något annat. Under den kan man
    /// lägga till fler intervjuare, eftersom en intervju ibland har flera (Nicklas 2026-11-10).
    @ViewBuilder
    private var roleChoiceRow: some View {
        if let choice = roleChoice {
            let others = transcript.speakers.filter { SpeakerRoles.speakerNumber($0) != nil }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(icon: .checkCircle).foregroundStyle(Color.success).accessibilityHidden(true)
                    Text("Klart. \(choice.speakers.formatted(.list(type: .and, width: .standard))) är intervjuare.")
                    Spacer(minLength: 8)
                    Button("Ångra") {
                        transcript.restoreSpeakers(choice.before)
                        roleChoice = nil
                    }
                    .buttonStyle(.link)
                }
                if !others.isEmpty {
                    FlowLayout(spacing: 12, lineSpacing: 6) {
                        Text("Fler intervjuare?")
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize()
                        ForEach(others, id: \.self) { speaker in
                            HStack(spacing: 2) {
                                Circle().fill(SpeakerPalette.color(for: speaker)).frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Button(speaker) { addInterviewer(speaker) }
                                    .fixedSize()
                                    .help("\(speaker) blir också intervjuare. Intervjuarna heter då Intervjuare 1, Intervjuare 2 …")
                            }
                        }
                    }
                }
            }
            .font(.app(.regular))
        }
    }

    @ViewBuilder
    private func interviewerButton(_ speaker: String) -> some View {
        if SpeakerRoles.isInterviewer(speaker) {
            Button("\(speaker) är inte intervjuare") { transcript.setInterviewer(speaker, to: false) }
        } else {
            Button("\(speaker) är intervjuare") { transcript.setInterviewer(speaker, to: true) }
        }
    }

    // MARK: - Anonymisering

    @ViewBuilder
    private var anonymizationBanner: some View {
        if anonymizationOptions != nil, !transcript.segments.isEmpty {
            HStack(spacing: 6) {
                Image(icon: .visibilityOff)
                if let result = currentAnonymization(for: transcript.sortedSegments) {
                    Text(result.replacementCount == 1
                         ? "Anonymiserad: 1 uppgift är dold."
                         : "Anonymiserad: \(result.replacementCount) uppgifter är dolda.")
                    Text("Originaltexten finns kvar.")
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Text("Anonymiserar…")
                }
                Spacer()
                Button("Visa original") { anonymize = false }
                    .buttonStyle(.link)
                    .help("Stäng av anonymiseringen. Slå på den igen med ögat i verktygsfältet.")
            }
            .font(.app(.regular))
        }
    }

    private var anonymizationOptions: AnonymizationOptions? {
        guard anonymize else { return nil }
        return AnonymizationSettings.options(
            names: anonymizeNames,
            identifiers: anonymizeIdentifiers,
            sensitiveTopics: anonymizeSensitive,
            organizations: anonymizeOrganizations,
            uncertainNames: anonymizeUncertainNames,
            alwaysHide: alwaysHide,
            neverHide: neverHide
        )
    }

    private func anonymizationInput(_ segments: [TranscriptSegment]) -> AnonymizationInput {
        AnonymizationInput(
            texts: segments.map(\.text),
            speakers: segments.map(\.speaker),
            options: anonymizationOptions
        )
    }

    /// Resultatet om det hör till nuvarande text och inställningar.
    private func currentAnonymization(for segments: [TranscriptSegment]) -> AnonymizationResult? {
        guard let anonymized, anonymized.input == anonymizationInput(segments),
              anonymized.result.segments.count == segments.count else { return nil }
        return anonymized.result
    }

    private func refreshAnonymization() async {
        let input = anonymizationInput(transcript.sortedSegments)
        guard let options = input.options, !input.texts.isEmpty else { return }
        let data = transcript.segmentData
        let result = await Task.detached(priority: .userInitiated) {
            Anonymizer.anonymize(data, options: options)
        }.value
        guard !Task.isCancelled else { return }
        anonymized = AnonymizedState(input: input, result: result)
    }

    /// Det som visas i listan. `nil` medan anonymiseringen räknas fram, så att
    /// originaltexten aldrig blinkar förbi.
    private func displaySegments(_ segments: [TranscriptSegment]) -> [DisplaySegment]? {
        guard anonymizationOptions != nil else {
            return segments.map { DisplaySegment(segment: $0, text: $0.text, speaker: $0.speaker, alternatives: $0.alternativeCount) }
        }
        // Medan man rättar räknas anonymiseringen om efter varje sparning. Då behålls det förra
        // resultatet, så att fälten inte försvinner och layouten inte hoppar.
        let stale = isEditing ? anonymized?.result : nil
        guard let result = currentAnonymization(for: segments) ?? stale, result.segments.count == segments.count else { return nil }
        return zip(segments, result.segments).map { segment, data in
            DisplaySegment(segment: segment, text: data.text, speaker: data.speaker, isAnonymized: true)
        }
    }

    /// Segment för kopiering och export: anonymiserade när inställningen är på.
    private var outputSegments: [SegmentData] {
        if anonymizationOptions != nil, let result = currentAnonymization(for: transcript.sortedSegments) {
            return result.segments
        }
        return transcript.outputSegments(options: anonymizationOptions)
    }

    // MARK: - Åtgärder

    private func beginRename(_ speaker: String) {
        newSpeakerName = speaker
        speakerToRename = speaker
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func export(as format: ExportFormat) {
        saveEditing()
        let output = TranscriptExporter.export(
            outputSegments,
            metadata: transcript.metadata,
            format: format,
            options: ExportOptions(includeTimestamps: exportTimestamps)
        )

        let panel = NSSavePanel()
        panel.title = "Exportera transkribering"
        panel.nameFieldStringValue = "\(transcript.title).\(format.fileExtension)"
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Binärsökning efter segmentet som innehåller `time`.
    static func activeSegment(in segments: [TranscriptSegment], at time: Double) -> TranscriptSegment? {
        var low = 0
        var high = segments.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let segment = segments[mid]
            if time < segment.start {
                high = mid - 1
            } else if time >= segment.end {
                low = mid + 1
            } else {
                return segment
            }
        }
        return nil
    }
}

/// Indata till anonymiseringen. När något ändras räknas resultatet om.
struct AnonymizationInput: Equatable {
    var texts: [String]
    var speakers: [String?]
    var options: AnonymizationOptions?
}

private struct AnonymizedState {
    var input: AnonymizationInput
    var result: AnonymizationResult
}

/// Stycket eller raden som flyttas till en ny talare medan namnet frågas efter.
struct NewSpeakerTarget {
    let indices: [Int]
    /// "stycket" eller "raden".
    let noun: String
}

/// Ett rollval som går att ångra: vem som valdes och talarna per segment före valet.
private struct RoleChoice {
    /// Talarna som valts till intervjuare, med namnen de hade när de valdes.
    var speakers: [String]
    let before: [String?]
}

/// Ett segment som det visas: anonymiserad eller original text och talare.
struct DisplaySegment: Identifiable {
    let segment: TranscriptSegment
    let text: String
    let speaker: String?
    /// Texten är anonymiserad (platshållare i stället för de dolda uppgifterna).
    var isAnonymized = false
    /// Antal markerade ord (experimentet Korskolla), så att raden ritas om när ett val görs.
    var alternatives = 0

    var id: PersistentIdentifier { segment.persistentModelID }

    /// Samma synliga innehåll. Ändringar i själva modellen når raderna via SwiftData-observationen.
    func sameContent(as other: DisplaySegment) -> Bool {
        id == other.id && text == other.text && speaker == other.speaker && isAnonymized == other.isAnonymized
            && alternatives == other.alternatives
    }
}

/// Läser uppspelningstiden i en egen vy, så att bara den ritas om när tiden tickar (10 gånger i
/// sekunden) och inte hela transkriptionsvyn. Kontrolleras av `scripts/test_scroll_perf.py`.
struct PlaybackTimeReader<Content: View>: View {
    let player: PlayerController?
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        content(player?.currentTime ?? 0)
    }
}

/// Segmentet som spelas just nu. Ändras bara när uppspelningen når ett nytt segment, så att det
/// som läser det (listan med stycken) inte ritas om tio gånger i sekunden.
@MainActor
@Observable
final class PlaybackFocus {
    private(set) var activeID: PersistentIdentifier?

    /// Skriver bara när segmentet faktiskt byts: varje skrivning ritar om listan.
    func update(_ id: PersistentIdentifier?) {
        if id != activeID { activeID = id }
    }
}

/// Osynlig vy som läser uppspelningstiden och uppdaterar `PlaybackFocus` när nästa segment börjar.
/// Den här lilla vyn är det enda i texten som räknas om vid varje tick.
struct PlaybackFocusTracker: View {
    let player: PlayerController?
    let segments: [TranscriptSegment]
    let focus: PlaybackFocus

    var body: some View {
        PlaybackTimeReader(player: player) { time in
            let id = TranscriptDetailView.activeSegment(in: segments, at: time)?.persistentModelID
            Color.clear.onChange(of: id, initial: true) { _, newID in focus.update(newID) }
        }
    }
}

/// Läser vilket segment som spelas, i en egen vy, så att bara listan ritas om när det byts.
struct PlaybackFocusReader<Content: View>: View {
    let focus: PlaybackFocus
    @ViewBuilder let content: (PersistentIdentifier?) -> Content

    var body: some View {
        content(focus.activeID)
    }
}

/// Spelaren startas när vyn visas och stängs när den försvinner; anonymiseringen räknas om vid ändring.
private struct DetailLifecycle: ViewModifier {
    let transcript: Transcript
    @Binding var player: PlayerController?
    let anonymizationKey: AnonymizationInput
    let refresh: () async -> Void
    /// Sparad uppspelningshastighet; gäller alla filer (Nicklas 2026-11-07).
    @AppStorage(SettingsKey.playbackSpeed) private var playbackSpeed = PlaybackSpeed.normal

    func body(content: Content) -> some View {
        content
            .onAppear {
                if player == nil { player = PlayerController(url: transcript.mediaURL, speed: playbackSpeed) }
            }
            .onChange(of: playbackSpeed) { _, speed in player?.setSpeed(speed) }
            .onDisappear {
                // Ett öppet videofönster hör till den här filen och stängs med den.
                if let player { VideoWindow.shared.closeIfShowing(player.player) }
                player?.invalidate()
                player = nil
            }
            .task(id: anonymizationKey) { await refresh() }
    }
}

/// Dialogerna: frågan före Transkribera igen (`RetranscribeSheet`) och Byt namn på talare.
private struct DetailDialogs: ViewModifier {
    @Binding var confirmRetranscribe: Bool
    @Binding var speakerToRename: String?
    @Binding var newSpeakerName: String
    @Binding var newSpeakerTarget: NewSpeakerTarget?
    @Binding var newSpeakerDraft: String
    let transcript: Transcript
    let onMoveToNewSpeaker: (NewSpeakerTarget, String) -> Void
    let onRetranscribe: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $confirmRetranscribe) {
                RetranscribeSheet(
                    versionCount: transcript.versionCount,
                    oldestDescription: transcript.oldestVersionDescription,
                    onCancel: { confirmRetranscribe = false },
                    onConfirm: {
                        confirmRetranscribe = false
                        onRetranscribe()
                    }
                )
                .presentationRoot()
            }
            .alert("Byt namn på talare", isPresented: Binding(
                get: { speakerToRename != nil },
                set: { if !$0 { speakerToRename = nil } }
            )) {
                TextField("Namn", text: $newSpeakerName)
                Button("Spara") {
                    if let old = speakerToRename {
                        transcript.renameSpeaker(old, to: newSpeakerName)
                    }
                    speakerToRename = nil
                }
                Button("Avbryt", role: .cancel) { speakerToRename = nil }
            } message: {
                Text("Det nya namnet används överallt där \(speakerToRename ?? "") pratar.")
            }
            .alert("Ny talare", isPresented: Binding(
                get: { newSpeakerTarget != nil },
                set: { if !$0 { newSpeakerTarget = nil } }
            )) {
                TextField("Namn", text: $newSpeakerDraft)
                Button("Flytta") {
                    if let target = newSpeakerTarget {
                        onMoveToNewSpeaker(target, newSpeakerDraft)
                    }
                    newSpeakerTarget = nil
                }
                Button("Avbryt", role: .cancel) { newSpeakerTarget = nil }
            } message: {
                Text("Bara \(newSpeakerTarget?.noun ?? "stycket") flyttas till den nya talaren. Namnet går att ändra senare.")
            }
    }
}

/// "Transkribera igen": grå som standard, blå (accent) när valen skiljer sig från filens.
struct RerunButtonStyle: ButtonStyle {
    let isEmphasized: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.small))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(isEmphasized ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.textPrimary))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEmphasized ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.chip))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// Fylld knapp med accentfärgen när läget är på, vanlig knapp när det är av. Samma storlek i
/// båda lägena, så att ingenting flyttar sig.
struct OnStateButtonStyle: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

import AppKit
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
    @State private var isEditing = false
    /// Håller stycket du läser kvar på skärmen när redigeringsläget växlar.
    @State private var scrollAnchor = ScrollAnchor()
    @State private var followPlayback = true
    @State private var speakerToRename: String?
    @State private var newSpeakerName = ""
    @State private var copied = false
    /// "Inte nu" på frågan om vem som är intervjuaren, för den här visningen.
    @State private var rolesDismissed = false
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
    @AppStorage(MiniPlayerSize.storageKey) private var miniSizeRaw = MiniPlayerSize.small.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let scrollSpace = "detailScroll"
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
            transcript: transcript,
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
            // Skrollvyn läses av, så att stycket du läser kan stå kvar när läget växlar.
            .background(ScrollOffsetObserver(onChange: { _ in }, anchor: scrollAnchor))
        }
        .coordinateSpace(name: Self.scrollSpace)
        // Stycket vid fönstrets överkant står kvar på samma plats när läget växlar.
        .onChange(of: isEditing) { _, _ in
            if let anchor = scrollAnchor.currentAnchor() { scrollAnchor.restore(anchor) }
        }
        // Esc stänger redigeringsläget. Fälten sparar när de tappar fokus.
        .onExitCommand { if isEditing { isEditing = false } }
        // Sökfältet stegar till en träff: den hamnar mitt i fönstret.
        .onChange(of: searchJump) { _, _ in scrollToCurrentHit(proxy: proxy) }
        .background {
            if isEditing {
                Button("Klar") { isEditing = false }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
        }
    }

    // MARK: - Kort

    private var hasText: Bool { !transcript.segments.isEmpty }
    private var isWorking: Bool { transcript.status == .queued || transcript.status == .transcribing }

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(Color.surface))
            .overlay(cardShape.strokeBorder(Color.line, lineWidth: 1))
    }

    /// Överst i texten: version, modell/språk/talare och Transkribera igen, och metadatan till höger.
    /// Får de inte plats på en rad hamnar metadatan under.
    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                versionPicker
                settingsPill
                rerunButton
                Spacer(minLength: 12)
                metaLine.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    versionPicker
                    settingsPill
                    rerunButton
                    Spacer(minLength: 0)
                }
                metaLine
            }
        }
    }

    private var rerunButton: some View {
        Button {
            requestRetranscribe()
        } label: {
            Label("Transkribera igen", systemImage: "arrow.clockwise")
        }
        .buttonStyle(RerunButtonStyle(isEmphasized: rerunSettingsChanged))
        .disabled(isWorking)
        .help("Transkribera filen igen med valen i knappen till vänster. Den nuvarande versionen sparas.")
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
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.chip, in: Capsule())
            .overlay(Capsule().strokeBorder(overrides.isEmpty ? Color.clear : Color.accentColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .help("Modell, språk och talare. Klicka för att välja andra till nästa omtagning.")
        .popover(isPresented: $showRerunSettings, arrowEdge: .bottom) {
            RerunSettingsPopover(overrides: $overrides, file: fileBaseline)
        }
    }

    private var settingsSummary: String {
        [modelChipText, languageChipText, speakersChipText].compactMap { $0 }.joined(separator: " · ")
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
            Text(statusText)
                .foregroundStyle(transcript.status == .failed ? AnyShapeStyle(Color.warning) : AnyShapeStyle(Color.textSecondary))
            Text("·")
            Text(transcript.liveVersionDate.formatted(date: .long, time: .shortened))
            Text("·")
            Text(TimeFormatting.duration(transcript.duration)).monospacedDigit()
        }
        .font(.callout)
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
            Menu {
                Picker("Version", selection: Binding(
                    get: { transcript.id },
                    set: { switchVersion(to: $0) }
                )) {
                    ForEach(transcript.versionInfos.reversed()) { info in
                        Text(versionMenuTitle(info)).tag(info.id)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Text("De \(VersionHistory.capacity) senaste versionerna sparas. Äldre raderas.")
            } label: {
                Text(label)
                    .monospacedDigit()
                    .fontWeight(older ? .semibold : .regular)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(older ? 0.15 : 0), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isWorking)
            .help("Byt mellan sparade versioner av texten. Varje version har egna rättningar och talarnamn.")
        }
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
        isEditing = false
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
                Image(systemName: "clock.arrow.circlepath")
                Text("Du tittar på en äldre version (\(label)). Rättningar sparas i den här versionen.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Visa senaste versionen") { showLatestVersion() }
                    .buttonStyle(.link)
                    .disabled(isWorking)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Säger vilken text som rättas. Ligger sist på raden efter Klar, så att ingenting flyttar sig
    /// när den visas.
    @ViewBuilder
    private var editStateLabel: some View {
        if isEditing {
            Text(anonymizationOptions != nil ? "Redigerar anonymiserad text" : "Redigerar originaltexten")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .truncationMode(.tail)
                // Titeln får hellre kortas än den här texten.
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
            Image(systemName: "magnifyingglass").foregroundStyle(Color.textSecondary)
            TextField("Sök i texten", text: $query)
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
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize()
                HStack(spacing: 2) {
                    Button { stepHit(forward: false) } label: {
                        Image(systemName: "chevron.up").frame(width: 18, height: 16)
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .help("Förra träffen (⇧⌘G)")
                    .accessibilityLabel("Förra träffen")
                    Button { stepHit(forward: true) } label: {
                        Image(systemName: "chevron.down").frame(width: 18, height: 16)
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
            if hasText { toolbarSearch }
            editStateLabel
            editToggle
            moreMenu
        }
    }

    /// Samma åtgärder som verktygsraden, så att de går att nå även när den har skrollats bort.
    private var moreMenu: some View {
        Menu {
            if hasText {
                Picker("Visning", selection: $layout) {
                    ForEach(TranscriptLayout.allCases) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .pickerStyle(.inline)
                Toggle(isOn: $anonymize) {
                    Label("Anonymisera", systemImage: anonymize ? "eye.slash" : "eye")
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
            Image(systemName: "ellipsis").accessibilityLabel("Fler val")
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

    /// Redigera/Klar. Fylld med accentfärgen när redigeringsläget är på.
    private var editToggle: some View {
        Toggle(isOn: $isEditing) {
            Label(isEditing ? "Klar" : "Redigera", systemImage: isEditing ? "checkmark" : "pencil")
        }
        .toggleStyle(.button)
        .modifier(OnStateButtonStyle(isOn: isEditing))
        .help(isEditing
              ? "Stäng redigeringsläget. Ändringarna sparas automatiskt (Esc)"
              : "Rätta texten direkt i transkriberingen")
        .disabled(!hasText)
    }

    /// Anonymisera. Fylld med accentfärgen när anonymiseringen är på.
    private var anonymizeToggle: some View {
        Toggle(isOn: $anonymize) {
            Label("Anonymisera", systemImage: anonymize ? "eye.slash" : "eye")
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
                Label("Talare", systemImage: "person.2")
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
        Section("Intervjuare") {
            ForEach(transcript.speakers, id: \.self) { speaker in
                Toggle(speaker, isOn: Binding(
                    get: { SpeakerRoles.isInterviewer(speaker) },
                    set: { transcript.setInterviewer(speaker, to: $0) }
                ))
            }
        }
        Divider()
        Button("Visa talarturer i Finder (för felsökning)") {
            NSWorkspace.shared.open(AppPaths.speakerTurnsDirectory)
        }
    }

    private func copyText() {
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
            Label(copied ? "Kopierat!" : "Kopiera text", systemImage: copied ? "checkmark" : "doc.on.doc")
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
                Image(systemName: "square.and.arrow.up")
                Text("Exportera")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.body.weight(.medium))
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

    /// Spelaren, fast under titelbaren: bild (video), spela, tid, reglage och Följ uppspelning.
    @ViewBuilder
    private var playerBar: some View {
        if hasText, let player {
            HStack(spacing: 14) {
                if transcript.isVideo { miniPlayer(player) }
                playPauseAndTime(player)
                positionSlider(player, maxWidth: .infinity)
                Text(TimeFormatting.short(transcript.duration))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                if transcript.isVideo { sizeMenu }
                Toggle(isOn: $followPlayback) {
                    Text("Följ uppspelning")
                }
                .toggleStyle(.checkbox)
                .help("Håll stycket som spelas upp i bild")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
        }
    }

    private var showsRolesBanner: Bool {
        !rolesDismissed && hasText && SpeakerRoles.needsRoles(transcript.speakers)
    }

    private var showsAnonymizationBanner: Bool { anonymizationOptions != nil && hasText }

    /// 5. Notiser samlade i ett kort.
    @ViewBuilder
    private var noticeCard: some View {
        if showsRolesBanner || showsAnonymizationBanner {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    rolesBanner
                    anonymizationBanner
                }
            }
        }
    }

    /// Videobilden i spelarraden. Liten som standard; Bildstorlek väljer mellan tre.
    private func miniPlayer(_ player: PlayerController) -> some View {
        let size = MiniPlayerSize.resolved(miniSizeRaw)
        return PlayerView(player: player.player, isVideo: true, compact: true)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var sizeMenu: some View {
        Menu {
            Picker("Bildstorlek", selection: $miniSizeRaw) {
                ForEach(MiniPlayerSize.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right").accessibilityLabel("Bildstorlek")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Bildstorlek: liten, mellan eller stor")
    }

    private func playPauseAndTime(_ player: PlayerController) -> some View {
        HStack(spacing: 10) {
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(player.isPlaying ? "Pausa" : "Spela")
            Text(TimeFormatting.short(player.currentTime))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func positionSlider(_ player: PlayerController, maxWidth: CGFloat = 200) -> some View {
        Slider(
            value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0, play: player.isPlaying) }
            ),
            in: 0...max(transcript.duration, 1)
        )
        .frame(minWidth: 80, maxWidth: maxWidth)
        .help("Hoppa i inspelningen")
    }

    /// Frågar först när något ska sparas eller raderas (se `RetranscribeDialog`).
    private func requestRetranscribe() {
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
                    Label("Transkriberingen misslyckades", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(transcript.errorMessage ?? "Okänt fel.")
                } actions: {
                    Button("Försök igen") { retranscribe(confirmed: false) }
                        .help("Transkribera filen igen med nuvarande inställningar")
                        .buttonStyle(.borderedProminent)
                }
            }
        default:
            textRows(proxy: proxy)
        }
    }

    @ViewBuilder
    private func textRows(proxy: ScrollViewProxy) -> some View {
        let segments = transcript.sortedSegments
        if let rows = displaySegments(segments) {
            let currentTime = player?.currentTime ?? 0
            let activeID = Self.activeSegment(in: segments, at: currentTime)?.persistentModelID
            switch layout {
            case .paragraphs:
                paragraphRows(rows: rows, currentTime: currentTime, activeID: activeID, proxy: proxy)
            case .segments:
                segmentRows(rows: rows, currentTime: currentTime, activeID: activeID, proxy: proxy)
            }
        } else {
            ProgressView("Anonymiserar…")
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func follow(_ id: some Hashable, proxy: ScrollViewProxy) {
        guard followPlayback, player?.isPlaying == true, !isEditing else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func segmentRows(rows: [DisplaySegment], currentTime: Double, activeID: PersistentIdentifier?, proxy: ScrollViewProxy) -> some View {
        // Hela texten visas alltid; sökningen markerar och stegar mellan träffarna.
        let hit = currentHit
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
                        currentTime: currentTime,
                        isEditing: isEditing,
                        isAnonymized: row.isAnonymized,
                        onSeek: { player?.seek(to: segment.start) }
                    )
                    .id(segment.persistentModelID)
                    .background(RowFrameReporter(id: AnyHashable(segment.persistentModelID), anchor: scrollAnchor, space: Self.scrollSpace))
                    .contextMenu { segmentMenu(row) }
                    Divider()
                }
            }
        }
        .onChange(of: activeID) { _, newValue in
            if let newValue { follow(newValue, proxy: proxy) }
        }
    }

    private func paragraphRows(rows: [DisplaySegment], currentTime: Double, activeID: PersistentIdentifier?, proxy: ScrollViewProxy) -> some View {
        let paragraphs = Self.paragraphs(rows)
        // Hela texten visas alltid; sökningen markerar och stegar mellan träffarna.
        let hit = currentHit
        let activeParagraphID = paragraphs.first { paragraph in paragraph.contains { $0.id == activeID } }?.first?.id

        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(paragraphs, id: \.first?.id) { paragraph in
                    ParagraphRow(
                        rows: paragraph,
                        query: query,
                        currentHit: hit,
                        activeID: activeID,
                        currentTime: currentTime,
                        isEditing: isEditing,
                        onSeek: { player?.seek(to: $0) },
                        speakerMenu: { speaker in
                            AnyView(Group {
                                Button("Byt namn på \(speaker)…") { beginRename(speaker) }
                                interviewerButton(speaker)
                            })
                        }
                    )
                    .id(paragraph.first?.id)
                    .background(RowFrameReporter(id: AnyHashable(paragraph.first?.id), anchor: scrollAnchor, space: Self.scrollSpace))
                    .contextMenu { paragraphMenu(paragraph) }
                    Divider()
                }
            }
        }
        .onChange(of: activeParagraphID) { _, newValue in
            if let newValue { follow(newValue, proxy: proxy) }
        }
    }

    /// Delar upp raderna i stycken på samma sätt som "Exportera för analys".
    private static func paragraphs(_ rows: [DisplaySegment]) -> [[DisplaySegment]] {
        let data = rows.map { SegmentData(start: $0.segment.start, end: $0.segment.end, text: $0.text, speaker: $0.speaker) }
        return AnalysisExporter.paragraphRanges(data).map { Array(rows[$0]) }
    }

    @ViewBuilder
    private func paragraphMenu(_ paragraph: [DisplaySegment]) -> some View {
        if let first = paragraph.first {
            let text = paragraph.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            Button("Spela upp stycket") { player?.seek(to: first.segment.start) }
            Button("Kopiera stycket") { copyToPasteboard(text) }
            Button("Kopiera med tidsstämpel") {
                var line = "[\(TimeFormatting.short(first.segment.start))] "
                if let speaker = first.speaker { line += "\(speaker): " }
                copyToPasteboard(line + text)
            }
            if let speaker = first.segment.speaker {
                Divider()
                Button("Byt namn på \(speaker)…") { beginRename(speaker) }
                interviewerButton(speaker)
            }
        }
    }

    @ViewBuilder
    private func segmentMenu(_ row: DisplaySegment) -> some View {
        let segment = row.segment
        Button("Spela upp härifrån") { player?.seek(to: segment.start) }
        Button("Kopiera stycket") { copyToPasteboard(row.text) }
        Button("Kopiera med tidsstämpel") {
            copyToPasteboard("[\(TimeFormatting.short(segment.start))] \(row.text)")
        }
        if let speaker = segment.speaker {
            Divider()
            Button("Byt namn på \(speaker)…") { beginRename(speaker) }
            interviewerButton(speaker)
        }
    }

    // MARK: - Roller

    /// Frågar vem som är intervjuaren när talarna bara heter "Talare 1", "Talare 2" …
    @ViewBuilder
    private var rolesBanner: some View {
        let speakers = transcript.speakers
        if !rolesDismissed, !isEditing, SpeakerRoles.needsRoles(speakers) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                Text("Vem av talarna är du?")
                ForEach(speakers, id: \.self) { speaker in
                    HStack(spacing: 2) {
                        Circle().fill(SpeakerPalette.color(for: speaker)).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Button(speaker) { transcript.setInterviewer(speaker) }
                            .help("\(speaker) blir Intervjuare och övriga Kund 1, Kund 2 … Det går att ändra under Talare i verktygsfältet.")
                        Button {
                            if let first = transcript.sortedSegments.first(where: { $0.speaker == speaker }) {
                                player?.seek(to: first.start)
                            }
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Lyssna på \(speaker)")
                    }
                }
                Spacer()
                Button("Inte nu") { rolesDismissed = true }
                    .buttonStyle(.link)
            }
            .font(.callout)
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
                Image(systemName: "eye.slash")
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
            .font(.callout)
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
            return segments.map { DisplaySegment(segment: $0, text: $0.text, speaker: $0.speaker) }
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

/// Ett segment som det visas: anonymiserad eller original text och talare.
struct DisplaySegment: Identifiable {
    let segment: TranscriptSegment
    let text: String
    let speaker: String?
    /// Texten är anonymiserad (platshållare i stället för de dolda uppgifterna).
    var isAnonymized = false

    var id: PersistentIdentifier { segment.persistentModelID }
}

/// Spelaren startas när vyn visas och stängs när den försvinner; anonymiseringen räknas om vid ändring.
private struct DetailLifecycle: ViewModifier {
    let transcript: Transcript
    @Binding var player: PlayerController?
    let anonymizationKey: AnonymizationInput
    let refresh: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if player == nil { player = PlayerController(url: transcript.mediaURL) }
            }
            .onDisappear {
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
    let transcript: Transcript
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
    }
}

/// "Transkribera igen": grå som standard, blå (accent) när valen skiljer sig från filens.
private struct RerunButtonStyle: ButtonStyle {
    let isEmphasized: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
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

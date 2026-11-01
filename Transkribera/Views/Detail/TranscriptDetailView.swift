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
    @State private var showOnlyMatches = true
    @State private var isEditing = false
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

    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var isCollapsed = false
    @State private var confirmRetranscribe = false
    @State private var overrides = TranscriptionOverrides()
    @State private var showRerunSettings = false
    @AppStorage(MiniPlayerSize.storageKey) private var miniSizeRaw = MiniPlayerSize.small.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let scrollSpace = "detailScroll"
    private static let topID = "detailTop"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                mainScroll(proxy: proxy)
                if isCollapsed {
                    collapsedBar(proxy: proxy)
                        .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                }
            }
        }
        // Fönstrets titel behålls för Fönster-menyn; macOS 14 kan inte dölja den (kräver macOS 15).
        .navigationTitle(transcript.title)
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
                chipsRow
                titleCard
                playerCard
                noticeCard
                textArea(proxy: proxy)
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            // Hela innehållet mäts, så att skrollpositionen alltid rapporteras.
            .background(ScrollOffsetObserver { updateCollapse(offset: $0) })
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: -geo.frame(in: .named(Self.scrollSpace)).minY
                )
            })
        }
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(ScrollOffsetKey.self) { updateCollapse(offset: $0) }
        // Esc stänger redigeringsläget. Fälten sparar när de tappar fokus.
        .onExitCommand { if isEditing { isEditing = false } }
        .background {
            if isEditing {
                Button("Klar") { isEditing = false }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
        }
    }

    private func updateCollapse(offset: Double) {
        let next = TitleCardCollapse.isCollapsed(offset: offset, wasCollapsed: isCollapsed)
        guard next != isCollapsed else { return }
        if reduceMotion {
            isCollapsed = next
        } else {
            withAnimation(.easeInOut(duration: 0.15)) { isCollapsed = next }
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
            .background(cardShape.fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(cardShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    /// 1. Modell, språk och antal talare som transkriberingen gjordes med, och Transkribera igen.
    private var chipsRow: some View {
        HStack(spacing: 8) {
            settingsChip(modelChipText, help: "Modell. Klicka för att välja en annan till nästa omtagning.")
            settingsChip(languageChipText, help: "Språk. Klicka för att välja ett annat till nästa omtagning.")
            if let speakersText = speakersChipText {
                settingsChip(speakersText, help: "Talare. Klicka för att ändra till nästa omtagning.")
            }
            Spacer()
            Button {
                if hasText {
                    confirmRetranscribe = true
                } else {
                    retranscribe(confirmed: false)
                }
            } label: {
                Label("Transkribera igen", systemImage: "arrow.clockwise")
            }
            .buttonStyle(RerunButtonStyle(isEmphasized: rerunSettingsChanged))
            .disabled(isWorking)
            .help("Transkribera filen igen med valen i chipsen. Rättningar och talarnamn ersätts.")
        }
        .popover(isPresented: $showRerunSettings, arrowEdge: .bottom) {
            RerunSettingsPopover(overrides: $overrides, file: fileBaseline)
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

    /// Chip som öppnar valen för omtagningen; accentkant när något är ändrat.
    private func settingsChip(_ text: String, help: String) -> some View {
        Button { showRerunSettings = true } label: {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(overrides.isEmpty ? Color.clear : Color.accentColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .help(help)
    }

    private var statusText: String {
        switch transcript.status {
        case .completed: "Klar"
        case .transcribing: "Transkriberar"
        case .queued: "I kö"
        case .failed: "Misslyckades"
        }
    }

    /// 3. Titelkortet: status, titel, intervjuare, sök och export, och verktygen.
    private var titleCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(statusText)
                        .foregroundStyle(transcript.status == .failed ? AnyShapeStyle(Color.warning) : AnyShapeStyle(.secondary))
                    Text("·").foregroundStyle(.secondary)
                    Text(transcript.createdAt.formatted(date: .long, time: .shortened))
                    Text("·").foregroundStyle(.secondary)
                    Text(TimeFormatting.duration(transcript.duration)).monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 10) {
                    TextField("Titel", text: $transcript.title)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .help("Klicka för att byta namn")
                    interviewerPill
                    if isEditing { editingPill }
                    Spacer(minLength: 8)
                    Button {
                        openSearch()
                    } label: {
                        Label("Sök i texten", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f")
                    .disabled(!hasText)
                    .help("Sök i transkriberingen (⌘F)")
                    exportMenu()
                }

                if showSearch { searchRow }

                Divider()
                HStack(spacing: 8) {
                    toolButtons(iconsOnly: false)
                    Spacer()
                    if hasText {
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
                }
            }
        }
    }

    /// Visar att man är i redigeringsläget. Ligger på titelraden, så att ingenting flyttar sig.
    private var editingPill: some View {
        Label(anonymizationOptions != nil ? "Redigerar anonymiserad text" : "Redigerar originaltexten", systemImage: "pencil")
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var interviewerPill: some View {
        let speakers = transcript.speakers
        if !speakers.isEmpty {
            let current = speakers.filter(SpeakerRoles.isInterviewer)
            Menu {
                ForEach(speakers, id: \.self) { speaker in
                    Toggle(speaker, isOn: Binding(
                        get: { SpeakerRoles.isInterviewer(speaker) },
                        set: { transcript.setInterviewer(speaker, to: $0) }
                    ))
                }
            } label: {
                Text(current.isEmpty ? "Välj intervjuare" : "Intervjuare: \(current.joined(separator: ", "))")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .help("Byt intervjuare. Övriga talare blir Kund 1, Kund 2 …")
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Sök i transkriberingen", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {}
            if !query.isEmpty {
                let count = TextSearch.countMatches(of: query, in: (displaySegments(transcript.sortedSegments) ?? []).map(\.text))
                Text(count == 1 ? "1 träff" : "\(count) träffar")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Toggle("Visa bara träffar", isOn: $showOnlyMatches)
                    .toggleStyle(.checkbox)
                    .help("Dölj stycken som inte innehåller sökordet")
            }
            Button("Stäng") {
                query = ""
                showSearch = false
            }
            .buttonStyle(.link)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openSearch() {
        showSearch = true
        // Fältet finns inte i vyn förrän nästa varv.
        Task { @MainActor in searchFocused = true }
    }

    /// Redigera, Anonymisera, Talare och Kopiera text. Med text i titelkortet, bara ikoner i den hopfällda raden.
    @ViewBuilder
    private func toolButtons(iconsOnly: Bool) -> some View {
        Toggle(isOn: $isEditing) {
            toolLabel(isEditing ? "Klar" : "Redigera", isEditing ? "checkmark" : "pencil", iconsOnly: iconsOnly)
        }
        .toggleStyle(.button)
        .tint(isEditing ? Color.accentColor : nil)
        .help(isEditing
              ? "Stäng redigeringsläget. Ändringarna sparas automatiskt (Esc)"
              : "Rätta texten direkt i transkriberingen")
        .disabled(!hasText)

        Toggle(isOn: $anonymize) {
            toolLabel("Anonymisera", anonymize ? "eye.slash" : "eye", iconsOnly: iconsOnly)
        }
        .toggleStyle(.button)
        .help(anonymize
              ? "Namn och känsliga uppgifter är dolda. Klicka för att visa originalet."
              : "Dölj namn, personnummer och andra känsliga uppgifter")

        if !transcript.speakers.isEmpty {
            Menu {
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
            } label: {
                toolLabel("Talare", "person.2", iconsOnly: iconsOnly)
            }
            .fixedSize()
            .help("Ge talarna riktiga namn")
        }

        Button {
            copyToPasteboard(TranscriptExporter.fullText(outputSegments))
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            toolLabel(copied ? "Kopierat!" : "Kopiera text", copied ? "checkmark" : "doc.on.doc", iconsOnly: iconsOnly)
        }
        .help("Kopiera hela transkriberingen till urklipp")
        .disabled(!hasText)
    }

    @ViewBuilder
    private func toolLabel(_ title: String, _ symbol: String, iconsOnly: Bool) -> some View {
        if iconsOnly {
            Image(systemName: symbol).accessibilityLabel(title)
        } else {
            Label(title, systemImage: symbol)
        }
    }

    private func exportMenu() -> some View {
        Menu {
            ForEach(ExportFormat.allCases) { format in
                Button(format.displayName) { export(as: format) }
            }
            Divider()
            Button("Exportera för analys…") { appState.isAnalysisExportPresented = true }
                .help("En Markdown-fil per session, anpassad för analys i t.ex. Claude")
            Divider()
            Toggle("Ta med tidsstämplar (.txt och .md)", isOn: $exportTimestamps)
        } label: {
            Label("Exportera", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .help("Spara som text, Markdown, undertexter eller JSON")
        .disabled(!hasText)
    }

    /// 4. Spelaren i ett eget kort, med Följ uppspelning.
    @ViewBuilder
    private var playerCard: some View {
        if hasText {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if let player {
                            PlayerView(player: player.player, isVideo: transcript.isVideo)
                        } else {
                            Color.black.opacity(0.05)
                        }
                    }
                    .frame(height: transcript.isVideo ? 300 : 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Toggle(isOn: $followPlayback) {
                        Label("Följ uppspelning", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .toggleStyle(.checkbox)
                    .help("Håll stycket som spelas upp i bild")
                }
            }
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

    /// 7. Den hopfällda raden som ligger kvar överst som ett overlay, så att texten inte hoppar.
    private func collapsedBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if transcript.isVideo, let player {
                miniPlayer(player)
            }
            if let player {
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(player.isPlaying ? "Pausa" : "Spela")
                Text(TimeFormatting.short(player.currentTime))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0, play: player.isPlaying) }
                    ),
                    in: 0...max(transcript.duration, 1)
                )
                .frame(minWidth: 80, maxWidth: 200)
                .help("Hoppa i inspelningen")
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            } label: {
                Text(transcript.title).font(.headline).lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Till början")
            Spacer(minLength: 8)
            toolButtons(iconsOnly: true)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
                openSearch()
            } label: {
                Image(systemName: "magnifyingglass").accessibilityLabel("Sök i texten")
            }
            .disabled(!hasText)
            .help("Sök i texten (⌘F)")
            exportMenu()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: cardShape)
        .overlay(cardShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: 860)
    }

    /// Videobilden i den hopfällda raden. Liten som standard; Bildstorlek väljer mellan tre.
    private func miniPlayer(_ player: PlayerController) -> some View {
        let size = MiniPlayerSize.resolved(miniSizeRaw)
        return HStack(spacing: 6) {
            PlayerView(player: player.player, isVideo: true, compact: true)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        let visible = (query.isEmpty || !showOnlyMatches)
            ? rows
            : rows.filter { TextSearch.matches($0.text, query: query) }

        return VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 40)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { row in
                    let segment = row.segment
                    SegmentRow(
                        segment: segment,
                        displayText: row.text,
                        displaySpeaker: row.speaker,
                        query: query,
                        isActive: segment.persistentModelID == activeID,
                        currentTime: currentTime,
                        isEditing: isEditing,
                        isAnonymized: row.isAnonymized,
                        onSeek: { player?.seek(to: segment.start) }
                    )
                    .id(segment.persistentModelID)
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
        let visible = (query.isEmpty || !showOnlyMatches)
            ? paragraphs
            : paragraphs.filter { paragraph in paragraph.contains { TextSearch.matches($0.text, query: query) } }
        let activeParagraphID = paragraphs.first { paragraph in paragraph.contains { $0.id == activeID } }?.first?.id

        return VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 40)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible, id: \.first?.id) { paragraph in
                    ParagraphRow(
                        rows: paragraph,
                        query: query,
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
                        .foregroundStyle(.secondary)
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

/// Hur långt texten har skrollats förbi toppen, för det hopfällda titelkortet
/// (i macOS 14 finns inget färdigt API för skrollposition).
private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
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

/// Dialogerna: bekräftelse för Transkribera igen och Byt namn på talare.
private struct DetailDialogs: ViewModifier {
    @Binding var confirmRetranscribe: Bool
    @Binding var speakerToRename: String?
    @Binding var newSpeakerName: String
    let transcript: Transcript
    let onRetranscribe: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Transkribera igen?", isPresented: $confirmRetranscribe, titleVisibility: .visible) {
                Button("Transkribera igen", role: .destructive, action: onRetranscribe)
            } message: {
                Text(RetranscribeConfirmation.dialogMessage)
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
            .foregroundStyle(isEmphasized ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEmphasized ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

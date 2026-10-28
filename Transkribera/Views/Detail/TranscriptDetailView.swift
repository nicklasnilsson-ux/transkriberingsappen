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

    var body: some View {
        VStack(spacing: 0) {
            header
            anonymizationBanner
            Group {
                if let player {
                    PlayerView(player: player.player, isVideo: transcript.isVideo)
                } else {
                    Color.black.opacity(0.05)
                }
            }
            .frame(height: transcript.isVideo ? 300 : 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal)
            .padding(.bottom, 8)
            if isEditing {
                Label("Klicka i texten för att rätta den. Ändringarna sparas automatiskt.", systemImage: "pencil")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            content
        }
        .navigationTitle(transcript.title)
        .navigationSubtitle(subtitle)
        .searchable(text: $query, placement: .toolbar, prompt: "Sök i transkriberingen")
        .toolbar { toolbarContent }
        .onAppear {
            if player == nil { player = PlayerController(url: transcript.mediaURL) }
        }
        .onDisappear {
            player?.invalidate()
            player = nil
        }
        .task(id: anonymizationInput(transcript.sortedSegments)) {
            await refreshAnonymization()
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

    // MARK: - Delar

    private var subtitle: String {
        var parts = [TimeFormatting.duration(transcript.duration)]
        if let language = transcript.language {
            parts.append(Language.displayName(for: language))
        }
        parts.append(transcript.modelName)
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Titel", text: $transcript.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .help("Klicka för att byta namn")
                Text(transcript.createdAt.formatted(date: .long, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !query.isEmpty {
                let count = TextSearch.countMatches(of: query, in: (displaySegments(transcript.sortedSegments) ?? []).map(\.text))
                Text(count == 1 ? "1 träff" : "\(count) träffar")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Toggle("Visa bara träffar", isOn: $showOnlyMatches)
                    .toggleStyle(.checkbox)
                    .help("Dölj stycken som inte innehåller sökordet")
            }
            if !transcript.segments.isEmpty {
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
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch transcript.status {
        case .queued, .transcribing:
            TranscriptionProgressView(transcript: transcript)
        case .failed where transcript.segments.isEmpty:
            ContentUnavailableView {
                Label("Transkriberingen misslyckades", systemImage: "exclamationmark.triangle")
            } description: {
                Text(transcript.errorMessage ?? "Okänt fel.")
            } actions: {
                Button("Försök igen") { queue.retranscribe(transcript) }
                    .help("Transkribera filen igen med nuvarande inställningar")
                    .buttonStyle(.borderedProminent)
            }
        default:
            segmentList
        }
    }

    @ViewBuilder
    private var segmentList: some View {
        let segments = transcript.sortedSegments
        if let rows = displaySegments(segments) {
            switch layout {
            case .paragraphs: paragraphScroll(segments: segments, rows: rows)
            case .segments: segmentScroll(segments: segments, rows: rows)
            }
        } else {
            ProgressView("Anonymiserar…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func segmentScroll(segments: [TranscriptSegment], rows: [DisplaySegment]) -> some View {
        let visible = (query.isEmpty || !showOnlyMatches)
            ? rows
            : rows.filter { TextSearch.matches($0.text, query: query) }
        let currentTime = player?.currentTime ?? 0
        let activeID = Self.activeSegment(in: segments, at: currentTime)?.persistentModelID

        return ScrollViewReader { proxy in
            ScrollView {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                }
                LazyVStack(alignment: .leading, spacing: 2) {
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
                            onSeek: { player?.seek(to: segment.start) }
                        )
                        .id(segment.persistentModelID)
                        .contextMenu { segmentMenu(row) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .onChange(of: activeID) { _, newValue in
                guard followPlayback, player?.isPlaying == true, !isEditing, let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func paragraphScroll(segments: [TranscriptSegment], rows: [DisplaySegment]) -> some View {
        let paragraphs = Self.paragraphs(rows)
        let visible = (query.isEmpty || !showOnlyMatches)
            ? paragraphs
            : paragraphs.filter { paragraph in paragraph.contains { TextSearch.matches($0.text, query: query) } }
        let currentTime = player?.currentTime ?? 0
        let activeID = Self.activeSegment(in: segments, at: currentTime)?.persistentModelID
        let activeParagraphID = paragraphs.first { paragraph in paragraph.contains { $0.id == activeID } }?.first?.id

        return ScrollViewReader { proxy in
            ScrollView {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                }
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visible, id: \.first?.id) { paragraph in
                        ParagraphRow(
                            rows: paragraph,
                            query: query,
                            activeID: activeID,
                            currentTime: currentTime,
                            isEditing: isEditing,
                            onSeek: { player?.seek(to: $0) }
                        )
                        .id(paragraph.first?.id)
                        .contextMenu { paragraphMenu(paragraph) }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .onChange(of: activeParagraphID) { _, newValue in
                guard followPlayback, player?.isPlaying == true, !isEditing, let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
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
        }
    }

    // MARK: - Verktygsfält

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $isEditing) {
                Label("Redigera", systemImage: "pencil")
            }
            .help("Rätta texten direkt i transkriberingen")
            .disabled(transcript.segments.isEmpty)

            Toggle(isOn: $anonymize) {
                Label("Anonymisera", systemImage: anonymize ? "eye.slash" : "eye")
            }
            .help(anonymize
                  ? "Namn och känsliga uppgifter är dolda. Klicka för att visa originalet."
                  : "Dölj namn, personnummer och andra känsliga uppgifter")

            Toggle(isOn: $followPlayback) {
                Label("Följ uppspelning", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .help("Håll stycket som spelas upp i bild")

            if !transcript.speakers.isEmpty {
                Menu {
                    ForEach(transcript.speakers, id: \.self) { speaker in
                        Button("Byt namn på \(speaker)…") { beginRename(speaker) }
                    }
                } label: {
                    Label("Talare", systemImage: "person.2")
                }
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
                Label(copied ? "Kopierat!" : "Kopiera text", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .help("Kopiera hela transkriberingen till urklipp")
            .disabled(transcript.segments.isEmpty)

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
            .help("Spara som text, Markdown, undertexter eller JSON")
            .disabled(transcript.segments.isEmpty)
        }
    }

    // MARK: - Anonymisering

    @ViewBuilder
    private var anonymizationBanner: some View {
        if anonymizationOptions != nil, !transcript.segments.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                if isEditing {
                    Text("Redigeringsläget visar originaltexten.")
                } else if let result = currentAnonymization(for: transcript.sortedSegments) {
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
            .padding(.horizontal)
            .padding(.bottom, 8)
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
        guard anonymizationOptions != nil, !isEditing else {
            return segments.map { DisplaySegment(segment: $0, text: $0.text, speaker: $0.speaker) }
        }
        guard let result = currentAnonymization(for: segments) else { return nil }
        return zip(segments, result.segments).map { segment, data in
            DisplaySegment(segment: segment, text: data.text, speaker: data.speaker)
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
private struct AnonymizationInput: Equatable {
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

    var id: PersistentIdentifier { segment.persistentModelID }
}

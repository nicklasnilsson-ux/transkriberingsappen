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

    var body: some View {
        VStack(spacing: 0) {
            header
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
                let count = TextSearch.countMatches(of: query, in: transcript.segments.map(\.text))
                Text(count == 1 ? "1 träff" : "\(count) träffar")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Toggle("Visa bara träffar", isOn: $showOnlyMatches)
                    .toggleStyle(.checkbox)
                    .help("Dölj stycken som inte innehåller sökordet")
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

    private var segmentList: some View {
        let segments = transcript.sortedSegments
        let visible = (query.isEmpty || !showOnlyMatches)
            ? segments
            : segments.filter { TextSearch.matches($0.text, query: query) }
        let currentTime = player?.currentTime ?? 0
        let activeID = Self.activeSegment(in: segments, at: currentTime)?.persistentModelID

        return ScrollViewReader { proxy in
            ScrollView {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 40)
                }
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visible) { segment in
                        SegmentRow(
                            segment: segment,
                            query: query,
                            isActive: segment.persistentModelID == activeID,
                            currentTime: currentTime,
                            isEditing: isEditing,
                            onSeek: { player?.seek(to: segment.start) }
                        )
                        .id(segment.persistentModelID)
                        .contextMenu { segmentMenu(segment) }
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

    @ViewBuilder
    private func segmentMenu(_ segment: TranscriptSegment) -> some View {
        Button("Spela upp härifrån") { player?.seek(to: segment.start) }
        Button("Kopiera stycket") { copyToPasteboard(segment.text) }
        Button("Kopiera med tidsstämpel") {
            copyToPasteboard("[\(TimeFormatting.short(segment.start))] \(segment.text)")
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
                copyToPasteboard(transcript.fullText)
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
            transcript.segmentData,
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

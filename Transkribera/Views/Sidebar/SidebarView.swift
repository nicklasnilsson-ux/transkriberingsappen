import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

struct SidebarView: View {
    @Binding var selection: Transcript?
    @Binding var multiSelection: [Transcript]
    @Environment(TranscriptionQueue.self) private var queue
    @Environment(AppState.self) private var appState
    @Environment(MeetingRecorder.self) private var recorder
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var filter = ""
    @State private var transcriptToDelete: Transcript?
    @State private var transcriptToRetranscribe: Transcript?
    @AppStorage(SettingsKey.askBeforeRetranscribe) private var askBeforeRetranscribe = true
    @State private var showsNextSettings = false
    /// Listans val som mängd: en eller flera. Flera ligger i `multiSelection`, en i `selection`.
    private var listSelection: Binding<Set<Transcript>> {
        Binding(
            get: { multiSelection.count > 1 ? Set(multiSelection) : (selection.map { [$0] } ?? []) },
            set: { newValue in
                if newValue.count > 1 {
                    multiSelection = Array(newValue)
                    selection = nil
                } else {
                    multiSelection = []
                    selection = newValue.first
                }
            }
        )
    }

    private var filtered: [Transcript] {
        guard !filter.isEmpty else { return transcripts }
        return transcripts.filter { TextSearch.matches($0.title, query: filter) }
    }

    private struct TranscriptGroup: Identifiable {
        let group: SidebarGroup
        let items: [Transcript]
        var id: String { group.rawValue }
    }

    private var groups: [TranscriptGroup] {
        let now = Date()
        return SidebarGroup.allCases.compactMap { group in
            let items = filtered.filter { SidebarGroup.group(for: $0.createdAt, now: now) == group }
            return items.isEmpty ? nil : TranscriptGroup(group: group, items: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            newTranscriptionGroup
            listHeader
            list
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .confirmationDialog(
            "Radera ”\(transcriptToDelete?.title ?? "")”?",
            isPresented: Binding(get: { transcriptToDelete != nil }, set: { if !$0 { transcriptToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                if let transcript = transcriptToDelete {
                    if selection == transcript { selection = nil }
                    multiSelection.removeAll { $0 == transcript }
                    queue.delete(transcript)
                }
                transcriptToDelete = nil
            }
        } message: {
            Text(transcriptToDelete?.isRecording == true
                 ? "Texten och inspelningen raderas. Det går inte att ångra."
                 : "Texten och appens kopia av filen raderas. Originalfilen påverkas inte. Det går inte att ångra.")
        }
        .sheet(item: $transcriptToRetranscribe) { transcript in
            RetranscribeSheet(
                versionCount: transcript.versionCount,
                oldestDescription: transcript.oldestVersionDescription,
                onCancel: { transcriptToRetranscribe = nil },
                onConfirm: {
                    if let confirmation = RetranscribeConfirmation(replacingText: !transcript.segments.isEmpty, confirmed: true) {
                        queue.retranscribe(transcript, confirmation: confirmation)
                    }
                    transcriptToRetranscribe = nil
                }
            )
        }
        .onDeleteCommand {
            if multiSelection.count > 1 {
                appState.requestBulkDelete = true
            } else if let selection {
                transcriptToDelete = selection
            }
        }
    }

    /// Inställningarna och släppytan hör ihop (båda gäller nästa transkribering), så de ligger i samma ruta.
    private var newTranscriptionGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ny transkribering")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.leading, 2)
            modeSwitcher
            settingsButton
            dropArea
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.chip)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    /// Fil eller Mötesinspelning. Ligger överst i sidopanelen (inte i fönstrets verktygsfält), så
    /// att titelbaren är fri för det som hör till den öppnade texten.
    private var modeSwitcher: some View {
        Picker("Läge", selection: Binding(
            get: { appState.mode },
            set: { appState.mode = $0; appState.clearSelection() }
        )) {
            Text("Fil").tag(AppMode.file)
            Label("Mötesinspelning", systemImage: "circle")
                .labelStyle(RecordingDotLabelStyle(isRecording: recorder.isRecording))
                .tag(AppMode.meeting)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Fil: transkribera ljud- och videofiler. Mötesinspelning: spela in datorns ljud.")
    }

    /// Högst upp: modell och språk för nästa transkribering. Knappen öppnar inställningarna.
    private var settingsButton: some View {
        let model = WhisperModel.resolved(modelRaw)
        return Button { showsNextSettings.toggle() } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.displayName) · \(Language.displayName(for: language))")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(queue.transcriber.isDownloaded(model) ? "Finns på datorn" : "Laddas ner automatiskt första gången")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Inställningar för en ny transkribering: modell, språk, antal talare och ordlista")
        .popover(isPresented: $showsNextSettings, arrowEdge: .trailing) {
            NextTranscriptionSettingsForm()
        }
    }

    /// Släppyta med knappen Välj filer…. Hela fönstret tar emot filer; den här visar var.
    private var dropArea: some View {
        VStack(spacing: 8) {
            Image(systemName: appState.isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(appState.isDropTargeted ? Color.accentColor : Color.textSecondary)
            Text("Släpp ljud- eller videofiler här")
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Välj filer…") { appState.isImporterPresented = true }
                .help("Välj ljud- eller videofiler att transkribera (⌘O)")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    appState.isDropTargeted ? Color.accentColor : Color.textSecondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: appState.isDropTargeted ? 2 : 1, dash: appState.isDropTargeted ? [] : [6, 4])
                )
        }
    }

    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transkriberingar (\(transcripts.count))")
                .font(.headline)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.textSecondary)
                TextField("Sök på titel", text: $filter)
                    .textFieldStyle(.plain)
                if !filter.isEmpty {
                    Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.textSecondary)
                        .help("Rensa sökningen")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var list: some View {
        List(selection: listSelection) {
            if transcripts.isEmpty {
                Text("Inga transkriberingar än. Släpp en fil eller spela in ett möte så hamnar resultatet här.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)
            }

            ForEach(groups) { group in
                Section(group.group.rawValue) {
                    ForEach(group.items) { transcript in
                        SidebarRow(transcript: transcript, isCurrent: queue.currentTranscriptID == transcript.id)
                            .tag(transcript)
                            .contextMenu { menu(for: transcript) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.sidebarBackground)
    }

    /// Frågar först när något ska sparas eller raderas (se `RetranscribeDialog`).
    private func requestRetranscribe(_ transcript: Transcript) {
        let hasText = !transcript.segments.isEmpty
        if hasText, RetranscribeDialog.needsDialog(versionCount: transcript.versionCount, askSetting: askBeforeRetranscribe) {
            transcriptToRetranscribe = transcript
        } else if let confirmation = RetranscribeConfirmation(replacingText: hasText, confirmed: true) {
            queue.retranscribe(transcript, confirmation: confirmation)
        }
    }

    @ViewBuilder
    private func menu(for transcript: Transcript) -> some View {
        Button("Transkribera igen med nuvarande inställningar…") { requestRetranscribe(transcript) }
            .disabled(transcript.status == .transcribing || transcript.status == .queued)
        Button("Visa ljud-/videofilen i Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([transcript.mediaURL])
        }
        Divider()
        Button("Radera…", role: .destructive) { transcriptToDelete = transcript }
    }
}

private struct SidebarRow: View {
    let transcript: Transcript
    let isCurrent: Bool
    @Environment(TranscriptionQueue.self) private var queue

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(transcript.title)
                    .lineLimit(1)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Text(statusLabel.text)
                    .font(.caption)
                    .foregroundStyle(statusLabel.isWarning ? AnyShapeStyle(Color.warning) : AnyShapeStyle(Color.textSecondary))
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var icon: some View {
        switch transcript.status {
        case .transcribing where isCurrent:
            if let fraction = queue.transcriber.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
        case .queued, .transcribing:
            Image(systemName: "clock").foregroundStyle(Color.textSecondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
        case .completed:
            Image(systemName: transcript.isRecording ? "record.circle" : (transcript.isVideo ? "film" : "waveform"))
                .foregroundStyle(.tint)
        }
    }

    private var detail: String {
        let date = transcript.createdAt.formatted(date: .abbreviated, time: .shortened)
        return transcript.status == .completed
            ? "\(TimeFormatting.duration(transcript.duration)) · \(date)"
            : date
    }

    private var statusLabel: (text: String, isWarning: Bool) {
        switch transcript.status {
        case .completed: ("Klar", false)
        case .transcribing: ("Transkriberar", false)
        case .queued: ("I kö", false)
        case .failed: ("Misslyckades", true)
        }
    }
}

/// Rubrik i lägesväxlaren: en röd prick (7 pt) före texten medan det spelas in.
private struct RecordingDotLabelStyle: LabelStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            if isRecording {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                    .accessibilityLabel("Spelar in")
            }
            configuration.title
        }
    }
}

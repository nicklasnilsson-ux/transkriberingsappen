import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

struct SidebarView: View {
    @Binding var selection: Transcript?
    @Environment(TranscriptionQueue.self) private var queue
    @Environment(AppState.self) private var appState
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var filter = ""
    @State private var transcriptToDelete: Transcript?
    @State private var transcriptToRetranscribe: Transcript?

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
        List(selection: $selection) {
            Button {
                appState.isImporterPresented = true
            } label: {
                Label("Välj filer…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .help("Välj ljud- eller videofiler att transkribera (⌘O). Du kan också släppa dem var som helst i fönstret.")
            .listRowSeparator(.hidden)

            Text("Transkriberingar (\(transcripts.count))")
                .font(.headline)
                .padding(.top, 6)
                .selectionDisabled()

            if transcripts.isEmpty {
                Text("Inga transkriberingar än. Släpp en fil eller spela in ett möte så hamnar resultatet här.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        .searchable(text: $filter, placement: .sidebar, prompt: "Sök på titel")
        .safeAreaInset(edge: .bottom, spacing: 0) { modelFooter }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .confirmationDialog(
            "Radera ”\(transcriptToDelete?.title ?? "")”?",
            isPresented: Binding(get: { transcriptToDelete != nil }, set: { if !$0 { transcriptToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Radera", role: .destructive) {
                if let transcript = transcriptToDelete {
                    if selection == transcript { selection = nil }
                    queue.delete(transcript)
                }
                transcriptToDelete = nil
            }
        } message: {
            Text(transcriptToDelete?.isRecording == true
                 ? "Texten och inspelningen raderas. Det går inte att ångra."
                 : "Texten och appens kopia av filen raderas. Originalfilen påverkas inte. Det går inte att ångra.")
        }
        .confirmationDialog(
            "Transkribera ”\(transcriptToRetranscribe?.title ?? "")” igen?",
            isPresented: Binding(get: { transcriptToRetranscribe != nil }, set: { if !$0 { transcriptToRetranscribe = nil } }),
            titleVisibility: .visible
        ) {
            Button("Transkribera igen", role: .destructive) {
                if let transcript = transcriptToRetranscribe,
                   let confirmation = RetranscribeConfirmation(replacingText: !transcript.segments.isEmpty, confirmed: true) {
                    queue.retranscribe(transcript, confirmation: confirmation)
                }
                transcriptToRetranscribe = nil
            }
        } message: {
            Text(RetranscribeConfirmation.dialogMessage)
        }
        .onDeleteCommand {
            if let selection { transcriptToDelete = selection }
        }
    }

    /// Längst ner: modellen och språket som nästa transkribering använder.
    private var modelFooter: some View {
        let model = WhisperModel.resolved(modelRaw)
        return VStack(alignment: .leading, spacing: 2) {
            Divider()
            Text("\(model.displayName) · \(Language.displayName(for: language))")
                .font(.callout.weight(.medium))
                .padding(.top, 6)
            Text(queue.transcriber.isDownloaded(model) ? "Finns på datorn" : "Laddas ner automatiskt första gången")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Modell och språk för nästa transkribering. Ändras under Nästa transkribering eller i Inställningar.")
    }

    @ViewBuilder
    private func menu(for transcript: Transcript) -> some View {
        Button("Transkribera igen med nuvarande inställningar…") { transcriptToRetranscribe = transcript }
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(statusLabel.text)
                    .font(.caption)
                    .foregroundStyle(statusLabel.isWarning ? AnyShapeStyle(Color.warning) : AnyShapeStyle(.secondary))
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
            Image(systemName: "clock").foregroundStyle(.secondary)
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

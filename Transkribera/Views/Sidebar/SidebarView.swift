import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

struct SidebarView: View {
    @Binding var selection: Transcript?
    @Environment(TranscriptionQueue.self) private var queue
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var filter = ""
    @State private var transcriptToDelete: Transcript?

    private var filtered: [Transcript] {
        guard !filter.isEmpty else { return transcripts }
        return transcripts.filter { TextSearch.matches($0.title, query: filter) }
    }

    private struct TranscriptGroup: Identifiable {
        let title: String
        let items: [Transcript]
        var id: String { title }
    }

    private var groups: [TranscriptGroup] {
        let calendar = Calendar.current
        var today: [Transcript] = []
        var week: [Transcript] = []
        var older: [Transcript] = []
        for transcript in filtered {
            if calendar.isDateInToday(transcript.createdAt) {
                today.append(transcript)
            } else if let days = calendar.dateComponents([.day], from: transcript.createdAt, to: Date()).day, days < 7 {
                week.append(transcript)
            } else {
                older.append(transcript)
            }
        }
        return [
            TranscriptGroup(title: "Idag", items: today),
            TranscriptGroup(title: "Senaste veckan", items: week),
            TranscriptGroup(title: "Tidigare", items: older)
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        List(selection: $selection) {
            Button {
                selection = nil
            } label: {
                Label("Ny transkribering", systemImage: "plus.circle.fill")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.vertical, 4)

            if transcripts.isEmpty {
                Text("Dina transkriberingar hamnar här.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { transcript in
                        SidebarRow(transcript: transcript, isCurrent: queue.currentTranscriptID == transcript.id)
                            .tag(transcript)
                            .contextMenu { menu(for: transcript) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $filter, placement: .sidebar, prompt: "Filtrera")
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
            Text("Transkriberingen och den sparade mediefilen tas bort. Det går inte att ångra.")
        }
        .onDeleteCommand {
            if let selection { transcriptToDelete = selection }
        }
    }

    @ViewBuilder
    private func menu(for transcript: Transcript) -> some View {
        Button("Transkribera igen") { queue.retranscribe(transcript) }
            .disabled(transcript.status == .transcribing || transcript.status == .queued)
        Button("Visa mediefil i Finder") {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .completed:
            Image(systemName: transcript.isRecording ? "record.circle" : (transcript.isVideo ? "film" : "waveform"))
                .foregroundStyle(.tint)
        }
    }

    private var detail: String {
        let date = transcript.createdAt.formatted(date: .abbreviated, time: .shortened)
        switch transcript.status {
        case .queued: return "I kö · \(date)"
        case .transcribing: return "Transkriberar… · \(date)"
        case .failed: return transcript.errorMessage ?? "Misslyckades"
        case .completed: return "\(date) · \(TimeFormatting.duration(transcript.duration))"
        }
    }
}

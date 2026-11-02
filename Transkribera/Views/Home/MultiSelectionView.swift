import SwiftUI
import TranskriberaCore

/// Huvudytan när två eller fler transkriberingar är valda: listan, en varning och knapparna
/// Transkribera N igen, Exportera för analys och Radera N. Både omtagning och radering frågar först.
struct MultiSelectionView: View {
    let transcripts: [Transcript]
    @Environment(AppState.self) private var appState
    @Environment(TranscriptionQueue.self) private var queue
    @State private var confirmRetranscribe = false

    private var count: Int { transcripts.count }
    private var anyWorking: Bool {
        transcripts.contains { $0.status == .queued || $0.status == .transcribing }
    }
    private var anyText: Bool { transcripts.contains { !$0.segments.isEmpty } }
    /// De som redan har alla platser för versioner använda: deras äldsta version raderas.
    private var atCapacity: Int { transcripts.filter { $0.versionCount >= VersionHistory.capacity }.count }

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 16) {
            Text("\(count) transkriberingar valda")
                .font(.title2.weight(.semibold))

            List(transcripts) { transcript in
                HStack {
                    Text(transcript.title).lineLimit(1)
                    Spacer()
                    Text(transcript.status == .completed ? TimeFormatting.duration(transcript.duration) : "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)

            if anyText {
                Label(BulkRetranscribe.message(count: count, atCapacity: atCapacity),
                      systemImage: atCapacity > 0 ? "exclamationmark.triangle" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(atCapacity > 0 ? AnyShapeStyle(Color.warning) : AnyShapeStyle(.secondary))
            }

            HStack(spacing: 10) {
                Button(BulkRetranscribe.buttonTitle(count: count)) { confirmRetranscribe = true }
                    .disabled(anyWorking)
                    .help("Transkribera de valda igen med nuvarande inställningar. Den nuvarande versionen av varje text sparas.")
                Button("Exportera för analys…") { appState.isAnalysisExportPresented = true }
                    .help("Samla de valda i en fil för analys")
                Spacer()
                Button("Radera \(count)…", role: .destructive) { appState.requestBulkDelete = true }
                    .help("Radera de valda transkriberingarna")
            }
        }
        .padding(20)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .navigationTitle("\(count) valda")
        .confirmationDialog(BulkRetranscribe.title(count: count), isPresented: $confirmRetranscribe, titleVisibility: .visible) {
            Button("Transkribera \(count) igen", role: .destructive) {
                if let confirmation = RetranscribeConfirmation(replacingText: anyText, confirmed: true) {
                    queue.retranscribe(transcripts, confirmation: confirmation)
                }
            }
        } message: {
            Text(BulkRetranscribe.message(count: count, atCapacity: atCapacity))
        }
        .confirmationDialog(DeleteConfirmation.title(count: count), isPresented: $appState.requestBulkDelete, titleVisibility: .visible) {
            Button("Radera \(count)", role: .destructive) {
                if let confirmation = DeleteConfirmation(count: count, confirmed: true) {
                    let chosen = transcripts
                    appState.clearSelection()
                    queue.delete(chosen, confirmation: confirmation)
                }
            }
        } message: {
            Text(DeleteConfirmation.message(count: count))
        }
    }
}

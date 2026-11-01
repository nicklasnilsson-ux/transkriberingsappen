import SwiftData
import SwiftUI

/// Delat UI-tillstånd som menykommandon behöver kunna påverka.
@MainActor
@Observable
final class AppState {
    var isImporterPresented = false
    var isAnalysisExportPresented = false
    var selection: Transcript?
    /// En fil dras över fönstret (för att markera släppytan i sidopanelen).
    var isDropTargeted = false
    /// Fil eller Mötesinspelning. Gäller när ingen transkribering är vald.
    var mode: AppMode = .file
    /// Visas vid start om databasen inte kunde öppnas (se `Database`).
    var databaseProblem: String?
}

enum AppMode: String, CaseIterable, Identifiable {
    case file = "Fil"
    case meeting = "Mötesinspelning"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(TranscriptionQueue.self) private var queue
    @Environment(MeetingRecorder.self) private var recorder
    @State private var isTargeted = false

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView(selection: $appState.selection)
        } detail: {
            if let transcript = appState.selection {
                TranscriptDetailView(transcript: transcript)
                    .id(transcript.id)
            } else if appState.mode == .meeting {
                MeetingModeView { appState.selection = $0 }
            } else {
                FileModeEmptyView()
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Läge", selection: Binding(
                    get: { appState.mode },
                    set: { appState.mode = $0; appState.selection = nil }
                )) {
                    Text("Fil").tag(AppMode.file)
                    Label("Mötesinspelning", systemImage: "circle")
                        .labelStyle(RecordingDotLabelStyle(isRecording: recorder.isRecording))
                        .tag(AppMode.meeting)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .help("Fil: transkribera ljud- och videofiler. Mötesinspelning: spela in datorns ljud.")
            }
        }
        // Hela fönstret tar emot släppta filer.
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                if let transcript = await queue.importFiles(urls) {
                    appState.mode = .file
                    appState.selection = transcript
                }
            }
            return true
        } isTargeted: { isTargeted = $0; appState.isDropTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $appState.isAnalysisExportPresented) {
            AnalysisExportSheet(preselected: appState.selection)
        }
        .fileImporter(
            isPresented: $appState.isImporterPresented,
            allowedContentTypes: MediaStore.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                if let transcript = await queue.importFiles(urls) {
                    appState.selection = transcript
                }
            }
        }
        .alert(
            "Några filer kunde inte läggas till",
            isPresented: Binding(
                get: { queue.importError != nil },
                set: { if !$0 { queue.importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { queue.importError = nil }
        } message: {
            Text(queue.importError ?? "")
        }
        .alert(
            "Tidigare transkriberingar kunde inte läsas in",
            isPresented: Binding(
                get: { appState.databaseProblem != nil },
                set: { if !$0 { appState.databaseProblem = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appState.databaseProblem = nil }
        } message: {
            Text(appState.databaseProblem ?? "")
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

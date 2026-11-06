import SwiftData
import SwiftUI
import TranskriberaCore

/// Delat UI-tillstånd som menykommandon behöver kunna påverka.
@MainActor
@Observable
final class AppState {
    var isImporterPresented = false
    var isAnalysisExportPresented = false
    var selection: Transcript?
    /// Två eller fler valda i sidopanelen (⌘- eller ⇧-klick). Tom när högst en är vald.
    var multiSelection: [Transcript] = []
    /// Delete-tangenten eller knappen Radera N: visa bekräftelsen i flervalsvyn.
    var requestBulkDelete = false
    /// En fil dras över fönstret (för att markera släppytan i sidopanelen).
    var isDropTargeted = false
    /// Fil eller Mötesinspelning. Gäller när ingen transkribering är vald.
    var mode: AppMode = .file
    /// Visas vid start om databasen inte kunde öppnas (se `Database`).
    var databaseProblem: String?

    /// Allt som är valt, en eller flera.
    var selectedTranscripts: [Transcript] {
        multiSelection.isEmpty ? (selection.map { [$0] } ?? []) : multiSelection
    }

    func clearSelection() {
        selection = nil
        multiSelection = []
    }
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

    /// Importerar och visar den första nya filen. Under en mötesinspelning visas ingenting nytt
    /// (Stoppa-knappen finns i mötesläget) och filerna väntar i kön tills inspelningen är sparad.
    private func importAndShow(_ urls: [URL]) async {
        let navigate = ImportNavigation.shouldNavigate(recordingBusy: recorder.isBusy)
        guard let transcript = await queue.importFiles(urls), navigate,
              ImportNavigation.shouldNavigate(recordingBusy: recorder.isBusy) else { return }
        appState.mode = .file
        appState.selection = transcript
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView(selection: $appState.selection, multiSelection: $appState.multiSelection)
        } detail: {
            if appState.multiSelection.count > 1 {
                MultiSelectionView(transcripts: appState.multiSelection)
            } else if let transcript = appState.selection {
                TranscriptDetailView(transcript: transcript)
                    .id(transcript.id)
            } else if appState.mode == .meeting {
                MeetingModeView()
            } else {
                FileModeEmptyView()
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        // Appens egen vita palett i stället för systemets bakgrunder (se Theme.swift).
        .background(Color.appBackground)
        .foregroundStyle(Color.textPrimary)
        // macOS-standard: ⌘-klick avmarkerar en rad i listan, Esc avmarkerar allt och tömmer vyn.
        .onExitCommand { appState.clearSelection() }
        // Hela fönstret tar emot släppta filer.
        .dropDestination(for: URL.self) { urls, _ in
            Task { await importAndShow(urls) }
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
            AnalysisExportSheet(preselected: appState.selectedTranscripts)
                .font(.app(.regular))
        }
        .fileImporter(
            isPresented: $appState.isImporterPresented,
            allowedContentTypes: MediaStore.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await importAndShow(urls) }
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

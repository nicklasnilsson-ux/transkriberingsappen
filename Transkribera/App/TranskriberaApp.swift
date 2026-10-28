import SwiftData
import SwiftUI

@main
struct TranskriberaApp: App {
    private let container: ModelContainer
    @State private var appState = AppState()
    @State private var queue: TranscriptionQueue
    @State private var recorder = MeetingRecorder()
    @StateObject private var updater = AppUpdater()

    init() {
        let schema = Schema([Transcript.self, TranscriptSegment.self])
        let url = AppPaths.supportDirectory.appending(path: "Transkribera.store")
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        } catch {
            fatalError("Kunde inte öppna databasen: \(error)")
        }
        let queue = TranscriptionQueue(transcriber: TranscriberService(), context: container.mainContext)
        _queue = State(initialValue: queue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(queue)
                .environment(recorder)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Ny transkribering") { appState.selection = nil }
                    .keyboardShortcut("n")
                Button("Öppna filer…") { appState.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .importExport) {
                Button("Exportera för analys…") { appState.isAnalysisExportPresented = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(queue)
                .environmentObject(updater)
        }
    }
}

/// Menyvalet "Sök efter uppdateringar…" i appmenyn.
private struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button("Sök efter uppdateringar…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

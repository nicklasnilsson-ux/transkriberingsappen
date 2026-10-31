import SwiftData
import SwiftUI

@main
struct TranskriberaApp: App {
    private let container: ModelContainer
    @State private var appState: AppState
    @State private var queue: TranscriptionQueue
    @State private var recorder = MeetingRecorder()
    @State private var lab = TestLab()
    @StateObject private var updater = AppUpdater()

    init() {
        SpeakerCountSetting.migrate()
        // Kraschar aldrig: en databas som inte går att öppna sparas undan (se Database).
        let database = Database.open()
        container = database.container
        let appState = AppState()
        appState.databaseProblem = database.problem
        _appState = State(initialValue: appState)
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
            CommandGroup(after: .help) {
                TestLabMenuButton()
            }
        }

        Window("Testlabb", id: TestLabMenuButton.windowID) {
            TestLabView()
                .environment(queue)
                .environment(lab)
        }
        .modelContainer(container)

        Settings {
            SettingsView()
                .environment(queue)
                .environmentObject(updater)
        }
    }
}

/// Menyvalet "Testlabb…" i Hjälp-menyn. Ett verktyg för att jämföra inställningar,
/// inte för vanlig användning, därför inte i Arkiv-menyn.
private struct TestLabMenuButton: View {
    static let windowID = "testlab"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Testlabb…") { openWindow(id: Self.windowID) }
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

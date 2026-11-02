import SwiftData
import SwiftUI
import TranskriberaCore

@main
struct TranskriberaApp: App {
    private let container: ModelContainer
    @State private var appState: AppState
    @State private var queue: TranscriptionQueue
    @State private var recorder = MeetingRecorder()
    @State private var lab = TestLab()
    @StateObject private var updater = AppUpdater()
    @AppStorage(SettingsKey.readingTextSize) private var readingSize = ReadingTextSize.standard

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
                .background(TestLabShortcut())
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Ny transkribering") {
                    appState.mode = .file
                    appState.clearSelection()
                }
                    .keyboardShortcut("n")
                Button("Öppna filer…") { appState.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .importExport) {
                Button("Exportera för analys…") { appState.isAnalysisExportPresented = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Större text") { readingSize = ReadingTextSize.larger(than: readingSize) }
                    .keyboardShortcut("+")
                    .disabled(ReadingTextSize.clamped(readingSize) == ReadingTextSize.steps.last)
                Button("Mindre text") { readingSize = ReadingTextSize.smaller(than: readingSize) }
                    .keyboardShortcut("-")
                    .disabled(ReadingTextSize.clamped(readingSize) == ReadingTextSize.steps.first)
                Button("Normal storlek") { readingSize = ReadingTextSize.standard }
                    .keyboardShortcut("0")
            }
        }

        Window("Testlabb", id: TestLabShortcut.windowID) {
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

/// Testlabbet är ett verktyg för att jämföra inställningar, inte för vanlig användning,
/// därför finns det inte i någon meny. Det öppnas med den dolda genvägen ⌥⇧⌘T.
/// Kontrolleras av scripts/test_testlab_hidden.py.
private struct TestLabShortcut: View {
    static let windowID = "testlab"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("") { openWindow(id: Self.windowID) }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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

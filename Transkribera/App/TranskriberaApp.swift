import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

@main
struct TranskriberaApp: App {
    private let container: ModelContainer
    @State private var appState: AppState
    @State private var queue: TranscriptionQueue
    @State private var recorder: MeetingRecorder
    @State private var lab = TestLab()
    @StateObject private var updater = AppUpdater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        // Filer som släpps under en mötesinspelning väntar tills inspelningen är sparad.
        let recorder = MeetingRecorder()
        recorder.onBusyChange = { [weak queue] busy in queue?.setRecordingBusy(busy) }
        _recorder = State(initialValue: recorder)
    }

    var body: some Scene {
        // Ett enda huvudfönster. Det kan stängas och öppnas igen (Dock, Fönster-menyn, Arkiv-menyn).
        Window("Transkribera", id: MainWindow.id) {
            ContentView()
                .environment(appState)
                .environment(queue)
                .environment(recorder)
                .background(TestLabShortcut(container: container, queue: queue, lab: lab))
                .background(MainWindowReopener(delegate: appDelegate))
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                ShowMainWindowButton()
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

        Settings {
            SettingsView()
                .environment(queue)
                .environmentObject(updater)
        }
    }
}

enum MainWindow {
    static let id = "main"
}

/// Dock-klicket på en app utan öppet fönster ska öppna huvudfönstret igen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sätts av huvudfönstret medan det finns; öppnar fönstret igen när det är stängt.
    var reopenMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, let reopen = reopenMainWindow else { return true }
        reopen()
        return false
    }
}

private struct MainWindowReopener: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { delegate.reopenMainWindow = { openWindow(id: MainWindow.id) } }
    }
}

/// Arkiv-menyn: öppnar huvudfönstret om det har stängts (annars hamnar det överst).
private struct ShowMainWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Visa huvudfönstret") { openWindow(id: MainWindow.id) }
    }
}

/// Testlabbet är ett verktyg för att jämföra inställningar, inte för vanlig användning,
/// därför finns det inte i någon meny, inte heller i Fönster-menyn. Det är därför ett eget
/// AppKit-fönster och inte en `Window`-scen (en sådan listas alltid i Fönster-menyn).
/// Det öppnas med den dolda genvägen ⌥⇧⌘T. Kontrolleras av scripts/test_testlab_hidden.py.
private struct TestLabShortcut: View {
    let container: ModelContainer
    let queue: TranscriptionQueue
    let lab: TestLab

    var body: some View {
        Button("") { TestLabWindow.show(container: container, queue: queue, lab: lab) }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

@MainActor
private enum TestLabWindow {
    private static var window: NSWindow?

    static func show(container: ModelContainer, queue: TranscriptionQueue, lab: TestLab) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = TestLabView()
            .environment(queue)
            .environment(lab)
            .modelContainer(container)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Testlabb"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
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

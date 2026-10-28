import SwiftData
import SwiftUI

@main
struct TranskriberaApp: App {
    private let container: ModelContainer
    @State private var appState = AppState()
    @State private var queue: TranscriptionQueue
    @State private var recorder = MeetingRecorder()

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
        }
    }
}

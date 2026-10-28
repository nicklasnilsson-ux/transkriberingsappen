import SwiftData
import SwiftUI

/// Delat UI-tillstånd som menykommandon behöver kunna påverka.
@MainActor
@Observable
final class AppState {
    var isImporterPresented = false
    var selection: Transcript?
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(TranscriptionQueue.self) private var queue
    @State private var isTargeted = false

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView(selection: $appState.selection)
        } detail: {
            if let transcript = appState.selection {
                TranscriptDetailView(transcript: transcript)
                    .id(transcript.id)
            } else {
                NewTranscriptionView { appState.selection = $0 }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
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
            "Import misslyckades",
            isPresented: Binding(
                get: { queue.importError != nil },
                set: { if !$0 { queue.importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { queue.importError = nil }
        } message: {
            Text(queue.importError ?? "")
        }
    }
}

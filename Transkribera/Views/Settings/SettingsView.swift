import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TranscriptionSettingsView()
                .tabItem { Label("Transkribering", systemImage: "waveform") }
            ModelSettingsView()
                .tabItem { Label("Modeller", systemImage: "cpu") }
        }
        .frame(width: 520)
        .padding(20)
    }
}

private struct TranscriptionSettingsView: View {
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.task) private var task = "transcribe"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.wordTimestamps) private var wordTimestamps = true
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true

    var body: some View {
        Form {
            Section {
                Picker("Språk", selection: $language) {
                    ForEach(Language.all) { language in
                        Text(language.name).tag(language.id)
                    }
                }
                Picker("Resultat", selection: $task) {
                    Text("Text på originalspråket").tag("transcribe")
                    Text("Översätt till engelska").tag("translate")
                }
            } footer: {
                Text("Välj språket som talas. Automatiskt fungerar oftast, men ett angivet språk ger säkrare resultat. Inställningarna gäller nya transkriberingar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
            } footer: {
                Text("Märker texten med Talare 1, Talare 2 … som du kan byta namn på. Laddar ner en extra modell (cirka 30 MB) första gången och tar lite längre tid.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Tidsstämplar per ord", isOn: $wordTimestamps)
            } footer: {
                Text("Gör att ordet som spelas upp markeras i texten och att långa undertexter delas upp bättre vid export.")
                    .foregroundStyle(.secondary)
            }

            if MeetingRecorder.supportsMicrophone {
                Section {
                    Toggle("Spela även in min mikrofon", isOn: $recordMicrophone)
                } header: {
                    Text("Mötesinspelning")
                } footer: {
                    Text("Ta med din egen röst. Annars spelas bara datorns ljud in, alltså de andra deltagarna.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelSettingsView: View {
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @Environment(TranscriptionQueue.self) private var queue
    @State private var refresh = 0

    var body: some View {
        let transcriber = queue.transcriber
        Form {
            Section {
                Picker("Modell", selection: $modelRaw) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
            } footer: {
                Text("Större modeller ger bättre text men tar längre tid och mer plats. Modellen laddas ner automatiskt första gången den används.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(WhisperModel.allCases) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            Text(model.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if transcriber.isDownloaded(model) {
                            Label("Nedladdad", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.green)
                                .help("Finns på datorn")
                            Button("Ta bort", role: .destructive) {
                                transcriber.deleteDownloadedModel(model)
                                refresh += 1
                            }
                            .disabled(transcriber.isBusy)
                            .help("Frigör utrymme. Modellen laddas ner igen om du använder den.")
                        } else {
                            Button("Ladda ner") {
                                Task {
                                    _ = try? await transcriber.prepare(model: model)
                                    refresh += 1
                                }
                            }
                            .disabled(transcriber.isBusy)
                            .help("Hämta modellen nu så att den är redo direkt")
                        }
                    }
                }
                .id(refresh)

                if transcriber.isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(transcriber.statusText).font(.caption)
                    }
                }
            } header: {
                Text("Modeller")
            } footer: {
                Text("Modellerna sparas på din Mac. Ta bort dem du inte använder för att frigöra utrymme.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Visa modellmappen i Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.modelsDirectory])
                }
            }
        }
        .formStyle(.grouped)
    }
}

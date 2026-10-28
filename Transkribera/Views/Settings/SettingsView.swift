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
    @State private var showsGuide = false

    var body: some View {
        let transcriber = queue.transcriber
        Form {
            Section {
                LabeledContent("Modell") {
                    ModelPicker(selection: $modelRaw)
                        .frame(maxWidth: 260)
                }
                Button("Vilken modell ska jag välja?") { showsGuide = true }
                    .help("Jämförelse av modellerna och råd om när du ska välja vilken")
                    .sheet(isPresented: $showsGuide) {
                        VStack(spacing: 0) {
                            ModelGuideView()
                            Divider()
                            HStack {
                                Spacer()
                                Button("Klar") { showsGuide = false }
                                    .keyboardShortcut(.defaultAction)
                            }
                            .padding(12)
                        }
                    }
            } footer: {
                Text("KB-modellerna är bäst på svenska. Välj en OpenAI-modell för andra språk. Modellen laddas ner automatiskt första gången den används.")
                    .foregroundStyle(.secondary)
            }

            ForEach(WhisperModel.Family.allCases) { family in
                Section {
                    ForEach(family.models) { model in
                        HStack(alignment: .top, spacing: 12) {
                            ModelInfoRow(model: model, isDownloaded: transcriber.isDownloaded(model))
                            if transcriber.isDownloaded(model) {
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
                } header: {
                    Text(family.title)
                }
            }

            Section {
                if transcriber.isBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(transcriber.statusText).font(.caption)
                    }
                }
                Button("Visa modellmappen i Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.modelsDirectory])
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modellerna sparas på din Mac. Ta bort dem du inte använder för att frigöra utrymme.")
                        .foregroundStyle(.secondary)
                    ModelSourceNote()
                }
            }
        }
        .formStyle(.grouped)
    }
}

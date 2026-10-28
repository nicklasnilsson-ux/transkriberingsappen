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
            Picker("Språk", selection: $language) {
                ForEach(Language.all) { language in
                    Text(language.name).tag(language.id)
                }
            }
            Picker("Uppgift", selection: $task) {
                Text("Transkribera (samma språk)").tag("transcribe")
                Text("Översätt till engelska").tag("translate")
            }
            Toggle("Identifiera talare (SpeakerKit)", isOn: $identifySpeakers)
            Text("Laddar ner en extra modell (~30 MB) första gången och tar lite längre tid.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Tidsstämplar per ord", isOn: $wordTimestamps)
            Text("Behövs för att markera ordet som spelas upp och för att dela långa undertexter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if MeetingRecorder.supportsMicrophone {
                Toggle("Spela in mikrofonen vid mötesinspelning", isOn: $recordMicrophone)
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
            Picker("Standardmodell", selection: $modelRaw) {
                ForEach(WhisperModel.allCases) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }

            Section("Modeller på den här datorn") {
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
                            Button("Radera", role: .destructive) {
                                transcriber.deleteDownloadedModel(model)
                                refresh += 1
                            }
                            .disabled(transcriber.isBusy)
                        } else {
                            Button("Ladda ner") {
                                Task {
                                    try? await transcriber.prepare(model: model)
                                    refresh += 1
                                }
                            }
                            .disabled(transcriber.isBusy)
                        }
                    }
                }
                .id(refresh)
            }

            if transcriber.isBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(transcriber.statusText).font(.caption)
                }
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

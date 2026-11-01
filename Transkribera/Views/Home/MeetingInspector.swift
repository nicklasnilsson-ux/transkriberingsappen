import SwiftUI
import TranskriberaCore

/// Högerpanelen i Mötesinspelning: mikrofon och inställningarna som inspelningen transkriberas med.
struct MeetingInspector: View {
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.speakers) private var speakers = SpeakerCount.automatic.rawValue
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""
    @Environment(MeetingRecorder.self) private var recorder

    var body: some View {
        Form {
            if MeetingRecorder.supportsMicrophone {
                Section("Inspelning") {
                    Toggle("Spela även in min mikrofon", isOn: $recordMicrophone)
                        .disabled(recorder.isBusy)
                        .help("Ta med din egen röst. Annars spelas bara datorns ljud in, alltså de andra deltagarna.")
                }
            }
            Section("Transkriberas med") {
                LabeledContent("Modell") {
                    ModelPicker(selection: $modelRaw)
                }
                Picker("Språk", selection: $language) {
                    ForEach(Language.all) { Text($0.name).tag($0.id) }
                }
                .help("Språket som talas. Ett angivet språk ger oftast säkrare resultat än automatiskt.")
                Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
                    .help("Märker texten med Talare 1, Talare 2 … som du sedan kan byta namn på. Tar lite längre tid.")
                if identifySpeakers {
                    LabeledContent("Antal talare") {
                        SpeakerCountPicker(selection: $speakers).labelsHidden().fixedSize()
                    }
                }
                TextField("Ordlista", text: $vocabulary, prompt: Text("Namn och fackord, t.ex. TG, Fortnox"))
                    .help("Ord som förekommer i inspelningen, med komma emellan. Hjälper modellen att stava dem rätt.")
            }
            Section {
                SettingsLink { Text("Fler inställningar…") }
                    .buttonStyle(.link)
                    .help("Öppna alla inställningar, t.ex. översättning och nedladdade modeller")
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
    }
}

import SwiftUI
import TranskriberaCore

/// Fil-läge utan vald transkribering: bara en tom vy.
/// Inställningarna för nästa transkribering finns bara i sidopanelens inställningskort (Nicklas 2026-11-05).
/// Här låg tidigare en rad med väljare som trycktes ihop och bröts mitt i orden när fönstret var smalt.
/// Filer släpps var som helst i fönstret (se ContentView), därför ingen egen släppyta här.
struct FileModeEmptyView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Ingen transkribering vald", icon: .waveform)
        } description: {
            Text("Släpp ljud- eller videofiler i fönstret, eller välj Välj filer… i sidopanelen. Allt transkriberas lokalt, inget lämnar din Mac.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Ny transkribering")
    }
}

/// Inställningarna för nästa transkribering (fil och mötesinspelning) som ett formulär, för popovern i sidopanelen.
/// Det enda stället där de ändras, förutom appens Inställningar… (⌘,).
struct NextTranscriptionSettingsForm: View {
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.speakers) private var speakers = SpeakerCount.automatic.rawValue
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""
    @Environment(TranscriptionQueue.self) private var queue

    var body: some View {
        let model = WhisperModel.resolved(modelRaw)
        VStack(alignment: .leading, spacing: 12) {
            Text("Ny transkribering").font(.app(.large, weight: .semibold))
            LabeledContent("Modell") { ModelPicker(selection: $modelRaw).frame(width: 240) }
            Text(queue.transcriber.isDownloaded(model) ? "Finns på datorn" : "Laddas ner automatiskt första gången")
                .font(.app(.small))
                .foregroundStyle(Color.textSecondary)
            Picker("Språk", selection: $language) {
                ForEach(Language.all) { Text($0.name).tag($0.id) }
            }
            .help("Språket som talas. Ett angivet språk ger oftast säkrare resultat än automatiskt.")
            Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
                .help("Märker texten med Talare 1, Talare 2 … som du sedan kan byta namn på. Tar lite längre tid.")
            if identifySpeakers {
                SpeakerCountPicker(selection: $speakers)
            }
            TextField("Ordlista", text: $vocabulary, prompt: Text("Namn och fackord, t.ex. TG, Fortnox"))
                .help("Ord som förekommer i inspelningen, med komma emellan. Hjälper modellen att stava dem rätt.")
            Divider()
            SettingsLink { Text("Fler inställningar…") }
                .buttonStyle(.link)
                .help("Öppna alla inställningar, t.ex. översättning och nedladdade modeller")
        }
        .frame(width: 340)
        .padding(16)
    }
}

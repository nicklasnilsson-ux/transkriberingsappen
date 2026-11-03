import SwiftUI
import TranskriberaCore

/// Fil-läge utan vald transkribering: chips för nästa transkribering och en tom vy.
/// Filer släpps var som helst i fönstret (se ContentView), därför ingen egen släppyta här.
struct FileModeEmptyView: View {
    var body: some View {
        VStack(spacing: 0) {
            NextTranscriptionChips()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ContentUnavailableView {
                Label("Ingen transkribering vald", systemImage: "waveform")
            } description: {
                Text("Släpp ljud- eller videofiler i fönstret, eller välj Välj filer… i sidopanelen. Allt transkriberas lokalt, inget lämnar din Mac.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Raden med inställningar sitter kloss i toppen, resten av ytan är den tomma vyn.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Ny transkribering")
    }
}

/// Inställningarna för nästa transkribering som chips. Varje chip öppnar en popover.
struct NextTranscriptionChips: View {
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.speakers) private var speakers = SpeakerCount.automatic.rawValue
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("Ny transkribering:")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
            chip("Modell", value: WhisperModel.resolved(modelRaw).displayName) {
                ModelPicker(selection: $modelRaw).frame(width: 260)
            }
            chip("Språk", value: Language.displayName(for: language)) {
                Picker("Språk", selection: $language) {
                    ForEach(Language.all) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(width: 240)
                .help("Språket som talas. Ett angivet språk ger oftast säkrare resultat än automatiskt.")
            }
            chip("Talare", value: identifySpeakers ? "Skiljs åt" : "Av") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
                        .help("Märker texten med Talare 1, Talare 2 … som du sedan kan byta namn på. Tar lite längre tid.")
                    if identifySpeakers {
                        SpeakerCountPicker(selection: $speakers).labelsHidden().fixedSize()
                    }
                }
            }
            chip("Ordlista", value: vocabulary.isEmpty ? "Tom" : "Ifylld") {
                TextField("Namn och fackord, t.ex. TG, bruttovinst, Fortnox", text: $vocabulary)
                    .frame(width: 280)
                    .help("Ord som förekommer i inspelningen, med komma emellan. Hjälper modellen att stava dem rätt.")
            }
            Spacer()
            SettingsLink { Text("Fler inställningar…") }
                .buttonStyle(.link)
                .help("Öppna alla inställningar, t.ex. översättning och nedladdade modeller")
        }
    }

    private func chip<Content: View>(_ title: String, value: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        ChipButton(title: title, value: value, content: content)
    }
}

private struct ChipButton<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(Color.textSecondary)
                Text(value).fontWeight(.medium)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Color.textSecondary)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Ändra \(title.lowercased()) för en ny transkribering")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            content().padding(16)
        }
    }
}

/// Inställningarna för nästa transkribering som ett formulär, för popovern i sidopanelen.
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
            Text("Ny transkribering").font(.headline)
            LabeledContent("Modell") { ModelPicker(selection: $modelRaw).frame(width: 240) }
            Text(queue.transcriber.isDownloaded(model) ? "Finns på datorn" : "Laddas ner automatiskt första gången")
                .font(.caption)
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

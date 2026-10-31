import SwiftUI
import TranskriberaCore

/// Startvyn: släpp filer, välj fil eller starta en mötesinspelning.
struct NewTranscriptionView: View {
    var onCreated: (Transcript) -> Void

    @Environment(TranscriptionQueue.self) private var queue
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                dropZone
                QuickSettingsView()
                    .frame(maxWidth: 560)
                RecordingPanel(onCreated: onCreated)
                    .frame(maxWidth: 560)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Ny transkribering")
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "waveform.badge.plus")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: isTargeted)
            Text("Släpp ljud- eller videofiler här")
                .font(.title2.weight(.semibold))
            Text("Till exempel MP3, M4A, WAV, MP4 eller MOV. Allt transkriberas lokalt – inget lämnar din Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                appState.isImporterPresented = true
            } label: {
                Label("Välj filer…", systemImage: "folder")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Välj en eller flera filer att transkribera")
        }
        .padding(40)
        .frame(maxWidth: 560, minHeight: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [] : [8, 6])
                )
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.spring(duration: 0.25), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            Task {
                if let transcript = await queue.importFiles(urls) {
                    onCreated(transcript)
                }
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// Snabbval för modell, språk och talare direkt på startsidan.
/// Gäller både filer och mötesinspelningar som startas härifrån.
struct QuickSettingsView: View {
    @AppStorage(SettingsKey.model) private var modelRaw = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var language = "sv"
    @AppStorage(SettingsKey.identifySpeakers) private var identifySpeakers = false
    @AppStorage(SettingsKey.speakers) private var speakers = SpeakerCount.automatic.rawValue
    @AppStorage(SettingsKey.vocabulary) private var vocabulary = ""
    @Environment(TranscriptionQueue.self) private var queue

    var body: some View {
        let transcriber = queue.transcriber
        let model = WhisperModel.resolved(modelRaw)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inställningar")
                    .font(.headline)
                Spacer()
                SettingsLink {
                    Text("Fler inställningar…")
                }
                .buttonStyle(.link)
                .help("Öppna alla inställningar, t.ex. översättning och nedladdade modeller")
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Modell").foregroundStyle(.secondary)
                    ModelPicker(selection: $modelRaw)
                        .frame(maxWidth: 280)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transcriber.isDownloaded(model)
                             ? "\(model.summary) · Finns på datorn"
                             : "\(model.summary) · Laddas ner automatiskt första gången")
                        if model.isSwedishOnly && language != "sv" {
                            Label("KB-modellerna är tränade för svenska. Välj en OpenAI-modell för andra språk.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420, alignment: .leading)
                }
                GridRow {
                    Text("Språk").foregroundStyle(.secondary)
                    Picker("Språk", selection: $language) {
                        ForEach(Language.all) { language in
                            Text(language.name).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .help("Språket som talas. Ett angivet språk ger oftast säkrare resultat än automatiskt.")
                }
                GridRow {
                    Text("Talare").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Toggle("Skilj på vem som pratar", isOn: $identifySpeakers)
                            .help("Märker texten med Talare 1, Talare 2 … som du sedan kan byta namn på. Tar lite längre tid.")
                        if identifySpeakers {
                            SpeakerCountPicker(selection: $speakers)
                                .labelsHidden()
                                .fixedSize()
                        }
                    }
                }
                GridRow {
                    Text("Ordlista").foregroundStyle(.secondary)
                    TextField("Namn och fackord, t.ex. TG, bruttovinst, Fortnox", text: $vocabulary)
                        .frame(maxWidth: 280)
                        .help("Ord som förekommer i inspelningen, med komma emellan. Hjälper modellen att stava dem rätt.")
                }
            }

            if transcriber.isBusy || transcriber.phase != .idle {
                HStack(spacing: 8) {
                    if transcriber.isBusy { ProgressView().controlSize(.small) }
                    Text(transcriber.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

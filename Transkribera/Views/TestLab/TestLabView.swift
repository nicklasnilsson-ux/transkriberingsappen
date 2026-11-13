import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore
import UniformTypeIdentifiers

/// Fönstret för Testlabbet (öppnas med ⌥⇧⌘T, finns inte i någon meny): välj en eller flera inspelningar
/// och vilka inställningar som ska provas, och få en text per körning i en mapp per inspelning.
struct TestLabView: View {
    @Environment(TestLab.self) private var lab
    @Environment(TranscriptionQueue.self) private var queue
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var chosenIDs = Set<UUID>()

    private var runnable: [Transcript] { transcripts.filter(TestLab.canRun) }
    /// De valda inspelningarna, i listans ordning.
    private var chosen: [Transcript] { runnable.filter { chosenIDs.contains($0.id) } }

    var body: some View {
        @Bindable var lab = lab
        Form {
            Section {
                ForEach(runnable) { transcript in
                    Toggle("\(transcript.title) (\(Int(transcript.duration / 60)) min)", isOn: Binding(
                        get: { chosenIDs.contains(transcript.id) },
                        set: { isOn in
                            if isOn { chosenIDs.insert(transcript.id) } else { chosenIDs.remove(transcript.id) }
                        }
                    ))
                    .disabled(lab.isRunning)
                    if chosenIDs.contains(transcript.id) {
                        facitRow(for: transcript)
                    }
                }
            } header: {
                Text(chosen.isEmpty ? "Inspelningar" : "Inspelningar (\(chosen.count) valda)")
            } footer: {
                Text("Facit är valfritt: en textfil med samma samtal, till exempel exporten från Klang. Med facit räknar labbet ut ordträff och fel som ändrar innebörden, och hur många av dem som markerades. Resultatet hamnar i \"jämförelse med facit.txt\".")
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                Picker("Lista", selection: $lab.kind) {
                    ForEach(TestLabPlan.Kind.offered) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .disabled(lab.isRunning)
            } footer: {
                Text(footer)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Körningar") {
                ForEach(lab.plan) { run in
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(isOn: binding(for: run, in: $lab.selected)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title)
                                Text(run.differences.isEmpty ? "som i dag" : run.differences.joined(separator: ", "))
                                    .font(.app(.small))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .disabled(lab.isRunning)
                        Spacer()
                        StatusLabel(status: lab.statuses[run.id])
                    }
                }
            }

            Section {
                if !chosen.isEmpty {
                    LabeledContent("Uppskattad tid", value: estimate(for: chosen))
                }
                if lab.isRunning {
                    HStack(alignment: .firstTextBaseline) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lab.stepText)
                            // Vad som händer just nu: nedladdning, första inläsningen eller
                            // transkriberingen. Utan raden såg en lång nedladdning ut som ett stopp.
                            if queue.transcriber.phase != .idle {
                                Text(queue.transcriber.statusText)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
                if let message = lab.message {
                    Text(message).foregroundStyle(Color.textSecondary)
                }
                HStack {
                    if lab.folder != nil {
                        Button("Visa i Finder") {
                            if let folder = lab.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                    }
                    Spacer()
                    if lab.isRunning {
                        Button("Avbryt", role: .cancel) { lab.cancel() }
                    } else {
                        Button("Starta") {
                            lab.start(transcripts: chosen, queue: queue)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen.isEmpty || lab.selected.isEmpty)
                    }
                }
            } footer: {
                Text("Datorn hålls vaken medan labbet kör. Låt den stå på laddning.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 640)
    }

    /// Facit för en vald inspelning: filnamnet, eller en knapp för att välja.
    private func facitRow(for transcript: Transcript) -> some View {
        HStack {
            if let url = lab.facits[transcript.id] {
                Text("Facit: \(url.lastPathComponent)")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("Ta bort") { lab.facits[transcript.id] = nil }
            } else {
                Text("Inget facit")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("Välj facit…") { chooseFacit(for: transcript) }
            }
        }
        .font(.app(.small))
        .padding(.leading, 20)
        .disabled(lab.isRunning)
    }

    private func chooseFacit(for transcript: Transcript) {
        let panel = NSOpenPanel()
        panel.title = "Facit för \(transcript.title)"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            lab.facits[transcript.id] = url
        }
    }

    private var footer: String {
        let common = "Varje körning sparas som en textfil (som Exportera för analys) och en logg utan text. Vanliga transkriberingar påverkas inte, men nya filer väntar i kön tills labbet är klart."
        switch lab.kind {
        case .precision:
            return "Varje vald inspelning körs med Pianissimo i 8 bitar (som i dag), 16 och 32 bitar. Allt annat är som dina vanliga inställningar, och talarna är desamma i alla tre. 16 och 32 bitar laddas ner första gången (1,2 och 2,4 GB). " + common
        case .crossCheck:
            return "Varje vald inspelning körs med Pianissimo som vanligt, och KB Large ordagrann lyssnar en gång till. Där de hörde olika i ett ord som ändrar innebörden (inte, bör, måste …) hamnar stället i filen som slutar på -ord-att-lyssna-pa.txt, med tid, talare och båda tolkningarna. Gå igenom listan med ljudet och notera vem som hade rätt. KB Large tar cirka en fjärdedel av inspelningens längd. " + common
        case .timing:
            return "Mäter hur lång tid hela kedjan tar med varje modell, med och utan talare: ljudet, transkriberingen, talarna och anonymiseringen, var för sig. Modeller som saknas laddas ner först, och den tiden räknas för sig. Övriga inställningar är dina vanliga. Sammanfattningen visar också tiden per timme ljud och vilken Mac den kördes på. " + common
        }
    }

    private func binding(for run: TestLabRun, in selected: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { selected.wrappedValue.contains(run.id) },
            set: { isOn in
                if isOn { selected.wrappedValue.insert(run.id) } else { selected.wrappedValue.remove(run.id) }
            }
        )
    }

    /// Grov uppskattning: KB Large tar ungefär en fjärdedel av inspelningens längd per
    /// körning, Pianissimo en femtondel. Large v3 Turbo och Pianissimo i 16/32 bitar är inte
    /// uppmätta; deras andelar är gissningar. Korskollen kör KB Large en gång till. Talarna en gång, plus en gång per körning med
    /// egna talare. Flera inspelningar läggs ihop.
    private func estimate(for transcripts: [Transcript]) -> String {
        let duration = transcripts.reduce(0) { $0 + $1.duration }
        let runs = lab.plan.filter { lab.selected.contains($0.id) }
        let factor = runs.reduce(0.03) { total, run in
            let engine: Double
            switch run.engine {
            case .pianissimo: engine = 0.07
            case .kbLargeStrict: engine = 0.25
            case .largeV3Turbo: engine = 0.1
            case .pianissimoFP16: engine = 0.1
            case .pianissimoFP32: engine = 0.3
            }
            return total + engine + (run.speakers == .own ? 0.03 : 0) + (run.crossCheck ? 0.25 : 0)
        }
        let minutes = Int((duration * factor / 60).rounded())
        return minutes < 60 ? "cirka \(minutes) min" : "cirka \(minutes / 60) h \(minutes % 60) min"
    }
}

private struct StatusLabel: View {
    let status: TestLab.Status?

    var body: some View {
        switch status {
        case .running:
            ProgressView().controlSize(.small)
        case .done(let seconds):
            // Under en minut i sekunder: "0 min" såg ut som att inget hade körts.
            Label(TimeFormatting.duration(seconds), icon: .checkCircle)
                .foregroundStyle(.green)
        case .failed(let error):
            Label("Fel", icon: .warning)
                .foregroundStyle(Color.warning)
                .help(error)
        case .cancelled:
            Text("Avbruten").foregroundStyle(Color.textSecondary)
        case .waiting:
            Text("Väntar").foregroundStyle(Color.textSecondary)
        case .skipped, nil:
            EmptyView()
        }
    }
}

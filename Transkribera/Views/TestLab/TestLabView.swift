import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

/// Fönstret för Testlabbet (öppnas med ⌥⇧⌘T, finns inte i någon meny): välj en inspelning och vilka
/// inställningar som ska provas, och få en text per körning i en mapp.
struct TestLabView: View {
    @Environment(TestLab.self) private var lab
    @Environment(TranscriptionQueue.self) private var queue
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var transcriptID: UUID?

    private var runnable: [Transcript] { transcripts.filter(TestLab.canRun) }
    private var chosen: Transcript? { runnable.first { $0.id == transcriptID } }

    var body: some View {
        @Bindable var lab = lab
        Form {
            Section {
                Picker("Inspelning", selection: $transcriptID) {
                    Text("Välj…").tag(UUID?.none)
                    ForEach(runnable) { transcript in
                        Text("\(transcript.title) (\(Int(transcript.duration / 60)) min)").tag(Optional(transcript.id))
                    }
                }
                .disabled(lab.isRunning)
                Picker("Lista", selection: $lab.kind) {
                    ForEach(TestLabPlan.Kind.allCases) { kind in
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
                if let chosen {
                    LabeledContent("Uppskattad tid", value: estimate(for: chosen))
                }
                if lab.isRunning {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(lab.stepText)
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
                            if let chosen { lab.start(transcript: chosen, queue: queue) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen == nil || lab.selected.isEmpty)
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

    private var footer: String {
        let common = "Varje körning sparas som en textfil (som Exportera för analys) och en logg utan text. Vanliga transkriberingar påverkas inte, men nya filer väntar i kön tills labbet är klart."
        switch lab.kind {
        case .comparison:
            return "Samma inspelning körs med varje markerad inställning. Talarna identifieras en gång och används i alla körningar. " + common
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
    /// körning, Pianissimo en femtondel. Large v3 Turbo är inte uppmätt; en tiondel är en
    /// gissning. Talarna en gång, plus en gång per körning med egna talare.
    private func estimate(for transcript: Transcript) -> String {
        let runs = lab.plan.filter { lab.selected.contains($0.id) }
        let factor = runs.reduce(0.03) { total, run in
            let engine: Double
            switch run.engine {
            case .pianissimo: engine = 0.07
            case .kbLargeStrict: engine = 0.25
            case .largeV3Turbo: engine = 0.1
            }
            return total + engine + (run.speakers == .own ? 0.03 : 0)
        }
        let minutes = Int((transcript.duration * factor / 60).rounded())
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
            Label("\(Int((seconds / 60).rounded())) min", icon: .checkCircle)
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

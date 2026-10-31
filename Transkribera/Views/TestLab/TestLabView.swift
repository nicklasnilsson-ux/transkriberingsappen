import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

/// Fönstret för Testlabbet (Hjälp > Testlabb…): välj en inspelning och vilka
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
            } footer: {
                Text("Samma inspelning körs med varje markerad inställning. Varje körning sparas som en textfil (som Exportera för analys) och en logg utan text. Talarna identifieras en gång och används i alla körningar. Vanliga transkriberingar påverkas inte, men nya filer väntar i kön tills labbet är klart.")
                    .foregroundStyle(.secondary)
            }

            Section("Körningar") {
                ForEach(lab.plan) { run in
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(isOn: binding(for: run, in: $lab.selected)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title)
                                Text(run.differences.isEmpty ? "som i dag" : run.differences.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                    Text(message).foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 640)
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
    /// körning, Pianissimo en femtondel. Talarna en gång.
    private func estimate(for transcript: Transcript) -> String {
        let runs = lab.plan.filter { lab.selected.contains($0.id) }
        let factor = runs.reduce(0.03) { $0 + ($1.engine == .pianissimo ? 0.07 : 0.25) }
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
            Label("\(Int((seconds / 60).rounded())) min", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let error):
            Label("Fel", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(error)
        case .cancelled:
            Text("Avbruten").foregroundStyle(.secondary)
        case .waiting:
            Text("Väntar").foregroundStyle(.secondary)
        case .skipped, nil:
            EmptyView()
        }
    }
}

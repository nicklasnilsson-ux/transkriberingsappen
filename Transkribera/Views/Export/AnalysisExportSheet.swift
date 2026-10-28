import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore
import UniformTypeIdentifiers

/// Exporterar en eller flera transkriberingar i ett format anpassat för analys
/// (t.ex. tematisering i Claude): en Markdown-fil per session.
struct AnalysisExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var selected: Set<UUID>

    init(preselected: Transcript?) {
        _selected = State(initialValue: preselected.map { [$0.id] } ?? [])
    }

    private var exportable: [Transcript] {
        transcripts.filter { $0.status == .completed && !$0.segments.isEmpty }
    }

    private var chosen: [Transcript] {
        exportable.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exportera för analys")
                .font(.title2.weight(.semibold))
            Text("Varje session blir en Markdown-fil med datum, längd och talare överst och ett stycke per talarbyte med tidskod. Byt gärna namn på talarna först, t.ex. till ”Moderator” och ”Deltagare”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if exportable.isEmpty {
                Text("Det finns inga färdiga transkriberingar att exportera.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(exportable) { transcript in
                    Toggle(isOn: binding(for: transcript)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transcript.title).lineLimit(1)
                            Text("\(transcript.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(TimeFormatting.duration(transcript.duration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.bordered)
            }

            HStack {
                Button("Markera alla") { selected = Set(exportable.map(\.id)) }
                    .disabled(exportable.isEmpty || chosen.count == exportable.count)
                Spacer()
                Button("Avbryt", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Exportera \(chosen.count) filer…" : "Exportera…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
    }

    private func binding(for transcript: Transcript) -> Binding<Bool> {
        Binding(
            get: { selected.contains(transcript.id) },
            set: { isOn in
                if isOn { selected.insert(transcript.id) } else { selected.remove(transcript.id) }
            }
        )
    }

    private func export() {
        let items = chosen
        let names = AnalysisExporter.uniqueFileNames(for: items.map(\.title))
        let files = zip(items, names).map { transcript, name in
            (name: name, content: AnalysisExporter.markdown(Self.segments(for: transcript), metadata: transcript.metadata))
        }

        if files.count == 1, let file = files.first {
            let panel = NSSavePanel()
            panel.title = "Exportera för analys"
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            if let type = UTType(filenameExtension: "md") {
                panel.allowedContentTypes = [type]
            }
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                write([(url, file.content)])
            }
        } else {
            let panel = NSOpenPanel()
            panel.title = "Välj mapp för exporten"
            panel.prompt = "Exportera hit"
            panel.message = "En fil per session sparas i mappen. Filer med samma namn skrivs över."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.begin { response in
                guard response == .OK, let folder = panel.url else { return }
                write(files.map { (folder.appending(path: $0.name), $0.content) })
            }
        }
    }

    private func write(_ files: [(URL, String)]) {
        do {
            for (url, content) in files {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
            dismiss()
            if let first = files.first?.0 {
                NSWorkspace.shared.activateFileViewerSelecting(files.count == 1 ? [first] : files.map(\.0))
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Segmenten som exporteras.
    static func segments(for transcript: Transcript) -> [SegmentData] {
        transcript.outputSegments()
    }
}

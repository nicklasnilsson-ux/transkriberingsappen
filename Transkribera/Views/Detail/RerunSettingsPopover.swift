import SwiftUI
import TranskriberaCore

/// Modell, språk och talare för en omtagning av just den här filen. Ändrar inte
/// standardinställningarna för nästa transkribering.
struct RerunSettingsPopover: View {
    @Binding var overrides: TranscriptionOverrides
    /// Utgångsläget är det filen har, inte dina standardinställningar.
    let file: FileBaseline
    /// Blå knapp först när något val skiljer sig från det filen transkriberades med.
    let isChanged: Bool
    let isWorking: Bool
    let onRerun: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inställningar för den här filen").font(.headline)
            Text("Gäller bara nästa omtagning av den här transkriberingen. Dina vanliga inställningar ändras inte.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Modell") {
                ModelPicker(selection: Binding(
                    get: { overrides.modelRaw ?? file.modelRaw },
                    set: { overrides.modelRaw = $0 }
                ))
                .frame(width: 240)
            }
            Picker("Språk", selection: Binding(
                get: { overrides.language ?? file.language },
                set: { overrides.language = $0 }
            )) {
                ForEach(Language.all) { Text($0.name).tag($0.id) }
            }
            Toggle("Skilj på vem som pratar", isOn: Binding(
                get: { overrides.identifySpeakers ?? file.identifySpeakers },
                set: { overrides.identifySpeakers = $0 }
            ))
            if overrides.identifySpeakers ?? file.identifySpeakers {
                SpeakerCountPicker(selection: Binding(
                    get: { overrides.speakerCount?.rawValue ?? SpeakerCount.automatic.rawValue },
                    set: { overrides.speakerCount = SpeakerCount(rawValue: $0) }
                ))
            }
            HStack {
                Button("Återställ") { overrides = TranscriptionOverrides() }
                    .buttonStyle(.link)
                    .disabled(overrides.isEmpty)
                    .help("Tillbaka till det filen transkriberades med")
                Spacer()
                Button {
                    onRerun()
                    dismiss()
                } label: {
                    Label("Transkribera igen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(RerunButtonStyle(isEmphasized: isChanged))
                .disabled(isWorking)
                .help("Transkribera filen igen med valen ovan. Den nuvarande versionen sparas.")
            }
        }
        .frame(width: 340)
        .padding(16)
    }
}

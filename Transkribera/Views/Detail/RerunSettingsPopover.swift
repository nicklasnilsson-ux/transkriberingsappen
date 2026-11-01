import SwiftUI
import TranskriberaCore

/// Modell, språk och talare för en omtagning av just den här filen. Ändrar inte
/// standardinställningarna för nästa transkribering.
struct RerunSettingsPopover: View {
    @Binding var overrides: TranscriptionOverrides
    /// Utgångsläget är det filen har, inte dina standardinställningar.
    let file: FileBaseline

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inställningar för den här filen").font(.headline)
            Text("Gäller bara nästa omtagning av den här transkriberingen. Dina vanliga inställningar ändras inte.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if !overrides.isEmpty {
                Button("Återställ till det filen har") { overrides = TranscriptionOverrides() }
                    .buttonStyle(.link)
            }
        }
        .frame(width: 340)
        .padding(16)
    }
}

import SwiftUI
import TranskriberaCore

/// Modell, språk och talare för en omtagning av just den här filen. Ändrar inte
/// standardinställningarna för nästa transkribering.
struct RerunSettingsPopover: View {
    @Binding var overrides: TranscriptionOverrides
    @AppStorage(SettingsKey.model) private var defaultModel = WhisperModel.default.rawValue
    @AppStorage(SettingsKey.language) private var defaultLanguage = "sv"
    @AppStorage(SettingsKey.identifySpeakers) private var defaultIdentify = false
    @AppStorage(SettingsKey.speakers) private var defaultSpeakers = SpeakerCount.automatic.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inställningar för den här filen").font(.headline)
            Text("Gäller bara nästa omtagning av den här transkriberingen. Dina vanliga inställningar ändras inte.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Modell") {
                ModelPicker(selection: Binding(
                    get: { overrides.modelRaw ?? defaultModel },
                    set: { overrides.modelRaw = $0 }
                ))
                .frame(width: 240)
            }
            Picker("Språk", selection: Binding(
                get: { overrides.language ?? defaultLanguage },
                set: { overrides.language = $0 }
            )) {
                ForEach(Language.all) { Text($0.name).tag($0.id) }
            }
            Toggle("Skilj på vem som pratar", isOn: Binding(
                get: { overrides.identifySpeakers ?? defaultIdentify },
                set: { overrides.identifySpeakers = $0 }
            ))
            if overrides.identifySpeakers ?? defaultIdentify {
                SpeakerCountPicker(selection: Binding(
                    get: { overrides.speakerCount?.rawValue ?? defaultSpeakers },
                    set: { overrides.speakerCount = SpeakerCount(rawValue: $0) }
                ))
            }
            if !overrides.isEmpty {
                Button("Återställ till vanliga inställningar") { overrides = TranscriptionOverrides() }
                    .buttonStyle(.link)
            }
        }
        .frame(width: 340)
        .padding(16)
    }
}

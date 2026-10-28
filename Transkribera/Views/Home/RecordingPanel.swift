import AppKit
import SwiftUI
import TranskriberaCore

/// Knapp och status för mötesinspelning (systemljud + ev. mikrofon).
struct RecordingPanel: View {
    var onCreated: (Transcript) -> Void

    @Environment(MeetingRecorder.self) private var recorder
    @Environment(TranscriptionQueue.self) private var queue
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: recorder.isRecording ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(recorder.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .symbolEffect(.pulse, isActive: recorder.isRecording)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mötesinspelning")
                        .font(.headline)
                    statusText
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await toggle() }
                } label: {
                    Text(recorder.isRecording ? "Stoppa och transkribera" : "Starta inspelning")
                        .frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? Color.red : Color.accentColor)
                .controlSize(.large)
                .disabled(recorder.state == .starting || recorder.state == .finishing)
                .help(recorder.isRecording
                      ? "Avslutar inspelningen och börjar transkribera den"
                      : "Spelar in allt ljud som hörs på datorn tills du stoppar")
            }

            if MeetingRecorder.supportsMicrophone {
                Toggle("Spela även in min mikrofon", isOn: $recordMicrophone)
                    .disabled(recorder.isBusy)
                    .help("Ta med din egen röst. Annars spelas bara datorns ljud in, alltså de andra deltagarna.")
            }

            if let error = recorder.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if error == RecordingError.permissionDenied.errorDescription {
                    Button("Öppna Systeminställningar") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var statusText: some View {
        switch recorder.state {
        case .idle:
            Text("Spelar in datorns ljud, t.ex. ett Teams- eller Meet-möte, och transkriberar när du stoppar.")
        case .starting:
            Text("Startar inspelningen…")
        case .recording(let since):
            TimelineView(.periodic(from: since, by: 1)) { context in
                Text("Spelar in · \(TimeFormatting.short(context.date.timeIntervalSince(since)))")
                    .monospacedDigit()
            }
        case .finishing:
            Text("Sparar inspelningen…")
        }
    }

    private func toggle() async {
        if recorder.isRecording {
            guard let url = await recorder.stop() else { return }
            let title = "Möte " + Date().formatted(date: .abbreviated, time: .shortened)
            if let transcript = await queue.importRecording(at: url, title: title) {
                onCreated(transcript)
            }
        } else {
            await recorder.start(includeMicrophone: recordMicrophone && MeetingRecorder.supportsMicrophone)
        }
    }
}

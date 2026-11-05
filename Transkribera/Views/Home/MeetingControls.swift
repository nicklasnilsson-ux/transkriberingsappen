import AppKit
import SwiftUI
import TranskriberaCore

/// Mötesläget i sidopanelen. Mikrofonvalet och Starta/Stoppa ersätter släppytan. Modell, språk, talare och
/// ordlista ligger i inställningskortet överst i panelen, som gäller både Fil och Mötesinspelning.
/// Under inspelning är valen låsta och det går inte att börja transkribera något annat:
/// man gör en sak i taget (Nicklas 2026-11-03).
struct MeetingControls: View {
    @Environment(MeetingRecorder.self) private var recorder
    @Environment(TranscriptionQueue.self) private var queue
    @Environment(AppState.self) private var appState
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                if MeetingRecorder.supportsMicrophone {
                    SwitchRow("Spela även in min mikrofon", isOn: $recordMicrophone)
                        .help("Ta med din egen röst. Annars spelas bara datorns ljud in, alltså de andra deltagarna.")
                }
            }
            // Låst läge under inspelning.
            .disabled(recorder.isBusy)
            .opacity(recorder.isBusy ? 0.55 : 1)

            if case .recording(let since) = recorder.state {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text("Spelar in").font(.callout)
                    Spacer()
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(TimeFormatting.short(context.date.timeIntervalSince(since)))
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            Button {
                Task { await toggle() }
            } label: {
                Text(recorder.isRecording ? "Stoppa inspelning" : "Starta inspelning")
                    .frame(maxWidth: .infinity)
            }
            .modifier(RecordingButtonStyle(isRecording: recorder.isRecording))
            .controlSize(.large)
            .disabled(recorder.state == .starting || recorder.state == .finishing)
            .help(recorder.isRecording
                  ? "Avslutar inspelningen och börjar transkribera den"
                  : "Spelar in allt ljud som hörs på datorn tills du stoppar")

            Text(recorder.isBusy
                 ? "Texten skapas när du stoppar inspelningen."
                 : "Spelar in allt ljud som hörs på datorn tills du stoppar.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func toggle() async {
        if recorder.isRecording {
            guard let url = await recorder.stop() else { return }
            let title = "Möte " + Date().formatted(date: .abbreviated, time: .shortened)
            if let transcript = await queue.importRecording(at: url, title: title) {
                appState.selection = transcript
            }
        } else {
            await recorder.start(includeMicrophone: recordMicrophone && MeetingRecorder.supportsMicrophone)
        }
    }
}

/// En rad med en reglage: texten till vänster och reglaget längst till höger, över hela bredden.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Starta inspelning är appens uppmaning (accent). Stoppa är en neutral svart knapp.
private struct RecordingButtonStyle: ViewModifier {
    let isRecording: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRecording {
            content.buttonStyle(NeutralProminentButtonStyle())
        } else {
            content.buttonStyle(.borderedProminent).tint(Color.accentColor)
        }
    }
}

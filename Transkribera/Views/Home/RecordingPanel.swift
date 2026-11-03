import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

/// Knapp och status för mötesinspelning (systemljud + ev. mikrofon).
struct RecordingPanel: View {
    var onCreated: (Transcript) -> Void

    @Environment(MeetingRecorder.self) private var recorder
    @Environment(TranscriptionQueue.self) private var queue
    @Query private var allTranscripts: [Transcript]
    @AppStorage(SettingsKey.recordMicrophone) private var recordMicrophone = true

    var body: some View {
        VStack(spacing: 14) {
            controlCard
            statusCard
        }
    }

    /// Filer som släppts under inspelningen och väntar i kön.
    private var waitingCount: Int { allTranscripts.filter { $0.status == .queued }.count }

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape.fill(Color.surface))
            .overlay(cardShape.strokeBorder(Color.line, lineWidth: 1))
    }

    /// Överst: inspelningsstatus och knappen. Under inspelning en röd tid och "Spelar in".
    private var controlCard: some View {
        card {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if case .recording(let since) = recorder.state {
                        TimelineView(.periodic(from: since, by: 1)) { context in
                            Text(TimeFormatting.short(context.date.timeIntervalSince(since)))
                                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.red)
                        }
                        Text("Spelar in").font(.headline)
                    } else {
                        Text("Mötesinspelning").font(.headline)
                        Text("Spelar in allt ljud som hörs på datorn tills du stoppar.")
                            .font(.callout)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                Button {
                    Task { await toggle() }
                } label: {
                    Text(recorder.isRecording ? "Stoppa och transkribera" : "Starta inspelning")
                        .frame(minWidth: 170)
                }
                .modifier(RecordingButtonStyle(isRecording: recorder.isRecording))
                .controlSize(.large)
                .disabled(recorder.state == .starting || recorder.state == .finishing)
                .help(recorder.isRecording
                      ? "Avslutar inspelningen och börjar transkribera den"
                      : "Spelar in allt ljud som hörs på datorn tills du stoppar")
            }
        }
    }

    /// Statuskort. Texten skapas när inspelningen stoppas, inte under tiden.
    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.textSecondary)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    statusText.font(.headline)
                }
                Text("Texten skapas när du stoppar inspelningen.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                if recorder.isBusy, waitingCount > 0 {
                    Text(waitingCount == 1
                         ? "1 fil väntar och transkriberas när inspelningen är sparad."
                         : "\(waitingCount) filer väntar och transkriberas när inspelningen är sparad.")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                }

                if let error = recorder.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Color.warning)
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
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch recorder.state {
        case .idle: Text("Redo att spela in")
        case .starting: Text("Startar inspelningen…")
        case .recording: Text("Inspelningen pågår")
        case .finishing: Text("Sparar inspelningen…")
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

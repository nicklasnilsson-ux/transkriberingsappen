import AppKit
import SwiftData
import SwiftUI
import TranskriberaCore

/// Mötesinspelning i huvudytan: bara status. Knapparna och inställningarna ligger i sidopanelen
/// (`MeetingControls`). Texten skapas när inspelningen stoppas, inte under tiden.
struct MeetingModeView: View {
    @Environment(MeetingRecorder.self) private var recorder
    @Query private var allTranscripts: [Transcript]

    /// Filer som släppts under inspelningen och väntar i kön.
    private var waitingCount: Int { allTranscripts.filter { $0.status == .queued }.count }

    var body: some View {
        VStack(spacing: 14) {
            if case .recording(let since) = recorder.state {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(TimeFormatting.short(context.date.timeIntervalSince(since)))
                        .font(.system(size: 44, weight: .semibold, design: .monospaced))
                }
            } else {
                Icon(.record, size: 48)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            statusText.font(.title2.weight(.semibold))
            Text(recorder.isBusy
                 ? "Spelar in allt ljud som hörs på datorn tills du stoppar. Texten skapas när du stoppar inspelningen."
                 : "Spelar in allt ljud som hörs på datorn tills du stoppar. Texten skapas när inspelningen är klar.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if recorder.isBusy, waitingCount > 0 {
                Text(waitingCount == 1
                     ? "1 fil väntar och transkriberas när inspelningen är sparad."
                     : "\(waitingCount) filer väntar och transkriberas när inspelningen är sparad.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
            if let error = recorder.errorMessage {
                Label(error, icon: .warning)
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
        .frame(maxWidth: 420)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Mötesinspelning")
    }

    @ViewBuilder
    private var statusText: some View {
        switch recorder.state {
        case .idle: Text("Redo att spela in")
        case .starting: Text("Startar inspelningen…")
        case .recording: Text("Spelar in")
        case .finishing: Text("Sparar inspelningen…")
        }
    }
}

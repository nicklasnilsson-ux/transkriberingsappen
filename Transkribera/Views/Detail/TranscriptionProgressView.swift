import SwiftUI

/// Visas medan en fil väntar i kön eller transkriberas.
struct TranscriptionProgressView: View {
    let transcript: Transcript
    @Environment(TranscriptionQueue.self) private var queue

    private var isCurrent: Bool { queue.currentTranscriptID == transcript.id }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isCurrent ? "waveform" : "clock")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: isCurrent)

            if isCurrent {
                let transcriber = queue.transcriber
                VStack(spacing: 4) {
                    if let step = transcriber.stepText {
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(transcriber.statusText)
                        .font(.headline)
                }
                // Samma stapel i alla steg; utan procent rör den sig obestämt i stället
                // för att stå still på noll.
                Group {
                    if let fraction = transcriber.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .frame(maxWidth: 360)
                if !transcriber.liveText.isEmpty {
                    Text("”\(transcriber.liveText)”")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 480)
                        .transition(.opacity)
                }
            } else {
                Text("Väntar i kön")
                    .font(.headline)
                Text("Startar automatiskt när filerna före är klara.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(isCurrent ? "Avbryt transkriberingen" : "Ta bort från kön", role: .cancel) {
                queue.cancel(transcript)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: queue.transcriber.liveText)
    }
}

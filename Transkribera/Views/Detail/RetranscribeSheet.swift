import SwiftUI
import TranskriberaCore

/// Frågan före "Transkribera igen". Säger vad som händer med den här versionen, att de 4 senaste
/// versionerna behålls och, när alla platser används, vilken version som raderas.
/// Texterna och reglerna ligger i `RetranscribeDialog` (och är enhetstestade).
struct RetranscribeSheet: View {
    /// Antal versioner nu, den visade inräknad.
    let versionCount: Int
    /// Den äldsta versionens tid och modell, för dialogen när den raderas.
    let oldestDescription: String?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @AppStorage(SettingsKey.askBeforeRetranscribe) private var ask = true
    @State private var dontAskAgain = false

    private var kind: RetranscribeDialog.Kind { RetranscribeDialog.kind(versionCount: versionCount) }
    private var canSuppress: Bool { RetranscribeDialog.canSuppress(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(RetranscribeDialog.title(kind))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(RetranscribeDialog.message(kind))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            slots

            if case .replacesOldest = kind, let oldestDescription {
                Text(RetranscribeDialog.warning(oldest: oldestDescription))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if canSuppress {
                Toggle(isOn: $dontAskAgain) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RetranscribeDialog.suppressLabel)
                        Text(RetranscribeDialog.suppressHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button("Avbryt", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(RetranscribeDialog.confirmButton(kind)) {
                    if dontAskAgain && canSuppress { ask = false }
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// De 4 platserna för versioner. Fyllda är sparade, den heldragna är den nya, och den
    /// streckade (som raderas) är Version 1 när alla platser används.
    private var slots: some View {
        HStack(spacing: 6) {
            ForEach(0..<VersionHistory.capacity, id: \.self) { index in
                slot(index)
            }
            Text(slotCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slotCaption)
    }

    private var slotCaption: String {
        switch kind {
        case .roomLeft(let versions): "\(versions + 1) av \(VersionHistory.capacity) platser används efter detta"
        case .replacesOldest: "\(VersionHistory.capacity) av \(VersionHistory.capacity) platser används"
        }
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch kind {
        case .replacesOldest where index == 0:
            shape.fill(Color.warning.opacity(0.15))
                .overlay(shape.strokeBorder(Color.warning, lineWidth: 1.5))
                .frame(width: 44, height: 18)
        case .roomLeft(let versions) where index == versions:
            shape.fill(Color.accentColor)
                .frame(width: 44, height: 18)
        case .roomLeft(let versions) where index > versions:
            shape.strokeBorder(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                .frame(width: 44, height: 18)
        default:
            shape.fill(Color.accentColor.opacity(0.15))
                .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 1.5))
                .frame(width: 44, height: 18)
        }
    }
}

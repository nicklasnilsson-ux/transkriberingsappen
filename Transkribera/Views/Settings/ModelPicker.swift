import SwiftUI

/// Modellväljare som visar storlek, språkstyrka, fart och karaktär för varje
/// modell redan i listan, innan man väljer.
struct ModelPicker: View {
    @Binding var selection: String
    @Environment(TranscriptionQueue.self) private var queue
    @State private var isPresented = false

    var body: some View {
        let current = WhisperModel(rawValue: selection) ?? .default
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(current.displayName)
                Text("· \(current.downloadSize)").foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help("Välj vilken Whisper-modell som ska transkribera")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelList(selection: current, transcriber: queue.transcriber) { model in
                selection = model.rawValue
                isPresented = false
            }
        }
    }
}

private struct ModelList: View {
    let selection: WhisperModel
    let transcriber: TranscriberService
    let onSelect: (WhisperModel) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ModelAdvice()
                ForEach(WhisperModel.Family.allCases) { family in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(family.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        ForEach(family.models) { model in
                            Button { onSelect(model) } label: {
                                ModelInfoRow(model: model, isDownloaded: transcriber.isDownloaded(model))
                                    .padding(8)
                                    .background(
                                        model == selection ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ModelSourceNote()
                    .padding(.horizontal, 8)
            }
            .padding(10)
        }
        .frame(width: 440)
        .frame(maxHeight: 560)
    }
}

/// En rad med all information om en modell. Används i väljaren och i Inställningar.
struct ModelInfoRow: View {
    let model: WhisperModel
    let isDownloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(model.displayName).font(.body.weight(.medium))
                if model.isRecommended { Badge(text: "Rekommenderad", color: .accentColor) }
                Badge(text: model.languageNote, color: model.isSwedishOnly ? .blue : .gray)
                Spacer(minLength: 4)
                Text(model.downloadSize)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(model.characteristic)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.swedishErrorText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Meter(label: "Fart", value: model.speed)
                Meter(label: "Svenska", value: model.swedishAccuracy)
                    .help(model.swedishErrorText)
                Spacer()
                Label(isDownloaded ? "Finns på datorn" : "Laddas ner automatiskt första gången",
                      systemImage: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.caption2)
                    .foregroundStyle(isDownloaded ? .green : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kort vägledning överst i väljaren.
private struct ModelAdvice: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pratas det svenska? Välj en KB-modell.").font(.callout.weight(.medium))
                Text("KB Small gör färre fel på svenska än OpenAI:s Large v3, fast den är sex gånger mindre. Större KB-modeller blir ännu säkrare men långsammare. För andra språk passar OpenAI-modellerna bättre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lightbulb").foregroundStyle(.yellow)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Källhänvisning för felsiffrorna.
struct ModelSourceNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Felsiffrorna är KBLab:s mätningar på det svenska testet FLEURS. Riktigt ljud med brus eller dialekt ger fler fel för alla modeller, men ordningen mellan dem brukar hålla.")
            Link("Källa: KBLab, Kungliga biblioteket", destination: URL(string: "https://kb-labb.github.io/posts/2025-03-07-welcome-KB-Whisper/")!)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// Fem prickar, t.ex. "Fart ●●●○○".
private struct Meter: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(index <= value ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) av 5")
    }
}

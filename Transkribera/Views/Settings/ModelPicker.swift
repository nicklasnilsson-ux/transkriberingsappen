import SwiftUI

/// Modellväljare som visar storlek, språkstyrka, fart och karaktär för varje
/// modell redan i listan, innan man väljer.
struct ModelPicker: View {
    @Binding var selection: String
    @Environment(TranscriptionQueue.self) private var queue
    @State private var isPresented = false

    var body: some View {
        let current = WhisperModel.resolved(selection)
        let replaced = WhisperModel.hiddenModel(selection)
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(current.displayName)
                Text("· \(current.downloadSize)").foregroundStyle(Color.textSecondary)
                if let replaced {
                    Text("(ersätter \(replaced.displayName))").foregroundStyle(Color.warning)
                }
                Spacer(minLength: 8)
                Icon(.unfold, size: 14)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(replaced.map { "\($0.displayName) finns inte längre i väljaren, så \(current.displayName) används. Välj en modell här för att spara valet." }
              ?? "Välj vilken modell som ska transkribera")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelList(selection: current, transcriber: queue.transcriber) { model in
                selection = model.rawValue
                isPresented = false
            }
                .font(.app(.regular))
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
                            .font(.app(.small, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
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
                Text(model.displayName).font(.app(.regular, weight: .medium))
                if model.isRecommended { Badge(text: "Rekommenderad", color: .accentColor) }
                Badge(text: model.languageNote, color: model.isSwedishOnly ? Color.accentColor : .gray)
                Spacer(minLength: 4)
                Text(model.downloadSize)
                    .font(.app(.small).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            Text(model.characteristic)
                .font(.app(.small))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.swedishErrorText)
                .font(.app(.small).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
            if let warning = model.memoryWarning {
                Label(warning, icon: .memory)
                    .font(.app(.small))
                    .foregroundStyle(Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Meter(label: "Fart", value: model.speed)
                Meter(label: "Svenska", value: model.swedishAccuracy)
                    .help(model.swedishErrorText)
                Spacer()
                Label(isDownloaded ? "Finns på datorn" : "Laddas ner automatiskt första gången",
                      icon: isDownloaded ? .checkCircle : .downloadCircle)
                    .font(.app(.small))
                    .foregroundStyle(isDownloaded ? Color.green : Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Kort vägledning överst i väljaren.
private struct ModelAdvice: View {
    @State private var showsGuide = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pratas det svenska? Välj Pianissimo.").font(.app(.regular, weight: .medium))
                Text("Pianissimo är snabbast och ger en komplett text. Välj KB Large ordagrann när varje ord måste stämma, t.ex. för citat, namn och facktermer. Andra språk än svenska: välj Large v3 Turbo.")
                    .font(.app(.small))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Vilken modell ska jag välja?") { showsGuide = true }
                    .buttonStyle(.link)
                    .font(.app(.small))
                    .popover(isPresented: $showsGuide, arrowEdge: .trailing) { ModelGuideView().font(.app(.regular)) }
            }
        } icon: {
            Image(icon: .lightbulb).foregroundStyle(.yellow)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Källhänvisning för felsiffrorna.
struct ModelSourceNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Felsiffrorna är KBLab:s mätningar (Pianissimo: Klangs) på det svenska testet FLEURS. Riktigt ljud med brus eller dialekt ger fler fel för alla modeller, men ordningen mellan dem brukar hålla.")
            Link("Källa: KBLab, Kungliga biblioteket", destination: URL(string: "https://kb-labb.github.io/posts/2025-03-07-welcome-KB-Whisper/")!)
        }
        .font(.app(.small))
        .foregroundStyle(Color.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.app(.small, weight: .medium))
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
            Text(label).font(.app(.small)).foregroundStyle(Color.textSecondary)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    Circle()
                        .fill(index <= value ? Color.accentColor : Color.textSecondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value) av 5")
    }
}

/// Längre förklaring i klartext om hur modellerna skiljer sig åt. Visas från
/// "Vilken modell ska jag välja?" i väljaren och i Inställningar.
struct ModelGuideView: View {
    private let rows: [WhisperModel] = WhisperModel.offered.filter { $0.swedishWordErrorRate != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Vilken modell ska jag välja?")
                    .font(.app(.large, weight: .semibold))

                section("Pianissimo: första valet för svenska",
                        "Pianissimo från Klang bygger inte på Whisper utan på NVIDIA:s Parakeet och är vidaretränad på omkring 50 000 timmar svenskt tal. Den är många gånger snabbare än Whisper-modellerna, även på långa inspelningar, och sätter själv punkt och stor bokstav. I våra jämförelser på riktiga intervjuer låg den nära KB Large på innehållet; skillnaden syns mest i småord och ordlydelse.")
                Link("Pianissimo av KlangAI, licens CC BY 4.0",
                     destination: URL(string: "https://huggingface.co/KlangAI/pianissimo-sv")!)
                    .font(.app(.small))

                section("KB Large ordagrann: när varje ord måste stämma",
                        "KB-modellerna kommer från Kungliga biblioteket (KBLab) och är vidaretränade på över 50 000 timmar svenskt tal. Den ordagranna varianten skriver mer exakt vad som sägs och stryker mindre. Välj den för citat, namn och facktermer, när du kan vänta längre och datorn har minst 16 GB minne.")

                section("Andra språk: Large v3 Turbo",
                        "Pianissimo och KB-modellen är tränade för svenska och blir sämre på andra språk. Pratas det engelska eller blandade språk, välj Large v3 Turbo.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Fel per 100 ord på svenska").font(.app(.large, weight: .semibold))
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        ForEach(rows) { model in
                            GridRow {
                                Text(model.displayName)
                                bar(for: model)
                                Text(Self.format(model.swedishWordErrorRate ?? 0))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.textSecondary)
                                    .gridColumnAlignment(.trailing)
                            }
                            .font(.app(.regular))
                        }
                        GridRow {
                            Text("OpenAI Large v3")
                            bar(rate: 7.8, highlighted: false)
                            Text(Self.format(7.8))
                                .monospacedDigit()
                                .foregroundStyle(Color.textSecondary)
                        }
                        .font(.app(.regular))
                    }
                    Text("OpenAI Large v3 är den modell som Large v3 Turbo bygger på. Turbo är snabbare men brukar göra något fler fel.")
                        .font(.app(.small))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ModelSourceNote()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460, height: 560)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.app(.large, weight: .semibold))
            Text(text)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bar(for model: WhisperModel) -> some View {
        bar(rate: model.swedishWordErrorRate ?? 0, highlighted: model.isSwedishOnly)
    }

    /// Stapel där 60 fel per 100 ord fyller hela bredden.
    private func bar(rate: Double, highlighted: Bool) -> some View {
        let width = 180.0
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.textSecondary.opacity(0.15)).frame(width: width, height: 8)
            Capsule()
                .fill(highlighted ? Color.accentColor : Color.textSecondary.opacity(0.6))
                .frame(width: max(4, width * min(rate, 60) / 60), height: 8)
        }
    }

    private static func format(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "sv_SE")))
    }
}

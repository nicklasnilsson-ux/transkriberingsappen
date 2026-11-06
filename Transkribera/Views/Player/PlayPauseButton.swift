import SwiftUI

/// Spela/Pausa i spelarraden: en rund platta i accentfärgen med vit ikon.
///
/// Storleken är fast och uttalad i stället för att komma från `.borderedProminent` + `.controlSize(.large)`,
/// så att den kan kontrolleras. Nicklas 2026-11-06: dubbelt så stor som plattan i 0.9.2–0.9.14
/// (se `PlayButtonSizeTests`, som mäter den gamla knappen och jämför). Bredden tas från reglaget,
/// som är det enda i raden som växer och krymper.
struct PlayPauseButton: View {
    /// Plattans diameter i punkter.
    static let diameter: CGFloat = 56
    /// Ikonen dubblas också (22 pt på den gamla plattan, som mätte 28 pt på macOS 15).
    static let iconSize: CGFloat = 44

    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(isPlaying ? .pause : .play, size: Self.iconSize)
                .foregroundStyle(.white)
        }
        .buttonStyle(RoundAccentButtonStyle(diameter: Self.diameter))
        .accessibilityLabel(isPlaying ? "Pausa" : "Spela")
        .help(isPlaying ? "Pausa" : "Spela")
    }
}

/// Rund accentplatta. Lite mörkare när den trycks ned, nedtonad när den är avstängd.
private struct RoundAccentButtonStyle: ButtonStyle {
    let diameter: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().fill(Color.black.opacity(configuration.isPressed ? 0.15 : 0)))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Circle())
    }
}

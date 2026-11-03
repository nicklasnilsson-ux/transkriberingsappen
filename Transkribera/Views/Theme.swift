import SwiftUI

extension Color {
    /// Varningsfärg för text och ikoner. Systemets orange ger bara 2,2:1 mot vitt;
    /// den här har minst 4,5:1 i ljust och mörkt läge (kontrolleras av scripts/check_colors.py).
    static let warning = Color("WarningColor")

    // Appens egen palett (vit och stram, ljust och mörkt, med varianter för Öka kontrast).
    // Alla textfärger kontrolleras mot alla bakgrunder av scripts/check_colors.py.
    static let appBackground = Color("AppBackground")
    static let sidebarBackground = Color("SidebarBackground")
    /// Kort och fält som ligger ovanpå bakgrunden.
    static let surface = Color("SurfaceBackground")
    /// Chips, tonade fält och inställningsknappar.
    static let chip = Color("ChipBackground")
    /// Tunna kanter och avdelare. Bär ingen information ensam.
    static let line = Color("LineColor")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    /// Neutral primärknapp (svart i ljust läge): Exportera och Stoppa inspelning.
    static let neutralButton = Color("NeutralButton")
    static let neutralButtonText = Color("NeutralButtonText")
}

/// Svart (i mörkt läge ljus) primärknapp för åtgärder som inte är appens huvudsakliga uppmaning.
/// Appens call to action (till exempel Starta inspelning) är fortsatt accentfärgad.
struct NeutralProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var controlSize: ControlSize = .large

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color.neutralButtonText)
            .padding(.horizontal, controlSize == .large ? 16 : 12)
            .padding(.vertical, controlSize == .large ? 8 : 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.neutralButton)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

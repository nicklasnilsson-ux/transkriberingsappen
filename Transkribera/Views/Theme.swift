import AppKit
import SwiftUI
import TranskriberaCore

extension Color {
    /// Varningsfärg för text och ikoner. Systemets orange ger bara 2,2:1 mot vitt;
    /// den här har minst 4,5:1 i ljust och mörkt läge (kontrolleras av scripts/check_colors.py).
    static let warning = Color("WarningColor")
    /// Klar. Grön med minst 4,5:1 mot alla bakgrunder (kontrolleras av scripts/check_colors.py).
    static let success = Color("SuccessColor")

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
            .font(.app(.regular, weight: .medium))
            .foregroundStyle(Color.neutralButtonText)
            .padding(.horizontal, controlSize == .large ? 16 : 12)
            .padding(.vertical, controlSize == .large ? 8 : 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.neutralButton)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }
}

/// Appens tre textstorlekar (Nicklas 2026-11-06). Inga andra storlekar får användas i gränssnittet;
/// scripts/test_text_sizes.py stoppar bygget om någon annan storlek dyker upp.
/// Hierarkin bärs av vikt och färg, inte av fler storlekar.
enum AppTextSize: CGFloat, CaseIterable {
    /// Sekundärt: hjälptext, tidskoder, metadata, märken, små knappar.
    case small = 12
    /// All vanlig text: knappar, listrader, formulär, bannrar. Standard i alla fönster.
    case regular = 14
    /// Rubriker (semibold).
    case large = 16
}

extension Font {
    /// En av appens tre textstorlekar.
    static func app(_ size: AppTextSize, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size.rawValue, weight: weight, design: design)
    }
}

extension Font {
    /// Läsytan (transkriptet): 16 pt som standard, ⌘+/⌘− väljer bland `ReadingTextSize.steps`.
    static func reading(_ size: Double) -> Font {
        .system(size: CGFloat(ReadingTextSize.clamped(size)))
    }

    /// Tiden under mötesinspelning. Enda undantaget från de tre storlekarna: den är det enda som
    /// syns under en inspelning och ska gå att läsa av på håll.
    static let meetingTimer = Font.system(size: 44, weight: .semibold, design: .monospaced)
}

extension NSFont {
    /// Läsytan i redigeringsfältet, samma storlek som `Font.reading`.
    static func reading(_ size: Double) -> NSFont {
        .systemFont(ofSize: CGFloat(ReadingTextSize.clamped(size)))
    }
}

extension View {
    /// Roten i varje ark och popover. En popover ärver miljön från det den öppnas från. Öppnas den från
    /// sidopanelens lista följer listradens radgräns med, och förklarande texter klipptes till en rad med …
    /// (modellväljaren från Inställningar-kortet, 2026-11-06). Här nollställs det, och texten får appens 14 pt.
    /// scripts/test_text_sizes.py kräver den på varje .sheet/.popover; `PresentationRootTests` mäter effekten.
    func presentationRoot() -> some View {
        self
            .font(.app(.regular))
            .lineLimit(nil)
            .truncationMode(.tail)
    }
}

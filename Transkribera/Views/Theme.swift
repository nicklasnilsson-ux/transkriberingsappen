import SwiftUI

extension Color {
    /// Varningsfärg för text och ikoner. Systemets orange ger bara 2,2:1 mot vitt;
    /// den här har minst 4,5:1 i ljust och mörkt läge (kontrolleras av scripts/check_colors.py).
    static let warning = Color("WarningColor")
}

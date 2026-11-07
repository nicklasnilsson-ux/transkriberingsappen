import SwiftUI

/// Appens ikoner. De kommer från Material Design Icons (stilen Rounded, Apache 2.0) och ligger som
/// ikonuppsättningar i resurskatalogen under `Icons`. Hämtas med `scripts/material_icons.py`.
/// I macOS egna ytor (Inställningar, titelbaren, menyerna) används SF Symbols via `SystemIcon` i stället.
///
/// Namnen här är samma som i skriptet. Varje fall har en uppsättning `icon-<namn>`.
enum AppIcon: String, CaseIterable {
    case check, checkCircle, cancel, chevronDown, unfold, circle, clock, copy
    case download, downloadCircle, group, history, info
    case lightbulb, memory, movie, openInFull, closeFullscreen, pause, personQuestion, play, playCircle
    case record, refresh, search, share, tune, visibility, visibilityOff, warning, waveform

    var assetName: String { "icon-\(rawValue)" }
}

extension Image {
    /// Ikonen i sin egen storlek (16 pt), målad i förgrundsfärgen. För andra storlekar: `Icon`.
    /// Ritas alltid om i den upplösning den visas i (se `AppIcon.crispImage`).
    init(icon: AppIcon) {
        self = icon.crispImage(size: 16)
    }
}

extension Label where Title == Text, Icon == Image {
    init<S: StringProtocol>(_ title: S, icon: AppIcon) {
        self.init {
            Text(title)
        } icon: {
            Image(icon: icon)
        }
    }
}

/// En ikon i vald storlek. Följer förgrundsfärgen.
struct Icon: View {
    let icon: AppIcon
    var size: CGFloat = 16

    init(_ icon: AppIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(icon: icon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension AppIcon {
    /// Ikonen som en bild som ritas om i den upplösning den visas i. En vanlig `Image("namn")` av en
    /// 16 pt stor SVG blir i listor, knappar och menyer en bitmapp i 16 pt som sedan förstoras till
    /// Retina-skärmens pixlar, och blir suddig. Här ritas vektorn först när bilden visas, med
    /// skärmens skala. Bilden är en mall och följer förgrundsfärgen.
    func crispImage(size: CGFloat) -> Image {
        let source = NSImage(named: assetName)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return Image(nsImage: image).renderingMode(.template)
    }
}

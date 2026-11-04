import AppKit
import SwiftUI

/// Appens ikoner. De kommer från Material Design Icons (stilen Rounded, Apache 2.0) och ligger som
/// ikonuppsättningar i resurskatalogen under `Icons`. Hämtas med `scripts/material_icons.py`.
/// SF Symbols används inte; `scripts/test_icons.py` stoppar det.
///
/// Namnen här är samma som i skriptet. Varje fall har en uppsättning `icon-<namn>`.
enum AppIcon: String, CaseIterable {
    case check, checkCircle, cancel, chevronDown, chevronUp, unfold, circle, clock, copy, chip
    case download, downloadCircle, edit, fullscreen, fullscreenExit, group, hand, history, info
    case lightbulb, memory, more, movie, openInFull, pause, personQuestion, play, playCircle
    case record, refresh, search, share, sync, tune, visibility, visibilityOff, warning, waveform

    var assetName: String { "icon-\(rawValue)" }
}

extension Image {
    /// Ikonen i sin egen storlek (16 pt), målad i förgrundsfärgen. För andra storlekar: `Icon`.
    init(icon: AppIcon) {
        self.init(icon.assetName)
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
    /// Ikonen som en bild som ritas om i den upplösning den visas i. Behövs där macOS gör egna bilder
    /// av ikonen, till exempel flikraden i Inställningar: där blir en vanlig `Image(icon:)` en
    /// bitmapp i 16 pt och suddig på Retina-skärmar. Ritningen sker först när bilden visas, med
    /// skärmens skala, och bilden är en mall som följer förgrundsfärgen.
    func crispImage(size: CGFloat) -> Image {
        let source = NSImage(named: assetName)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return Image(nsImage: image)
    }
}

/// Fliketikett med skarp ikon (se `AppIcon.crispImage`). 24 pt är den storlek flikraden i Inställningar visar.
struct CrispTabLabel: View {
    let title: String
    let icon: AppIcon

    var body: some View {
        Label {
            Text(title)
        } icon: {
            icon.crispImage(size: 24)
        }
    }
}

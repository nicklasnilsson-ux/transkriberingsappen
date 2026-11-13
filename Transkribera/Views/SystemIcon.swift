import AppKit
import SwiftUI

/// Ikoner i macOS egna ytor: Inställningars flikar, titelbaren och menyerna. Där används SF Symbols,
/// eftersom de följer systemets textstorlek, tyngd och baslinje (beslut Nicklas 2026-11-07).
/// Appens egna ytor (sidopanelens rader, spelarraden, texten) använder `AppIcon` (Material).
///
/// SF Symbols får bara hämtas här. `scripts/test_icons.py` stoppar `systemName:` i andra filer och
/// begränsar `SystemIcon` till systemytorna; `SystemIconTests` kontrollerar att varje symbol finns.
enum SystemIcon: String, CaseIterable {
    // Inställningar
    case transcription = "waveform"
    case models = "cpu"
    case privacy = "hand.raised"
    case updates = "arrow.triangle.2.circlepath"
    // Titelbaren
    case olderVersion = "clock"
    case search = "magnifyingglass"
    case previousHit = "chevron.up"
    case nextHit = "chevron.down"
    case saved = "checkmark"
    case edit = "pencil"
    case more = "ellipsis.circle"
    // Menyer
    case anonymize = "eye.slash"
    case showNames = "eye"
    case ownWindow = "macwindow.badge.plus"
    case backToPlayer = "arrow.uturn.backward"
    case listen = "play.fill"

    var symbolName: String { rawValue }
}

extension SystemIcon {
    /// För menyrader som AppKit ritar (`AppMenu`).
    var nsImage: NSImage? { NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) }
}

extension Image {
    init(systemIcon: SystemIcon) {
        self.init(systemName: systemIcon.symbolName)
    }
}

extension Label where Title == Text, Icon == Image {
    init<S: StringProtocol>(_ title: S, systemIcon: SystemIcon) {
        self.init {
            Text(title)
        } icon: {
            Image(systemIcon: systemIcon)
        }
    }
}

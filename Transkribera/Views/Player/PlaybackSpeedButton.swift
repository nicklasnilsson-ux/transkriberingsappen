import AppKit
import SwiftUI
import TranskriberaCore

/// Uppspelningshastigheten i spelarraden (Nicklas 2026-11-07, variant A i
/// design/uppspelningshastighet-skiss.html): en liten knapp med aktuell hastighet som öppnar en meny
/// med alla steg. Knappen blir indigo när hastigheten inte är 1×, så att man ser att man lyssnar
/// snabbare eller långsammare.
///
/// Knappen ritas av appen själv och menyn är en vanlig `NSMenu` (se `AppMenu`). En SwiftUI-`Menu` ritas av macOS,
/// som kan strunta i färgerna (så blev det med playknappen i 0.9.2–0.9.14). `PlaybackSpeedTests`
/// läser färgerna i den ritade knappen.
struct PlaybackSpeedButton: View {
    @Binding var speed: Double
    /// Utan pilen, för spelarraden i ett smalt fönster.
    var compact = false
    @State private var anchor = MenuAnchor()

    private var isActive: Bool { !PlaybackSpeed.isNormal(speed) }

    var body: some View {
        Button {
            anchor.show(PlaybackSpeedMenu.entries(selected: speed) { speed = $0 })
        } label: {
            HStack(spacing: 2) {
                Text(PlaybackSpeed.label(speed))
                    .font(.app(.small, weight: isActive ? .semibold : .regular, design: .monospaced))
                    // Lika bred för alla steg, så att raden inte hoppar när hastigheten byts.
                    .frame(minWidth: 38, alignment: .leading)
                if !compact { Icon(.chevronDown, size: 14) }
            }
            .padding(.trailing, compact ? 4 : 0)
        }
        .buttonStyle(SpeedButtonStyle(isActive: isActive))
        .background(MenuAnchorView(anchor: anchor))
        .fixedSize()
        .help("Uppspelningshastighet (⌥⌘→ snabbare, ⌥⌘← långsammare, ⌥⌘0 normal)")
        .accessibilityLabel("Uppspelningshastighet")
        .accessibilityValue(PlaybackSpeed.menuLabel(speed))
    }
}

/// Knappens utseende: tunn kant och sekundär textfärg vid 1×, indigo kant, text och svag platta annars.
struct SpeedButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .foregroundStyle(isActive ? Color.accentColor : Color.textSecondary)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 3)
            .background(shape.fill(isActive ? Color.accentColor.opacity(0.12) : Color.clear))
            .overlay(shape.strokeBorder(isActive ? Color.accentColor : Color.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}

/// Menyn under hastighetsknappen: rubrik och alla steg, med bock på det valda.
@MainActor
enum PlaybackSpeedMenu {
    static func entries(selected: Double, onPick: @escaping (Double) -> Void) -> [AppMenuEntry] {
        let current = PlaybackSpeed.clamped(selected)
        // Rubriken överst (Nicklas 2026-11-07), ritad av appen så att den uppfyller kontrastkravet.
        let choices = PlaybackSpeed.steps.map { step -> AppMenuEntry in
            .choice(PlaybackSpeed.menuLabel(step), checked: step == current) { onPick(step) }
        }
        return [.header("Uppspelningshastighet")] + choices
    }
}

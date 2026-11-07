import AppKit
import SwiftUI
import TranskriberaCore

/// Uppspelningshastigheten i spelarraden (Nicklas 2026-11-07, variant A i
/// design/uppspelningshastighet-skiss.html): en liten knapp med aktuell hastighet som öppnar en meny
/// med alla steg. Knappen blir indigo när hastigheten inte är 1×, så att man ser att man lyssnar
/// snabbare eller långsammare.
///
/// Knappen ritas av appen själv och menyn är en vanlig `NSMenu`. En SwiftUI-`Menu` ritas av macOS,
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
            anchor.showSpeedMenu(selected: speed) { speed = $0 }
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

/// Håller vyn som menyn ska visas under.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
    /// Menyns mål hålls kvar medan menyn är öppen (NSMenuItem håller det bara svagt).
    private var target: SpeedMenuTarget?

    /// Menyn med alla hastigheter, under knappen. Vald hastighet har bock.
    func showSpeedMenu(selected: Double, onPick: @escaping (Double) -> Void) {
        guard let view else { return }
        let target = SpeedMenuTarget(onPick: onPick)
        self.target = target
        let menu = Self.speedMenu(selected: selected, target: target)
        // Vyn är inte vänd (origo nere till vänster), så y = -4 är strax under knappen.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4), in: view)
    }

    static func speedMenu(selected: Double, target: SpeedMenuTarget) -> NSMenu {
        let menu = NSMenu(title: "Uppspelningshastighet")
        let current = PlaybackSpeed.clamped(selected)
        // Rubrik överst (Nicklas 2026-11-07), i macOS egen stil för sektionsrubriker.
        menu.addItem(NSMenuItem.sectionHeader(title: "Uppspelningshastighet"))
        for step in PlaybackSpeed.steps {
            let item = NSMenuItem(title: PlaybackSpeed.menuLabel(step), action: #selector(SpeedMenuTarget.pick(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = step
            item.state = step == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
}

@MainActor
final class SpeedMenuTarget: NSObject {
    let onPick: (Double) -> Void

    init(onPick: @escaping (Double) -> Void) {
        self.onPick = onPick
    }

    @objc func pick(_ sender: NSMenuItem) {
        guard let speed = sender.representedObject as? Double else { return }
        onPick(speed)
    }
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

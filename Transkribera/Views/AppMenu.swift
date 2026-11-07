import AppKit
import SwiftUI

/// Menyer som öppnas från en knapp i appen (hastighet, bildstorlek, versioner).
///
/// macOS ritar rubriker och förklarande rader i menyer (`Section`, inline-`Picker`,
/// sektionsrubriker i `NSMenu`, `Text` i en `Menu`) i ljusgrått. I Nicklas skärmbild 2026-11-07 hade
/// rubriken Bildstorlek kontrasten 1,9:1 mot menyn, långt under kravet 4,5:1. Här ritas rubriker och
/// förklaringar därför av appen själv, i `TextSecondary` (5,6:1 mot menyn i ljust läge). Kontrolleras
/// av `scripts/test_menu_contrast.py` och `PlaybackSpeedTests`.
enum AppMenuEntry {
    /// Rubrik överst eller över en grupp. Kan inte väljas.
    case header(String)
    /// Förklarande text, t.ex. om hur många versioner som sparas. Kan inte väljas.
    case note(String)
    /// Ett val med bock när det gäller.
    case choice(String, checked: Bool, action: () -> Void)
    /// En vanlig åtgärd.
    case action(String, action: () -> Void)
    case separator
}

@MainActor
enum AppMenu {
    /// Färg för rubriker och förklaringar; texten är 12 pt (`AppTextSize.small`).
    static let textColorName = "TextSecondary"

    static func make(_ entries: [AppMenuEntry], target: AppMenuTarget) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .header(let title):
                menu.addItem(textItem(title, bold: true))
            case .note(let text):
                menu.addItem(textItem(text, bold: false))
            case .choice(let title, let checked, let action):
                let item = actionItem(title, action: action, target: target)
                item.state = checked ? .on : .off
                menu.addItem(item)
            case .action(let title, let action):
                menu.addItem(actionItem(title, action: action, target: target))
            case .separator:
                menu.addItem(.separator())
            }
        }
        return menu
    }

    private static func actionItem(_ title: String, action: @escaping () -> Void, target: AppMenuTarget) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(AppMenuTarget.run(_:)), keyEquivalent: "")
        item.target = target
        item.tag = target.add(action)
        item.isEnabled = true
        return item
    }

    /// En rad som appen ritar själv: text i `TextSecondary`, som följer ljust/mörkt läge och Öka kontrast.
    static func textItem(_ text: String, bold: Bool) -> NSMenuItem {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .app(.small, weight: bold ? .semibold : .regular)
        label.textColor = NSColor(named: textColorName) ?? .secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = 260
        let size = label.fittingSize
        // Samma vänsterkant som rubriker i macOS menyer, lite luft över och under.
        let inset = NSEdgeInsets(top: 3, left: 12, bottom: 3, right: 12)
        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: size.width + inset.left + inset.right,
                                             height: size.height + inset.top + inset.bottom))
        label.frame = NSRect(x: inset.left, y: inset.bottom, width: size.width, height: size.height)
        container.addSubview(label)
        container.setAccessibilityElement(false)
        let item = NSMenuItem()
        item.view = container
        item.isEnabled = false
        item.title = text
        return item
    }
}

/// Håller åtgärderna medan menyn är öppen (NSMenuItem håller sitt mål bara svagt).
@MainActor
final class AppMenuTarget: NSObject {
    private var actions: [() -> Void] = []

    func add(_ action: @escaping () -> Void) -> Int {
        actions.append(action)
        return actions.count - 1
    }

    @objc func run(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

/// Håller vyn som menyn ska visas under.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
    private var target: AppMenuTarget?

    /// Visar menyn strax under knappen.
    func show(_ entries: [AppMenuEntry]) {
        guard let view else { return }
        let target = AppMenuTarget()
        self.target = target
        let menu = AppMenu.make(entries, target: target)
        // Vyn är inte vänd (origo nere till vänster), så y = -4 är strax under knappen.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4), in: view)
    }
}

/// Lägg som `.background` på knappen som öppnar menyn.
struct MenuAnchorView: NSViewRepresentable {
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

/// En knapp med egen etikett som öppnar en `AppMenu` under sig. Varje knapp har sitt eget ankare,
/// så att den fungerar även när vyn byggs i flera varianter (t.ex. i `ViewThatFits`).
struct AppMenuButton<Label: View>: View {
    let entries: () -> [AppMenuEntry]
    @ViewBuilder let label: () -> Label
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            anchor.show(entries())
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
    }
}

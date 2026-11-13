import AppKit
import TranskriberaCore

/// Den lilla menyn vid ett prickat understruket ord (experimentet Korskolla, `CrossCheck`):
/// de två tolkningarna och Lyssna. Inget mer (beslut Nicklas 2026-11-13: "det ser ut som att
/// beslutet som ska tas är mycket större än vad det är" om ett större förslag).
///
/// Menyn öppnas där man klickade. Lyssna stänger inte menyn, så att man kan lyssna och sedan välja.
@MainActor
final class CrossCheckMenu {
    private var target: AppMenuTarget?
    private var listenTarget: ListenTarget?

    func show(current: String, alternative: String, onKeep: @escaping () -> Void, onChoose: @escaping () -> Void, onListen: (() -> Void)?) {
        let target = AppMenuTarget()
        self.target = target
        let menu = AppMenu.make([
            .choice(current, checked: true, action: onKeep),
            .choice(alternative, checked: false, action: onChoose)
        ], target: target)
        if let onListen {
            let listen = ListenTarget(action: onListen)
            listenTarget = listen
            menu.addItem(.separator())
            menu.addItem(Self.listenItem(target: listen))
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Lyssna som en knapp i menyn: en vanlig menyrad skulle stänga menyn.
    private static func listenItem(target: ListenTarget) -> NSMenuItem {
        let button = NSButton(title: "Lyssna", image: SystemIcon.listen.nsImage ?? NSImage(), target: target, action: #selector(ListenTarget.run))
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = .menuFont(ofSize: 0)
        button.contentTintColor = .labelColor
        button.setAccessibilityHelp("Spelar två ord före till två ord efter. Menyn är kvar.")
        button.sizeToFit()
        // Samma vänsterkant som texten i menyraderna ovanför (efter bockkolumnen).
        let container = NSView(frame: NSRect(x: 0, y: 0, width: button.frame.width + 40, height: 24))
        button.frame.origin = NSPoint(x: 18, y: (24 - button.frame.height) / 2)
        container.addSubview(button)
        let item = NSMenuItem()
        item.view = container
        item.title = "Lyssna"
        return item
    }
}

/// Håller Lyssna-åtgärden medan menyn är öppen.
@MainActor
private final class ListenTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func run() { action() }
}

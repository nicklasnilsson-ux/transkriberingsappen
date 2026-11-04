import AVKit
import AppKit

/// Visar videon i helskärm i ett eget fönster med AVKits spelkontroller (de tonar fram när musen rör sig).
/// Samma AVPlayer som i spelarraden, så läget i filmen följer med. Esc eller knappen i kontrollpanelen lämnar helskärmen och stänger fönstret.
@MainActor
enum VideoFullscreen {
    private static var window: NSWindow?
    private static var observers: [NSObjectProtocol] = []

    static func present(player: AVPlayer) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        // AVKits egen helskärmsknapp lämnade fönstret kvar (0.9.2). Den ersätts av vår egen knapp nedan.
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Video"
        window.contentView = container(for: view)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { window.close() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { cleanup() }
            },
        ]
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    /// Videon med en knapp överst till vänster som lämnar helskärmen och stänger videofönstret,
    /// så att man är tillbaka i appens läge (liten, mellan, stor). Esc gör samma sak.
    private static func container(for playerView: AVPlayerView) -> NSView {
        let container = NSView()
        playerView.frame = container.bounds
        playerView.autoresizingMask = [.width, .height]
        container.addSubview(playerView)

        let button = NSButton(title: "Tillbaka till appen", target: closeTarget, action: #selector(CloseTarget.close))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.toolTip = "Lämna helskärmen och gå tillbaka till appen (Esc)"
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
        ])
        return container
    }

    private static let closeTarget = CloseTarget()

    /// Knappens mål. Utan helskärm stänger det fönstret direkt, annars lämnas helskärmen och fönstret stängs då.
    @MainActor
    private final class CloseTarget: NSObject {
        @objc func close() {
            guard let window = VideoFullscreen.window else { return }
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            } else {
                window.close()
            }
        }
    }

    private static func cleanup() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        window?.contentView = nil
        window = nil
    }
}

import AVKit
import AppKit

/// Visar videon i helskärm i ett eget fönster med AVKits spelkontroller (de tonar fram när musen rör sig).
/// Samma AVPlayer som i spelarraden, så läget i filmen följer med. Esc lämnar helskärmen och stänger fönstret.
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
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Video"
        window.contentView = view
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

    private static func cleanup() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        window?.contentView = nil
        window = nil
    }
}

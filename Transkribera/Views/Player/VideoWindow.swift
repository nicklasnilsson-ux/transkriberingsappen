import AVKit
import AppKit
import Observation

/// Videon i ett eget, vanligt fönster som går att flytta och ändra storlek på genom att dra i hörnet
/// (Nicklas 2026-11-07, ersätter Helskärm). Samma AVPlayer som i spelarraden, så läget i filmen följer med.
///
/// Medan fönstret är öppet visas videon bara där: spelarraden visar en platshållare med Tillbaka hit,
/// så att samma video inte syns på två ställen. Videon läggs tillbaka i spelarraden när fönstret stängs
/// (stängknappen eller ⌘W), med Tillbaka hit eller med Tillbaka till spelarraden i bildstorleksmenyn.
/// Fönstrets storlek och plats sparas mellan gångerna. Helskärm finns kvar via fönstrets gröna knapp.
@MainActor
@Observable
final class VideoWindow {
    static let shared = VideoWindow()

    /// Spelaren som visas i fönstret, nil när fönstret är stängt.
    private(set) var player: AVPlayer?

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var closeObserver: NSObjectProtocol?

    /// Sant när just den här spelarens video visas i fönstret (och därför inte i spelarraden).
    func isShowing(_ player: AVPlayer) -> Bool {
        self.player === player
    }

    func open(player: AVPlayer, title: String) {
        if let window, self.player === player {
            window.makeKeyAndOrderFront(nil)
            return
        }
        close()

        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        // Helskärm sköts av fönstrets gröna knapp, som alla andra fönster.
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = .resizeAspect

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = view
        window.contentMinSize = NSSize(width: 240, height: 135)
        // Hörnet följer videons form, så att draget inte ger svarta kanter.
        window.contentAspectRatio = Self.aspectRatio(of: player)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.center()
        // Storlek och plats från förra gången, om det finns.
        window.setFrameAutosaveName("Videofönster")

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            // Stängknappen eller ⌘W. Bara det fönster som visas nu städas undan.
            MainActor.assumeIsolated {
                guard let self, let window, self.window === window else { return }
                self.tearDown()
            }
        }
        self.window = window
        self.player = player
        window.makeKeyAndOrderFront(nil)
    }

    /// Stänger fönstret, och videon kommer tillbaka i spelarraden.
    func close() {
        guard let window else { return }
        tearDown()
        window.close()
    }

    /// Stänger fönstret om det visar den här spelaren (när filen byts eller vyn stängs).
    func closeIfShowing(_ player: AVPlayer) {
        if isShowing(player) { close() }
    }

    /// Släpper fönstret och spelaren. Spelarraden visar då videon igen.
    private func tearDown() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        (window?.contentView as? AVPlayerView)?.player = nil
        window?.contentView = nil
        window = nil
        player = nil
    }

    private static func aspectRatio(of player: AVPlayer) -> NSSize {
        let size = player.currentItem?.presentationSize ?? .zero
        return size.width > 0 && size.height > 0 ? size : NSSize(width: 16, height: 9)
    }
}

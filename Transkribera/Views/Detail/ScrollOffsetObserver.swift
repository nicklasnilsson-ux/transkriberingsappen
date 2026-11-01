import AppKit
import SwiftUI

/// Läser hur långt en SwiftUI-`ScrollView` är skrollad, direkt från AppKits `NSScrollView`.
/// Läggs som bakgrund på innehållet. Pålitligare än att mäta med `GeometryReader`, som på
/// macOS 14 inte alltid rapporterar under pågående skrollning.
struct ScrollOffsetObserver: NSViewRepresentable {
    /// Antal punkter innehållet är skrollat från toppen (0 = överst).
    var onChange: (Double) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: (Double) -> Void = { _ in }
        private var observed: NSClipView?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard observed == nil, let scrollView = enclosingScrollView else { return }
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            observed = clip
            token = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.report(scrollView)
            }
            report(scrollView)
        }

        private func report(_ scrollView: NSScrollView) {
            // Innehållet börjar under verktygsfältet (negativ origin), så insättningen räknas bort.
            onChange(Double(scrollView.contentView.bounds.origin.y + scrollView.contentInsets.top))
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}

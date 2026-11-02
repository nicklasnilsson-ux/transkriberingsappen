import AppKit
import SwiftUI

/// Läser hur långt en SwiftUI-`ScrollView` är skrollad, direkt från AppKits `NSScrollView`.
/// Läggs som bakgrund på innehållet. Pålitligare än att mäta med `GeometryReader`, som på
/// macOS 14 inte alltid rapporterar under pågående skrollning.
struct ScrollOffsetObserver: NSViewRepresentable {
    /// Antal punkter innehållet är skrollat från toppen (0 = överst).
    var onChange: (Double) -> Void
    /// Får en referens till skrollvyn, så att den kan skrollas när ett stycke ska stå kvar.
    var anchor: ScrollAnchor? = nil

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        view.anchor = anchor
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
        view.anchor = anchor
        if let scrollView = view.enclosingScrollView { view.anchor?.scrollView = scrollView }
    }

    final class ProbeView: NSView {
        var onChange: (Double) -> Void = { _ in }
        weak var anchor: ScrollAnchor?
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
            anchor?.scrollView = scrollView
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

/// Håller stycket du läser på samma plats på skärmen när redigeringsläget slås av eller på.
/// Raderna rapporterar var de ligger i fönstret (`RowFrameReporter`). Före bytet väljs raden
/// som ligger vid fönstrets överkant; efter bytet skrollas lika mycket som den raden flyttade sig.
final class ScrollAnchor {
    weak var scrollView: NSScrollView?
    /// Radernas överkant i förhållande till fönstrets överkant, bara för rader som visas.
    var rowTops: [AnyHashable: CGFloat] = [:]

    /// Raden vid fönstrets överkant: den som börjar ovanför och närmast kanten, annars den första under.
    func currentAnchor() -> (id: AnyHashable, top: CGFloat)? {
        let above = rowTops.filter { $0.value <= 0 }.max { $0.value < $1.value }
        let below = rowTops.filter { $0.value > 0 }.min { $0.value < $1.value }
        guard let row = above ?? below else { return nil }
        return (row.key, row.value)
    }

    /// Skrollar så att raden står där den stod, när den nya layouten är klar.
    func restore(_ anchor: (id: AnyHashable, top: CGFloat)) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let scrollView = self.scrollView, let top = self.rowTops[anchor.id] else { return }
            let delta = top - anchor.top
            guard abs(delta) > 0.5 else { return }
            let clip = scrollView.contentView
            var origin = clip.bounds.origin
            origin.y += delta
            // Inte förbi början eller slutet av texten.
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
            scrollView.reflectScrolledClipView(clip)
        }
    }
}

/// Rapporterar radens överkant i skrollytan till `ScrollAnchor`. Skriver bara till en vanlig
/// klass, så att vyn inte ritas om när man skrollar.
struct RowFrameReporter: View {
    let id: AnyHashable
    let anchor: ScrollAnchor
    let space: String

    var body: some View {
        GeometryReader { geo in
            let top = geo.frame(in: .named(space)).minY
            Color.clear
                .onAppear { anchor.rowTops[id] = top }
                .onChange(of: top) { _, newTop in anchor.rowTops[id] = newTop }
                .onDisappear { anchor.rowTops[id] = nil }
        }
    }
}

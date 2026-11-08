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
        private var liveScrollTokens: [NSObjectProtocol] = []
        private var wheelMonitor: Any?

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
            watchUserScrolling(scrollView)
        }

        /// Noterar när du själv skrollar (mushjul, styrplatta eller rullningslisten), så att
        /// "Följ uppspelning" inte drar tillbaka texten mitt i. Programmerad skrollning räknas inte.
        private func watchUserScrolling(_ scrollView: NSScrollView) {
            for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
                liveScrollTokens.append(NotificationCenter.default.addObserver(
                    forName: name, object: scrollView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.anchor?.noteUserScroll() }
                })
            }
            // Ett vanligt mushjul ger inga live-scroll-notiser, så hjulhändelserna läses också.
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak scrollView] event in
                if let self, let scrollView, event.window === scrollView.window,
                   scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)) {
                    self.anchor?.noteUserScroll()
                }
                return event
            }
        }

        private func report(_ scrollView: NSScrollView) {
            // Innehållet börjar under verktygsfältet (negativ origin), så insättningen räknas bort.
            onChange(Double(scrollView.contentView.bounds.origin.y + scrollView.contentInsets.top))
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
            liveScrollTokens.forEach { NotificationCenter.default.removeObserver($0) }
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        }
    }
}

/// Håller stycket du läser på samma plats på skärmen när redigeringsläget slås av eller på.
/// Raderna registrerar en osynlig vy (`RowFrameReporter`). Läget läses först när det behövs:
/// före bytet väljs raden som ligger vid fönstrets överkant; efter bytet skrollas lika mycket
/// som den raden flyttade sig. Under skrollning görs alltså inget arbete per rad (0.9.33).
final class ScrollAnchor {
    weak var scrollView: NSScrollView?
    private struct WeakView { weak var view: NSView? }
    private var rowViews: [AnyHashable: WeakView] = [:]
    /// När du senast skrollade själv.
    private(set) var lastUserScroll: Date?
    /// Så länge efter att du slutat skrolla väntar "Följ uppspelning" innan texten följer med igen.
    static let followPause: TimeInterval = 3

    func register(_ id: AnyHashable, view: NSView) { rowViews[id] = WeakView(view: view) }
    func unregister(_ id: AnyHashable, view: NSView) {
        if rowViews[id]?.view === view { rowViews[id] = nil }
    }

    /// Radernas överkant i förhållande till fönstrets överkant, bara för rader som visas.
    var rowTops: [AnyHashable: CGFloat] {
        guard let clip = scrollView?.contentView else { return [:] }
        var result: [AnyHashable: CGFloat] = [:]
        for (id, box) in rowViews {
            guard let view = box.view, view.window != nil else { continue }
            let rect = view.convert(view.bounds, to: clip)
            // Vyerna är vända (y växer nedåt); annars räknas från nederkanten.
            result[id] = clip.isFlipped ? rect.minY - clip.bounds.origin.y : -(rect.maxY - clip.bounds.maxY)
        }
        return result
    }

    func noteUserScroll(at date: Date = Date()) { lastUserScroll = date }

    /// Sant om du har skrollat själv inom `followPause` sekunder.
    func userScrolledRecently(now: Date = Date()) -> Bool {
        guard let lastUserScroll else { return false }
        return now.timeIntervalSince(lastUserScroll) < Self.followPause
    }

    /// Raden vid fönstrets överkant: den som börjar ovanför och närmast kanten, annars den första under.
    func currentAnchor() -> (id: AnyHashable, top: CGFloat)? {
        let tops = rowTops
        let above = tops.filter { $0.value <= 0 }.max { $0.value < $1.value }
        let below = tops.filter { $0.value > 0 }.min { $0.value < $1.value }
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

/// Registrerar radens plats hos `ScrollAnchor` med en osynlig vy. Ingen `GeometryReader` och
/// ingen `onChange` per rad: förut skrevs radens läge vid varje skrollsteg för varje rad som visades.
struct RowFrameReporter: NSViewRepresentable {
    let id: AnyHashable
    let anchor: ScrollAnchor

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.id = id
        view.anchor = anchor
        anchor.register(id, view: view)
        return view
    }

    func updateNSView(_ view: Probe, context: Context) {
        view.id = id
        view.anchor = anchor
        anchor.register(id, view: view)
    }

    static func dismantleNSView(_ view: Probe, coordinator: ()) {
        view.anchor?.unregister(view.id, view: view)
    }

    final class Probe: NSView {
        var id: AnyHashable = 0
        weak var anchor: ScrollAnchor?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

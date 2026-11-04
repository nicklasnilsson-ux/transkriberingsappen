import AppKit
import SwiftData
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Hela fönstret (ContentView) i Fil-läget och i Mötesinspelning: inget i fönstret får ligga utanför
/// fönstrets yta, och mötesläget får inte kräva ett högre fönster än Fil-läget (Nicklas 2026-11-04:
/// sidopanelen hamnade ovanför appens övre kant vid Mötesinspelning).
@MainActor
final class WindowLayoutTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    private struct Measurement {
        var ideal: CGSize
        var frames: [String]
        var outside: [String]
    }

    private func measure(mode: AppMode, size: CGSize) -> Measurement {
        let appState = AppState()
        appState.mode = mode
        let queue = TranscriptionQueue(transcriber: TranscriberService(), context: container.mainContext)
        let recorder = MeetingRecorder()
        let root = ContentView()
            .environment(appState)
            .environment(queue)
            .environment(recorder)
            .modelContainer(container)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false
        )
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()

        var frames: [String] = []
        var outside: [String] = []
        let bounds = host.bounds
        func walk(_ view: NSView, depth: Int) {
            let name = String(describing: type(of: view))
            let interesting = name.contains("Scroll") || name.contains("Split") || name.contains("Hosting")
                || name.contains("TableView") || name.contains("Outline") || name.contains("Clip")
            let rect = host.convert(view.bounds, from: view)
            if interesting, depth < 14 {
                frames.append("\(String(repeating: " ", count: depth))\(name) x:\(Int(rect.minX)) y:\(Int(rect.minY)) w:\(Int(rect.width)) h:\(Int(rect.height))")
            }
            if interesting, rect.width > 1, rect.height > 1,
               rect.minY < bounds.minY - 1 || rect.maxY > bounds.maxY + 1 {
                outside.append("\(name) y:\(Int(rect.minY))…\(Int(rect.maxY)) mot fönstret 0…\(Int(bounds.maxY))")
            }
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        walk(host, depth: 0)
        let ideal = host.fittingSize
        window.contentView = nil
        return Measurement(ideal: ideal, frames: frames, outside: outside)
    }

    private func fitting<V: View>(_ view: V, width: CGFloat) -> CGSize {
        let appState = AppState()
        appState.mode = .meeting
        let queue = TranscriptionQueue(transcriber: TranscriberService(), context: container.mainContext)
        let host = NSHostingView(rootView: view
            .environment(appState).environment(queue).environment(MeetingRecorder())
            .modelContainer(container))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 626)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// Höjden på NSSplitView för en navigationsyta med given sidopanel och detaljvy.
    private func splitHeight<D: View>(mode: AppMode, sidebar: Bool, @ViewBuilder detail: () -> D) -> Int {
        let appState = AppState()
        appState.mode = mode
        let queue = TranscriptionQueue(transcriber: TranscriberService(), context: container.mainContext)
        let detailView = detail()
        let root = NavigationSplitView {
            if sidebar {
                SidebarView(selection: .constant(nil), multiSelection: .constant([]))
            } else {
                Text("sidopanel")
            }
        } detail: { detailView }
            .frame(minWidth: 820, minHeight: 540)
            .environment(appState).environment(queue).environment(MeetingRecorder())
            .modelContainer(container)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 650)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        var result = -1
        func walk(_ v: NSView) {
            if v is NSSplitView, result < 0 { result = Int(v.frame.height) }
            v.subviews.forEach(walk)
        }
        walk(host)
        window.contentView = nil
        return result
    }

    private struct QueryOnly: View {
        @Query private var all: [Transcript]
        var body: some View { Color.clear.overlay { Text("\(all.count)").hidden() } }
    }
    private struct RecorderOnly: View {
        @Environment(MeetingRecorder.self) private var recorder
        var body: some View { Color.clear.overlay { Text("\(recorder.isBusy ? 1 : 0)").hidden() } }
    }
    private func wrap<V: View>(_ v: V) -> some View {
        v.frame(maxWidth: 420).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func testMeetingModeDoesNotNeedAHigherWindowThanFileMode() {
        let long = "Spelar in allt ljud som hörs på datorn tills du stoppar. Texten skapas när inspelningen är klar."
        var out: [String] = []
        func add(_ name: String, _ h: Int) { out.append("\(name)=\(h)") }
        add("ikon", splitHeight(mode: .meeting, sidebar: false) { wrap(Icon(.record, size: 48)) })
        add("ikonAccent", splitHeight(mode: .meeting, sidebar: false) { wrap(Icon(.record, size: 48).foregroundStyle(Color.accentColor)) })
        add("titel2", splitHeight(mode: .meeting, sidebar: false) { wrap(Text("Redo").font(.title2.weight(.semibold))) })
        add("callout", splitHeight(mode: .meeting, sidebar: false) {
            wrap(Text(long).font(.callout).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true))
        })
        add("vstack3", splitHeight(mode: .meeting, sidebar: false) {
            wrap(VStack(spacing: 14) { Icon(.record, size: 48); Text("Redo").font(.title2); Text(long).font(.callout).fixedSize(horizontal: false, vertical: true) })
        })
        add("medNavTitel", splitHeight(mode: .meeting, sidebar: false) { wrap(Icon(.record, size: 48)).navigationTitle("Mötesinspelning") })
        add("query", splitHeight(mode: .meeting, sidebar: false) { QueryOnly() })
        add("recorder", splitHeight(mode: .meeting, sidebar: false) { RecorderOnly() })
        XCTFail("VARIANTER " + out.joined(separator: " ¦ "))
    }
}

import AppKit
import SwiftData
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Hela fönstret (ContentView) i Fil-läget och i Mötesinspelning: inget i fönstret får ligga utanför
/// fönstrets yta. Felet 2026-11-04: en text med fixedSize(vertical:) i mötesvyn gjorde splitvyn ca 1340 pt
/// hög i ett fönster på 626 pt, så sidopanelen hamnade ovanför appens överkant.
@MainActor
final class WindowLayoutTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    /// Delar av fönstret som ligger utanför dess yta, som text. Tom lista = allt ryms.
    private func viewsOutsideWindow(mode: AppMode) -> [String] {
        let appState = AppState()
        appState.mode = mode
        let queue = TranscriptionQueue(transcriber: TranscriberService(), context: container.mainContext)
        let root = ContentView()
            .environment(appState)
            .environment(queue)
            .environment(MeetingRecorder())
            .modelContainer(container)
        let size = CGSize(width: 1000, height: 650)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()

        var outside: [String] = []
        let bounds = host.bounds
        func walk(_ view: NSView) {
            let name = String(describing: type(of: view))
            let rect = host.convert(view.bounds, from: view)
            if name.contains("Split") || name.contains("Scroll"), rect.width > 1, rect.height > 1,
               rect.minY < bounds.minY - 1 || rect.maxY > bounds.maxY + 1 {
                outside.append("\(name.prefix(40)) höjd \(Int(rect.height)) mot fönstret \(Int(bounds.height))")
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        window.contentView = nil
        return outside
    }

    func testFileModeFitsInTheWindow() {
        XCTAssertEqual(viewsOutsideWindow(mode: .file), [])
    }

    func testMeetingModeFitsInTheWindow() {
        XCTAssertEqual(viewsOutsideWindow(mode: .meeting), [])
    }
}

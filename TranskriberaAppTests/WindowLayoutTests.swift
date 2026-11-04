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

    func testMeetingModeDoesNotNeedAHigherWindowThanFileMode() {
        let size = CGSize(width: 1000, height: 650)
        let file = measure(mode: .file, size: size)
        let meeting = measure(mode: .meeting, size: size)
        let report = """
        FIL ideal \(file.ideal), utanför: \(file.outside)
        MÖTE ideal \(meeting.ideal), utanför: \(meeting.outside)
        FIL-vyer:
        \(file.frames.joined(separator: "\n"))
        MÖTE-vyer:
        \(meeting.frames.joined(separator: "\n"))
        """
        print(report)
        XCTAssertTrue(file.outside.isEmpty, "Fil-läget har vyer utanför fönstret.\n\(report)")
        XCTAssertTrue(meeting.outside.isEmpty, "Mötesläget har vyer utanför fönstret.\n\(report)")
        XCTAssertLessThanOrEqual(meeting.ideal.height, file.ideal.height + 1, "Mötesläget kräver ett högre fönster.\n\(report)")
        XCTFail("DIAGNOS (tas bort före merge)\n\(report)")
    }
}

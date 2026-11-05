import AppKit
import SwiftData
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Mätning (inte ett test som kan falla): ritar fönstret och skriver ut var sidopanelens delar börjar och slutar i x,
/// rad för rad, så att sidmarginalerna kan jämföras utan en Mac. Raderna börjar med SIDEBAR-MEASURE i CI-loggen.
@MainActor
final class SidebarMeasureTests: XCTestCase {
    func testMeasureSidebarEdges() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        var first: Transcript?
        for name in ["Möte A", "Möte B", "Möte C"] {
            let t = Transcript(title: name, mediaFileName: "x.m4a", originalFileName: "x.m4a", isVideo: false, duration: 20, modelName: "M0")
            t.status = .completed
            container.mainContext.insert(t)
            if first == nil { first = t }
        }
        try container.mainContext.save()

        let appState = AppState()
        appState.selection = first
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
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()

        var out: [String] = []
        // Vy-trädet: tabellrader och deras innehåll (x i förhållande till fönstret).
        func dump(_ view: NSView, depth: Int) {
            let name = String(describing: type(of: view))
            let r = host.convert(view.bounds, from: view)
            if r.minX < 420, depth < 14, name.contains("Table") || name.contains("Row") || name.contains("Cell") || name.contains("Scroll") || name.contains("Split") {
                out.append("SIDEBAR-MEASURE view \(String(repeating: " ", count: depth))\(name.prefix(48)) x \(Int(r.minX))…\(Int(r.maxX)) y \(Int(r.minY))…\(Int(r.maxY))")
            }
            view.subviews.forEach { dump($0, depth: depth + 1) }
        }
        dump(host, depth: 0)

        // Bilden: första och sista färgade kolumnen i varje rad, sammanslagna till band.
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let width = min(rep.pixelsWide, 420 * rep.pixelsWide / Int(size.width))
        let scale = Double(rep.pixelsWide) / Double(size.width)
        out.append("SIDEBAR-MEASURE bild \(rep.pixelsWide)x\(rep.pixelsHigh) skala \(scale)")
        var bands: [(y0: Int, y1: Int, minX: Int, maxX: Int)] = []
        for y in 0..<rep.pixelsHigh {
            guard let bg = rep.colorAt(x: 2, y: y)?.usingColorSpace(.sRGB) else { continue }
            var minX = -1, maxX = -1
            for x in 2..<width {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent)
                if d > 0.06 { if minX < 0 { minX = x }; maxX = x }
            }
            if minX < 0 { continue }
            if let last = bands.last, last.y1 == y - 1, abs(last.minX - minX) <= 1, abs(last.maxX - maxX) <= 1 {
                bands[bands.count - 1].y1 = y
            } else {
                bands.append((y, y, minX, maxX))
            }
        }
        for b in bands where b.y1 - b.y0 >= 1 {
            out.append("SIDEBAR-MEASURE band y \(Int(Double(b.y0) / scale))…\(Int(Double(b.y1) / scale)) x \(Int(Double(b.minX) / scale))…\(Int(Double(b.maxX) / scale))")
        }
        window.contentView = nil
        XCTFail("MÄTNING (felet är avsiktligt, tas bort före merge):\n" + out.prefix(160).joined(separator: "\n"))
    }
}

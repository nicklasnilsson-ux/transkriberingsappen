import AppKit
import SwiftData
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Sidopanelen ritas på riktigt och mäts i pixlar: rutan för ny transkribering och sökfältet ska ha samma
/// vänster- och högerkant som markeringen av en vald rad. Felet 2026-11-05 (0.9.7): rutan låg ca 18 pt
/// innanför markeringen, och två gissade rättningar utan mätning missade.
@MainActor
final class SidebarMarginTests: XCTestCase {
    private struct Band { var y0: Int; var y1: Int; var minX: Int; var maxX: Int }

    func testBoxSearchAndSelectionShareTheSameEdges() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        var oldest: Transcript?
        for name in ["Möte A", "Möte B", "Möte C"] {
            let t = Transcript(title: name, mediaFileName: "x.m4a", originalFileName: "x.m4a", isVideo: false, duration: 20, modelName: "M0")
            t.status = .completed
            container.mainContext.insert(t)
            if oldest == nil { oldest = t }
        }
        try container.mainContext.save()

        let appState = AppState()
        appState.selection = oldest // sist i listan
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
        defer { window.contentView = nil }

        // Listans rader (tabellrader) i fönstrets koordinater, uppifrån.
        var rows: [NSRect] = []
        var sidebarWidth: CGFloat = 0
        func walk(_ view: NSView) {
            let name = String(describing: type(of: view))
            let r = host.convert(view.bounds, from: view)
            if name.contains("ListCoreScrollView") { sidebarWidth = r.width }
            if name == "ListTableRowView" || name.hasPrefix("ListTableRowView") { rows.append(r) }
            view.subviews.forEach(walk)
        }
        walk(host)
        rows.sort { $0.minY < $1.minY }
        XCTAssertGreaterThan(sidebarWidth, 100, "hittade inte sidopanelens lista")
        XCTAssertGreaterThanOrEqual(rows.count, 5, "rutan, rubriken och tre transkriberingar")
        guard rows.count >= 5, sidebarWidth > 100 else { return }

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = Double(rep.pixelsWide) / Double(size.width)
        let limit = Int((Double(sidebarWidth) - 6) * scale) // före avdelaren

        /// Första och sista färgade kolumnen per pixelrad inom `rect`, i punkter. Bakgrunden läses i panelens kant.
        func bands(in rect: NSRect) -> [Band] {
            var result: [Band] = []
            let y0 = max(0, Int(Double(rect.minY) * scale)), y1 = min(rep.pixelsHigh - 1, Int(Double(rect.maxY) * scale) - 1)
            guard y0 <= y1 else { return [] }
            for y in y0...y1 {
                guard let bg = rep.colorAt(x: 1, y: y)?.usingColorSpace(.sRGB) else { continue }
                var minX = -1, maxX = -1
                for x in 1..<limit {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let d = abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent)
                    if d > 0.02 { if minX < 0 { minX = x }; maxX = x }
                }
                if minX < 0 { continue }
                let b = Band(y0: y, y1: y, minX: Int(Double(minX) / scale), maxX: Int(Double(maxX) / scale))
                if var last = result.last, last.y1 == y - 1, last.minX == b.minX, last.maxX == b.maxX {
                    last.y1 = y; result[result.count - 1] = last
                } else { result.append(b) }
            }
            return result
        }
        /// Kanterna för den högsta sammanhängande ytan i raden (rutans eller markeringens kropp).
        func edges(of rect: NSRect) -> (left: Int, right: Int, report: String) {
            let all = bands(in: rect)
            let tallest = all.max { ($0.y1 - $0.y0) < ($1.y1 - $1.y0) }
            let report = all.map { "y\($0.y0)…\($0.y1) x\($0.minX)…\($0.maxX)" }.joined(separator: ", ")
            return (tallest?.minX ?? -1, tallest?.maxX ?? -1, report)
        }

        let box = edges(of: rows[0])
        // Raden med rubrik och sökfält: sökfältet är den bredaste ytan (rubriktexten är kortare).
        let headerBands = bands(in: rows[1])
        let widest = headerBands.max { ($0.maxX - $0.minX) < ($1.maxX - $1.minX) }
        let search = (left: widest?.minX ?? -1, right: widest?.maxX ?? -1,
                      report: headerBands.map { "y\($0.y0)…\($0.y1) x\($0.minX)…\($0.maxX)" }.joined(separator: ", "))
        let selected = edges(of: rows[rows.count - 1])
        let context = "rutan \(box.left)…\(box.right), sök \(search.left)…\(search.right), markering \(selected.left)…\(selected.right) (panel \(Int(sidebarWidth)) pt)\nrutan: \(box.report)\nsök: \(search.report)\nmarkering: \(selected.report)"
        XCTAssertGreaterThan(selected.right - selected.left, 100, "ingen markering hittades. " + context)
        XCTAssertLessThanOrEqual(abs(box.left - selected.left), 1, "vänsterkant ruta mot markering. " + context)
        XCTAssertLessThanOrEqual(abs(box.right - selected.right), 1, "högerkant ruta mot markering. " + context)
        XCTAssertLessThanOrEqual(abs(search.left - selected.left), 1, "vänsterkant sökfält mot markering. " + context)
        XCTAssertLessThanOrEqual(abs(search.right - selected.right), 1, "högerkant sökfält mot markering. " + context)
    }
}

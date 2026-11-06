import AppKit
import SwiftUI
import XCTest
@testable import Transkribera

/// Felet 2026-11-06 (0.9.12): öppnades modellväljaren från Inställningar-kortet i sidopanelen klipptes de
/// förklarande texterna till en rad med … I appens Inställningar-fönster syntes allt. En popover ärver miljön
/// från det den öppnas från, och listraden i sidopanelen begränsade texten. `presentationRoot()` nollställer det.
@MainActor
final class PresentationRootTests: XCTestCase {
    private func height<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// Modellraden och källnoten ritas som de gör i väljaren, en gång i ren miljö och en gång med en radgräns
    /// på en rad utifrån (som från listraden). Med `presentationRoot()` ska de vara lika höga.
    func testExplanatoryTextWrapsEvenWhenTheSourceLimitsLines() {
        let width: CGFloat = 420
        let views: [(String, AnyView)] = [
            ("modellraden Pianissimo", AnyView(ModelInfoRow(model: .pianissimo, isDownloaded: true))),
            ("modellraden KB Large ordagrann", AnyView(ModelInfoRow(model: .kbLargeStrict, isDownloaded: false))),
            ("källnoten", AnyView(ModelSourceNote())),
        ]
        for (name, view) in views {
            let clean = height(view.presentationRoot(), width: width)
            let leakedAndReset = height(view.presentationRoot().lineLimit(1), width: width)
            let leaked = height(view.font(.app(.regular)).lineLimit(1), width: width)
            XCTAssertGreaterThan(clean, 20, "\(name) ritades inte")
            XCTAssertEqual(leakedAndReset, clean, accuracy: 0.5,
                           "\(name) klipps när radgränsen kommer utifrån (\(leakedAndReset) mot \(clean) pt)")
            // Testet måste kunna se felet: utan nollställning blir texten lägre (klippt).
            XCTAssertLessThan(leaked, clean - 5, "\(name): testet ser inte skillnaden, mätningen är fel")
        }
    }

    /// Diagnos: vilken radgräns (m.m.) har en rad i sidopanelens lista? Skrivs i testloggen; stoppar inte bygget.
    func testReportLineLimitInSidebarListRow() {
        var seen: [String] = []
        let probe = LineLimitProbe { seen.append($0) }
        let host = NSHostingView(rootView: List { probe }.listStyle(.sidebar).frame(width: 260, height: 200))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        defer { window.contentView = nil }
        print("PresentationRootTests: lineLimit i sidopanelens listrad = \(seen)")
    }
}

private struct LineLimitProbe: View {
    @Environment(\.lineLimit) private var limit
    @Environment(\.truncationMode) private var truncation
    @Environment(\.allowsTightening) private var tightening
    @Environment(\.minimumScaleFactor) private var scale
    let onRead: (String) -> Void

    var body: some View {
        Color.clear.frame(width: 10, height: 10).onAppear {
            onRead("lineLimit=\(limit.map(String.init) ?? "nil") truncation=\(truncation) tightening=\(tightening) scale=\(scale)")
        }
    }
}

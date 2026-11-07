import AppKit
import SwiftUI
import XCTest
@testable import Transkribera

/// Valt alternativ i modellväljaren har en accentkant utöver den ljusa plattan (Nicklas 2026-11-07).
/// scripts/check_colors.py räknar på färgvärdena; här mäts det som faktiskt ritas, eftersom macOS
/// tidigare har ritat annat än koden bad om (playknappens platta, 0.9.2–0.9.14).
@MainActor
final class SelectionHighlightTests: XCTestCase {
    private let inset: CGFloat = 10

    private func render(selected: Bool, appearance: NSAppearance) throws -> (NSBitmapImageRep, CGFloat) {
        let view = Color.clear
            .frame(width: 160, height: 60)
            .selectionHighlight(selected)
            .padding(inset)
            .background(Color.surface)
        let host = NSHostingView(rootView: view.fixedSize())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return (rep, CGFloat(rep.pixelsWide) / host.bounds.width)
    }

    private func pixel(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat, scale: CGFloat) throws -> NSColor {
        try XCTUnwrap(rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
    }

    private func luminance(_ c: NSColor) -> CGFloat {
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testSelectedRowHasVisibleAccentBorder() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let (rep, scale) = try render(selected: true, appearance: appearance)
            let midY = inset + 30
            // Mitt i kanten (1,5 pt bred), på plattan en bit in och på bakgrunden utanför.
            let border = try pixel(rep, x: inset + 0.5, y: midY, scale: scale)
            let plate = try pixel(rep, x: inset + 20, y: midY, scale: scale)
            let outside = try pixel(rep, x: inset / 2, y: midY, scale: scale)
            print("Valt alternativ (\(name.rawValue)): kant \(border), platta \(plate), utanför \(outside)")
            XCTAssertGreaterThan(border.blueComponent - max(border.redComponent, border.greenComponent), 0.25,
                                 "Kanten är inte indigo (\(name.rawValue))")
            XCTAssertGreaterThanOrEqual(contrast(border, plate), 3, "Kanten mot plattan under 3:1 (\(name.rawValue))")
            XCTAssertGreaterThanOrEqual(contrast(border, outside), 3, "Kanten mot bakgrunden under 3:1 (\(name.rawValue))")
        }
    }

    func testUnselectedRowHasNoBorderOrPlate() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let (rep, scale) = try render(selected: false, appearance: appearance)
            let midY = inset + 30
            let edge = try pixel(rep, x: inset + 0.5, y: midY, scale: scale)
            let inside = try pixel(rep, x: inset + 20, y: midY, scale: scale)
            let outside = try pixel(rep, x: inset / 2, y: midY, scale: scale)
            XCTAssertLessThan(contrast(edge, outside), 1.05, "Ovald rad har en kant (\(name.rawValue))")
            XCTAssertLessThan(contrast(inside, outside), 1.05, "Ovald rad har en platta (\(name.rawValue))")
        }
    }
}

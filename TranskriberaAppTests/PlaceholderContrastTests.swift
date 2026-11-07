import AppKit
import SwiftUI
import XCTest
@testable import Transkribera

/// Platshållaren i textfälten ska gå att läsa (minst 4,5:1). macOS ritar den annars ljusgrå;
/// Nicklas påpekade det 2026-11-07. Kontrasten mäts i det ritade fältet, inte i koden, eftersom
/// macOS kan strunta i färgen som koden ber om.
@MainActor
final class PlaceholderContrastTests: XCTestCase {
    private func luminance(_ c: NSColor) -> CGFloat {
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Högsta kontrasten mellan någon bildpunkt i fältet och bakgrunden (bildpunkten i hörnet).
    /// Kärnan i bokstäverna har textens färg, så det är platshållarens kontrast.
    private func placeholderContrast(_ field: some View, appearance name: NSAppearance.Name) throws -> CGFloat {
        let host = NSHostingView(rootView: AnyView(
            field.frame(width: 260).padding(12).background(Color.chip)
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.contentView = nil }
        window.contentView = host
        window.appearance = NSAppearance(named: name)
        host.appearance = NSAppearance(named: name)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let background = try XCTUnwrap(rep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB))
        var best: CGFloat = 1
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.9 else { continue }
                best = max(best, contrast(c, background))
            }
        }
        return best
    }

    func testSearchPlaceholderIsReadable() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let field = TextField("Sök på titel", text: .constant(""), prompt: .prompt("Sök på titel"))
                .textFieldStyle(.plain)
                .font(.app(.regular))
            let ratio = try placeholderContrast(field, appearance: name)
            print("Platshållare i sökfältet (\(name.rawValue)): \(String(format: "%.2f", ratio)):1")
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "Platshållaren är för svag (\(name.rawValue))")
        }
    }

    /// Kontrollen ska fånga det ursprungliga felet: systemets platshållare är för svag.
    func testTheMeasurementCatchesTheSystemPlaceholder() throws {
        let field = TextField("Sök på titel", text: .constant(""))
            .textFieldStyle(.plain)
            .font(.app(.regular))
        let ratio = try placeholderContrast(field, appearance: .aqua)
        print("Systemets platshållare (ljust): \(String(format: "%.2f", ratio)):1")
        XCTAssertLessThan(ratio, 4.5, "Mätningen ser inte skillnad på systemets platshållare")
    }
}

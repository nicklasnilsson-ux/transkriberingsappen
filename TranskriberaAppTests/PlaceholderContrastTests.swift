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

    private func render(_ view: some View, appearance name: NSAppearance.Name) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AnyView(view.frame(width: 320).padding(12).background(Color.chip)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.contentView = nil }
        window.appearance = NSAppearance(named: name)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        host.display()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let classes = Set(allSubviews(host).map { String(describing: type(of: $0)) }
            .filter { $0.contains("Text") })
        print("Textvyer: \(classes.sorted())")
        return rep
    }

    private func allSubviews(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    /// Platshållarens kontrast: fältet ritas med och utan platshållare. Bildpunkter som skiljer sig
    /// är platshållarens, och varje jämförs med samma bildpunkt utan platshållare (dess bakgrund).
    /// Kärnan i bokstäverna har textens färg, så den högsta kontrasten är platshållarens.
    private func placeholderContrast<V: View>(appearance name: NSAppearance.Name,
                                     _ field: (String) -> V) throws -> CGFloat {
        let with = try render(field("Sök på titel"), appearance: name)
        let without = try render(field(""), appearance: name)
        XCTAssertEqual(with.pixelsWide, without.pixelsWide)
        var best: CGFloat = 1
        var changed = 0
        for x in 0..<min(with.pixelsWide, without.pixelsWide) {
            for y in 0..<min(with.pixelsHigh, without.pixelsHigh) {
                guard let a = with.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let b = without.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let ratio = contrast(a, b)
                if ratio > 1.05 { changed += 1 }
                best = max(best, ratio)
            }
        }
        XCTAssertGreaterThan(changed, 20, "Ingen platshållare ritades")
        return best
    }

    private let modes: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func check<V: View>(_ what: String, _ field: @escaping (String) -> V) throws {
        for name in modes {
            let ratio = try placeholderContrast(appearance: name, field)
            print("Platshållare, \(what) (\(name.rawValue)): \(String(format: "%.2f", ratio)):1")
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "Platshållaren är för svag: \(what) (\(name.rawValue))")
        }
    }

    /// Sökfälten i sidopanelen och titelbaren (utan ram).
    func testSearchPlaceholderIsReadable() throws {
        try check("sökfält") { prompt in
            TextField("Sök på titel", text: .constant(""), prompt: Text(prompt))
                .readablePrompt(prompt)
                .textFieldStyle(.plain)
        }
    }

    /// Ordlistan i kortet Ny transkribering (fält med ram).
    func testBorderedFieldPlaceholderIsReadable() throws {
        try check("fält med ram") { prompt in
            TextField("Ordlista", text: .constant(""), prompt: Text(prompt))
                .readablePrompt(prompt)
        }
    }

    /// Ordlista och undantag i Inställningar (flerradigt fält i ett grupperat formulär).
    func testMultilineFormFieldPlaceholderIsReadable() throws {
        try check("flerradigt fält i formulär") { prompt in
            Form {
                TextField("Ordlista", text: .constant(""), prompt: Text(prompt), axis: .vertical)
                    .readablePrompt(prompt)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
        }
    }

    /// Kontrollen ska fånga det ursprungliga felet: systemets platshållare är för svag.
    func testTheMeasurementCatchesTheSystemPlaceholder() throws {
        let ratio = try placeholderContrast(appearance: .aqua) { prompt in
            TextField("Sök på titel", text: .constant(""), prompt: Text(prompt))
                .textFieldStyle(.plain)
        }
        print("Systemets platshållare (ljust): \(String(format: "%.2f", ratio)):1")
        XCTAssertLessThan(ratio, 4.5, "Mätningen ser inte skillnad på systemets platshållare")
    }
}

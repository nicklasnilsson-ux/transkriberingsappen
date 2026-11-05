import AppKit
import XCTest
@testable import Transkribera

/// Handen i Inställningar (2026-11-05) gick ut till bildens kant och nuddade fliktexten under.
/// Här ritas varje ikon ur den byggda resurskatalogen, så som macOS faktiskt tolkar SVG:n,
/// och den målade ytan ska ligga inom 1–23 av 24 (scripts/test_icons.py kontrollerar källfilen).
@MainActor
final class IconBoundsTests: XCTestCase {
    private let pixels = 96

    private func paintedBounds(_ icon: AppIcon) throws -> (left: Double, top: Double, right: Double, bottom: Double) {
        let image = try XCTUnwrap(NSImage(named: icon.assetName), "\(icon.assetName) saknas")
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var minX = pixels, minY = pixels, maxX = -1, maxY = -1
        for y in 0..<pixels {
            for x in 0..<pixels where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, 0, "\(icon.rawValue): ingenting målades")
        let unit = Double(pixels) / 24
        return (Double(minX) / unit, Double(minY) / unit, Double(maxX + 1) / unit, Double(maxY + 1) / unit)
    }

    func testEveryIconStaysInsideTheGridMargin() throws {
        for icon in AppIcon.allCases {
            let b = try paintedBounds(icon)
            for (edge, value) in [("vänster", b.left), ("topp", b.top), ("höger", b.right), ("botten", b.bottom)] {
                XCTAssertTrue((0.75...23.25).contains(value),
                              "\(icon.rawValue): \(edge) \(String(format: "%.2f", value)) av 24 ligger utanför 1–23")
            }
        }
    }

    func testHandIsNoTallerThanTheOtherIcons() throws {
        let hand = try paintedBounds(.hand)
        let info = try paintedBounds(.info)
        XCTAssertLessThanOrEqual(hand.bottom - hand.top, info.bottom - info.top + 0.5,
                                 "handen \(hand.top)–\(hand.bottom), info \(info.top)–\(info.bottom)")
    }
}

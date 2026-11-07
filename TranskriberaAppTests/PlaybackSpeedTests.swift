import AVFoundation
import AppKit
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Uppspelningshastigheten (Nicklas 2026-11-07): spelaren startar i sparad hastighet och behåller
/// tonhöjden, och knappen i spelarraden blir indigo när hastigheten inte är 1×.
@MainActor
final class PlaybackSpeedTests: XCTestCase {
    private var url: URL { FileManager.default.temporaryDirectory.appendingPathComponent("finns-inte.m4a") }

    func testPlayerStartsAtTheSavedSpeedAndKeepsThePitch() throws {
        let player = PlayerController(url: url, speed: 1.5)
        defer { player.invalidate() }
        XCTAssertEqual(player.player.defaultRate, 1.5)
        let item = try XCTUnwrap(player.player.currentItem)
        XCTAssertEqual(item.audioTimePitchAlgorithm, .timeDomain)
        XCTAssertNotEqual(item.audioTimePitchAlgorithm, .varispeed, "varispeed ändrar tonhöjden")
        player.setSpeed(2)
        XCTAssertEqual(player.player.defaultRate, 2)
        player.setSpeed(9)
        XCTAssertEqual(player.player.defaultRate, 2, "Ett trasigt värde rundas till närmaste steg")
    }

    func testMenuListsEveryStepWithTheCurrentOneChecked() {
        let menu = MenuAnchor.speedMenu(selected: 1.25, target: SpeedMenuTarget { _ in })
        XCTAssertEqual(menu.items.map(\.title), ["0,75×", "1× (Normal)", "1,25×", "1,5×", "1,75×", "2×"])
        XCTAssertEqual(menu.items.filter { $0.state == .on }.map(\.title), ["1,25×"])
    }

    func testPickingInTheMenuSetsTheSpeed() throws {
        var picked: Double?
        let target = SpeedMenuTarget { picked = $0 }
        let menu = MenuAnchor.speedMenu(selected: 1, target: target)
        let item = try XCTUnwrap(menu.items.last)
        target.pick(item)
        XCTAssertEqual(picked, 2)
    }

    /// Räknar tydligt indigo bildpunkter i den ritade knappen (färgen läses i bilden, inte i koden,
    /// eftersom macOS tidigare ritade playknappen i en annan färg än koden bad om).
    private func indigoPixels(speed: Double, appearance name: NSAppearance.Name) throws -> Int {
        let host = NSHostingView(rootView: AnyView(PlaybackSpeedButton(speed: .constant(speed)).padding(4)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.contentView = nil }
        window.contentView = host
        host.appearance = NSAppearance(named: name)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
                if c.blueComponent - max(c.redComponent, c.greenComponent) > 0.25 { count += 1 }
            }
        }
        return count
    }

    func testButtonIsIndigoOnlyWhenNotNormal() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let normal = try indigoPixels(speed: 1, appearance: name)
            let fast = try indigoPixels(speed: 1.5, appearance: name)
            print("Hastighetsknappen (\(name.rawValue)): indigo bildpunkter vid 1× \(normal), vid 1,5× \(fast)")
            XCTAssertEqual(normal, 0, "Knappen ska vara neutral vid 1× (\(name.rawValue))")
            XCTAssertGreaterThan(fast, 20, "Knappen ska vara indigo vid 1,5× (\(name.rawValue))")
        }
    }

    func testButtonHasTheSameWidthForEverySpeed() {
        let widths = Set(PlaybackSpeed.steps.map { speed -> CGFloat in
            NSHostingView(rootView: PlaybackSpeedButton(speed: .constant(speed))).fittingSize.width
        })
        XCTAssertEqual(widths.count, 1, "Knappen byter bredd med hastigheten: \(widths.sorted())")
    }
}

import AppKit
import SwiftUI
import XCTest
import TranskriberaCore
@testable import Transkribera

/// Spela/Pausa är dubbelt så stor som i 0.9.2–0.9.14 (Nicklas 2026-11-06), och reglaget i spelarraden
/// fungerar fortfarande i ett smalt fönster: det är minst `PlayerBar.sliderMinWidth` brett och ingenting
/// i raden hamnar utanför den.
@MainActor
final class PlayButtonSizeTests: XCTestCase {
    /// Ritar vyn utanför skärmen och returnerar värdvyn (fönstret hålls kvar tills `close`).
    private func host<V: View>(_ view: V, width: CGFloat? = nil) -> (NSHostingView<AnyView>, NSWindow) {
        let root: AnyView = width.map { AnyView(view.frame(width: $0)) } ?? AnyView(view.fixedSize())
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width ?? 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width ?? 400, height: 300)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let fitting = host.fittingSize
        host.frame = NSRect(x: 0, y: 0, width: width ?? fitting.width, height: fitting.height)
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func size<V: View>(of view: V) -> CGSize {
        let (host, window) = host(view)
        defer { window.contentView = nil }
        return host.fittingSize
    }

    /// Plattan så som den såg ut i 0.9.2–0.9.14, för att mäta "dagens storlek".
    private var previousButton: some View {
        Button {} label: {
            Icon(.play, size: 22).padding(4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(Color.accentColor)
    }

    func testPlayButtonIsTwiceTheEarlierSize() {
        let before = size(of: previousButton)
        let now = size(of: PlayPauseButton(isPlaying: false) {})
        print("Spela-knappen: förut \(before), nu \(now)")
        XCTAssertGreaterThan(before.width, 20, "Den gamla knappen gick inte att mäta")
        XCTAssertEqual(now.width, before.width * 2, accuracy: 2, "Spela ska vara dubbelt så bred som förut (\(before.width) pt)")
        XCTAssertEqual(now.height, before.height * 2, accuracy: 2, "Spela ska vara dubbelt så hög som förut (\(before.height) pt)")
        XCTAssertEqual(now.width, PlayPauseButton.diameter, accuracy: 0.5)
        XCTAssertEqual(now.width, now.height, accuracy: 0.5, "Plattan är rund")
    }

    // MARK: - Smalt fönster

    private struct BarResult {
        var sliderWidths: [CGFloat] = []
        var outside: [String] = []
        var barHeight: CGFloat = 0
    }

    private func layout(width: CGFloat, isVideo: Bool) -> BarResult {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("finns-inte.m4a")
        let player = PlayerController(url: url)
        let bar = PlayerBar(
            player: player, duration: 3723, isVideo: isVideo,
            followPlayback: .constant(true), miniSizeRaw: .constant(MiniPlayerSize.small.rawValue)
        )
        let (host, window) = host(bar, width: width)
        defer { window.contentView = nil }
        var result = BarResult(barHeight: host.fittingSize.height)
        func walk(_ view: NSView) {
            let rect = host.convert(view.bounds, from: view)
            if !view.isHidden, rect.width > 1, rect.height > 1,
               rect.minX < -1 || rect.maxX > host.bounds.width + 1 {
                result.outside.append("\(String(describing: type(of: view)).prefix(40)) x \(Int(rect.minX))–\(Int(rect.maxX))")
            }
            if view is NSSlider { result.sliderWidths.append(rect.width) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return result
    }

    /// Bredder detaljvyn kan få: 820 pt fönster minus sidopanelen (360 pt störst, 260 pt normalt).
    func testSliderStillWorksInANarrowWindow() {
        let cases: [(CGFloat, Bool)] = [(460, false), (560, false), (900, false), (600, true), (900, true)]
        for (width, isVideo) in cases {
            let result = layout(width: width, isVideo: isVideo)
            let label = "\(isVideo ? "video" : "ljud") \(Int(width)) pt"
            print("Spelarraden \(label): reglage \(result.sliderWidths), höjd \(result.barHeight), utanför \(result.outside)")
            XCTAssertEqual(result.sliderWidths.count, 1, "Hittade inte reglaget i spelarraden (\(label))")
            if let slider = result.sliderWidths.first {
                XCTAssertGreaterThanOrEqual(slider, PlayerBar.sliderMinWidth - 1, "Reglaget är för smalt (\(label))")
            }
            XCTAssertEqual(result.outside, [], "Delar av spelarraden hamnar utanför (\(label))")
            XCTAssertGreaterThanOrEqual(result.barHeight, PlayPauseButton.diameter, "Raden rymmer knappen (\(label))")
        }
        // Mätvärde att följa, inget krav: video i det smalaste fönstret.
        let tight = layout(width: 460, isVideo: true)
        print("Spelarraden video 460 pt (inget krav): reglage \(tight.sliderWidths), utanför \(tight.outside)")
    }
}

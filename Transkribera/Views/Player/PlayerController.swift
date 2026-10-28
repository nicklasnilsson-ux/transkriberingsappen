import AVFoundation
import Foundation
import Observation

/// Håller en AVPlayer och publicerar aktuell uppspelningstid till SwiftUI.
@MainActor
@Observable
final class PlayerController {
    let player: AVPlayer
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?

    init(url: URL) {
        player = AVPlayer(url: url)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func invalidate() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        rateObservation = nil
    }

    /// Hoppar till en tidpunkt och startar uppspelningen.
    func seek(to seconds: Double, play: Bool = true) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        if play { player.play() }
    }

    func togglePlayPause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds, play: isPlaying)
    }

    var playbackRate: Float {
        get { player.defaultRate }
        set {
            player.defaultRate = newValue
            if player.rate != 0 { player.rate = newValue }
        }
    }
}

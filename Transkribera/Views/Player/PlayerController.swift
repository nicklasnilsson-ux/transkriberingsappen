import AVFoundation
import Foundation
import Observation
import SwiftUI
import TranskriberaCore

/// Håller en AVPlayer och publicerar aktuell uppspelningstid till SwiftUI.
@MainActor
@Observable
final class PlayerController {
    let player: AVPlayer
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?
    /// Stoppar en uppspelad bit (`play(from:to:)`) när den är slut.
    @ObservationIgnored private var clipEnd: Any?

    /// - Parameter speed: uppspelningshastigheten (`PlaybackSpeed`), sparad i inställningarna.
    init(url: URL, speed: Double = PlaybackSpeed.normal) {
        let item = AVPlayerItem(url: url)
        // Tonhöjden behålls alltid när hastigheten ändras (Nicklas 2026-11-07). `.timeDomain` behåller
        // tonhöjden och passar tal; `.varispeed` skulle ge ljusare röster i högre hastighet.
        item.audioTimePitchAlgorithm = Self.pitchAlgorithm
        player = AVPlayer(playerItem: item)
        player.defaultRate = Float(PlaybackSpeed.clamped(speed))
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
        endClip()
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        rateObservation = nil
    }

    /// Hoppar till en tidpunkt och startar uppspelningen.
    func seek(to seconds: Double, play: Bool = true) {
        endClip()
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
        if play { player.play() }
    }

    /// Spelar bara biten `start`–`end` och stannar sedan (Lyssna i korskollens meny).
    func play(from start: Double, to end: Double) {
        seek(to: start)
        let stop = CMTime(seconds: max(start, end), preferredTimescale: 600)
        clipEnd = player.addBoundaryTimeObserver(forTimes: [NSValue(time: stop)], queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.player.pause()
                self?.endClip()
            }
        }
    }

    private func endClip() {
        if let clipEnd { player.removeTimeObserver(clipEnd) }
        clipEnd = nil
    }

    func togglePlayPause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds, play: isPlaying)
    }

    /// Algoritmen för hastighetsändring. Behåller tonhöjden (kontrolleras av `PlaybackSpeedTests`).
    static let pitchAlgorithm: AVAudioTimePitchAlgorithm = .timeDomain

    /// Hastigheten som `play()` använder. Ändras den under uppspelning gäller den direkt.
    var playbackRate: Float {
        get { player.defaultRate }
        set {
            player.defaultRate = newValue
            if player.rate != 0 { player.rate = newValue }
        }
    }

    /// Sätter hastigheten från ett sparat värde (rundas till närmaste giltiga steg).
    func setSpeed(_ speed: Double) {
        playbackRate = Float(PlaybackSpeed.clamped(speed))
    }
}

/// Spelaren i det fönster som är i fokus, för menyn Uppspelning (Spela/Pausa).
struct FocusedPlayerKey: FocusedValueKey {
    typealias Value = PlayerController
}

extension FocusedValues {
    var player: PlayerController? {
        get { self[FocusedPlayerKey.self] }
        set { self[FocusedPlayerKey.self] = newValue }
    }
}

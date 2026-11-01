import AVKit
import SwiftUI

/// AVPlayerView från AVKit, inbäddad i SwiftUI.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let isVideo: Bool
    /// Liten bild utan egna kontroller (hopfällda raden).
    var compact = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = compact ? .none : (isVideo ? .floating : .inline)
        view.showsFullScreenToggleButton = isVideo && !compact
        view.allowsPictureInPicturePlayback = isVideo
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

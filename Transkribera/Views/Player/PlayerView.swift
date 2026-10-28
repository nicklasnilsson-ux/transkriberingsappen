import AVKit
import SwiftUI

/// AVPlayerView från AVKit, inbäddad i SwiftUI.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let isVideo: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = isVideo ? .floating : .inline
        view.showsFullScreenToggleButton = isVideo
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

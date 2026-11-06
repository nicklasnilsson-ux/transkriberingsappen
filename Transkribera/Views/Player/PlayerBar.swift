import SwiftUI
import TranskriberaCore

/// Spelarraden, fast under titelbaren: bild (video) med bildstorlek, spela, tid, reglage, längd och
/// Följ uppspelning. Reglaget är det enda som växer och krymper; allt annat har sin egen bredd, så att
/// ett smalare fönster tar plats från reglaget och inte klipper texterna (se `PlayButtonSizeTests`).
struct PlayerBar: View {
    let player: PlayerController
    let duration: Double
    let isVideo: Bool
    @Binding var followPlayback: Bool
    @Binding var miniSizeRaw: String

    /// Reglaget blir aldrig smalare än så här, även i ett smalt fönster.
    static let sliderMinWidth: CGFloat = 80

    var body: some View {
        // I ett smalt fönster blir "Följ uppspelning" kortare hellre än att reglaget trycks ihop.
        // ViewThatFits mäter raderna med reglagets minsta bredd (idealWidth) och tar den första som ryms.
        ViewThatFits(in: .horizontal) {
            row(followTitle: "Följ uppspelning")
            row(followTitle: "Följ")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func row(followTitle: String) -> some View {
        HStack(spacing: 14) {
            if isVideo { videoWithControls }
            playPauseAndTime
            positionSlider
            Text(TimeFormatting.short(duration))
                .font(.app(.small, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .fixedSize()
            followToggle(followTitle)
        }
    }

    private func followToggle(_ title: String) -> some View {
        Toggle(isOn: $followPlayback) {
            Text(title)
        }
        .toggleStyle(.checkbox)
        .fixedSize()
        .help("Följ uppspelning: håll stycket som spelas upp i bild")
    }

    /// Videobilden i spelarraden. Liten som standard; Bildstorlek väljer mellan tre.
    private var miniPlayer: some View {
        let size = MiniPlayerSize.resolved(miniSizeRaw)
        return PlayerView(player: player.player, isVideo: true, compact: true)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Bilden med bildstorlek och helskärm närmast sig, till vänster om spelknapparna.
    private var videoWithControls: some View {
        HStack(alignment: .center, spacing: 8) {
            miniPlayer
            sizeMenu
        }
    }

    /// Bildstorlek och helskärm i samma lilla meny.
    private var sizeMenu: some View {
        Menu {
            Picker("Bildstorlek", selection: $miniSizeRaw) {
                ForEach(MiniPlayerSize.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Divider()
            Button {
                VideoFullscreen.present(player: player.player)
            } label: {
                Label("Helskärm", icon: .fullscreen)
            }
        } label: {
            Icon(.openInFull, size: 18).accessibilityLabel("Bildstorlek")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Bildstorlek: liten, mellan eller stor, eller helskärm")
    }

    private var playPauseAndTime: some View {
        HStack(spacing: 10) {
            // Stor och tydlig: en rund platta i accentfärgen (Nicklas 2026-11-04, dubblad 2026-11-06).
            PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlayPause() }
            PlaybackTimeReader(player: player) { time in
                Text(TimeFormatting.short(time))
                    .font(.app(.small, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize()
            }
        }
    }

    private var positionSlider: some View {
        PlaybackTimeReader(player: player) { time in
            Slider(
                value: Binding(
                    get: { time },
                    set: { player.seek(to: $0, play: player.isPlaying) }
                ),
                in: 0...max(duration, 1)
            )
            .frame(minWidth: Self.sliderMinWidth, idealWidth: Self.sliderMinWidth, maxWidth: .infinity)
            .help("Hoppa i inspelningen")
        }
    }
}

import SwiftUI
import TranskriberaCore

/// Spelarraden, fast under titelbaren: bild (video) med bildstorlek, spela, tid, reglage, längd,
/// uppspelningshastighet och Följ uppspelning. Reglaget är det enda som växer och krymper; allt annat
/// har sin egen bredd, så att ett smalare fönster tar plats från reglaget och inte klipper texterna (se `PlayButtonSizeTests`).
struct PlayerBar: View {
    let player: PlayerController
    let duration: Double
    let isVideo: Bool
    @Binding var followPlayback: Bool
    @Binding var miniSizeRaw: String
    /// Rubriken på videofönstret (filens namn).
    var title = "Video"

    /// Sparad hastighet, gemensam för alla filer (Nicklas 2026-11-07). Ändras även från menyn
    /// Uppspelning; `DetailLifecycle` för över den till spelaren.
    @AppStorage(SettingsKey.playbackSpeed) private var playbackSpeed = PlaybackSpeed.normal

    /// Reglaget blir aldrig smalare än så här, även i ett smalt fönster.
    static let sliderMinWidth: CGFloat = 80

    var body: some View {
        // I ett smalt fönster blir "Följ uppspelning" kortare hellre än att reglaget trycks ihop.
        // ViewThatFits mäter raderna med reglagets minsta bredd (idealWidth) och tar den första som ryms.
        ViewThatFits(in: .horizontal) {
            row(followTitle: "Följ uppspelning")
            row(followTitle: "Följ")
            // Smalast (video i ca 600 pt): tätare avstånd och hastighetsknappen utan pil.
            row(followTitle: "Följ", spacing: 8, compactSpeed: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func row(followTitle: String, spacing: CGFloat = 14, compactSpeed: Bool = false) -> some View {
        HStack(spacing: spacing) {
            if isVideo { videoWithControls }
            playPauseAndTime
            positionSlider
            Text(TimeFormatting.short(duration))
                .font(.app(.small, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .fixedSize()
            PlaybackSpeedButton(speed: $playbackSpeed, compact: compactSpeed)
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

    private var videoWindow: VideoWindow { .shared }

    /// Sant när videon visas i eget fönster. Då visas den inte här, så att den inte spelas på två ställen.
    private var inOwnWindow: Bool { videoWindow.isShowing(player.player) }

    /// Videobilden i spelarraden. Liten som standard; Bildstorlek väljer mellan tre.
    /// När videon visas i eget fönster står en platshållare i samma storlek här, med Tillbaka hit.
    @ViewBuilder
    private var miniPlayer: some View {
        let size = MiniPlayerSize.resolved(miniSizeRaw)
        Group {
            if inOwnWindow {
                backHerePlaceholder
            } else {
                PlayerView(player: player.player, isVideo: true, compact: true)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Platshållaren medan videon visas i eget fönster. Hela ytan är en knapp som lägger tillbaka videon.
    private var backHerePlaceholder: some View {
        Button {
            videoWindow.close()
        } label: {
            VStack(spacing: 4) {
                Icon(.closeFullscreen, size: 18)
                Text("Tillbaka hit")
                    .font(.app(.small))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.line.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Videon visas i eget fönster. Klicka för att lägga tillbaka den här.")
        .accessibilityLabel("Tillbaka hit: lägg tillbaka videon i spelarraden")
    }

    /// Bilden med bildstorlek och eget fönster närmast sig, till vänster om spelknapparna.
    private var videoWithControls: some View {
        HStack(alignment: .center, spacing: 8) {
            miniPlayer
            sizeMenu
        }
    }

    /// Bildstorlek och eget fönster i samma lilla meny.
    private var sizeMenu: some View {
        Menu {
            Picker("Bildstorlek", selection: $miniSizeRaw) {
                ForEach(MiniPlayerSize.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Divider()
            if inOwnWindow {
                Button {
                    videoWindow.close()
                } label: {
                    Label("Tillbaka till spelarraden", icon: .closeFullscreen)
                }
            } else {
                Button {
                    videoWindow.open(player: player.player, title: title)
                } label: {
                    Label("Visa i eget fönster", icon: .openInNew)
                }
            }
        } label: {
            Icon(.openInFull, size: 18).accessibilityLabel("Bildstorlek")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Bildstorlek: liten, mellan eller stor, eller visa i eget fönster")
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

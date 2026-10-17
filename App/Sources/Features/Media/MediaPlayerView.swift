import SwiftUI
import UIKit

/// Carte du lecteur multimédia Spotify située au bas du panneau gauche du tableau de bord.
struct MediaPlayerView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.palette) private var palette

    @State private var expanded = false
    @State private var scrubbing: Double?

    var body: some View {
        if settings.mediaHidden {
            EmptyView()
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(spacing: 10) {
            GrabHandle()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(Motion.panel) {
                        expanded.toggle()
                    }
                }

            mainRow

            scrubber

            if expanded {
                expandedDetails
            }
        }
        .padding(14)
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        .swipeToDismiss(.down) {
            withAnimation(Motion.panel) {
                if expanded {
                    expanded = false
                } else {
                    settings.mediaHidden = true
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -40 && !expanded {
                        withAnimation(Motion.panel) {
                            expanded = true
                        }
                    }
                }
        )
        .animation(Motion.panel, value: expanded)
    }

    // MARK: - Rangée principale

    private var mainRow: some View {
        HStack(spacing: 12) {
            artworkView

            VStack(alignment: .leading, spacing: 2) {
                Text(spotify.title)
                    .font(TeslaFont.ui(17, .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(spotify.artist)
                    .font(TeslaFont.ui(14))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)

                if !spotify.isConnected {
                    Text(spotify.lastError ?? "Touchez ▶︎ pour connecter Spotify")
                        .font(TeslaFont.ui(12))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            controlsRow
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = spotify.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    palette.panelSecondary
                    Image("app.spotify")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var controlsRow: some View {
        HStack(spacing: 2) {
            Button {
                spotify.toggleLike()
            } label: {
                Image(systemName: spotify.isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundStyle(spotify.isSaved ? Theme.telltaleGreen : palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TeslaPressStyle())
            .disabled(!spotify.isConnected)

            Button {
                spotify.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TeslaPressStyle())

            Button {
                spotify.togglePlay()
            } label: {
                Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TeslaPressStyle())

            Button {
                spotify.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TeslaPressStyle())
        }
    }

    // MARK: - Curseur de progression

    private var scrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let currentFraction = max(0, min(1, scrubbing ?? spotify.progress))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.outline)
                    .frame(height: 4)

                Capsule()
                    .fill(palette.textPrimary)
                    .frame(width: max(0, width * currentFraction), height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard spotify.canSeek, spotify.isConnected, width > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / width))
                        scrubbing = fraction
                    }
                    .onEnded { value in
                        guard spotify.canSeek, spotify.isConnected, width > 0 else {
                            scrubbing = nil
                            return
                        }
                        let fraction = max(0, min(1, value.location.x / width))
                        spotify.seek(to: fraction)
                        scrubbing = nil
                    }
            )
        }
        .frame(height: 22)
        .opacity((!spotify.canSeek || !spotify.isConnected) ? 0.4 : 1.0)
        .disabled(!spotify.canSeek || !spotify.isConnected)
    }

    // MARK: - Vue dépliée

    private var expandedDetails: some View {
        VStack(spacing: 10) {
            let elapsed = formatTime(spotify.currentTime)
            let remaining = formatTime(max(0, spotify.duration - spotify.currentTime))

            HStack {
                Text(elapsed)
                Spacer()
                Text("-\(remaining)")
            }
            .font(TeslaFont.ui(12))
            .foregroundStyle(palette.textSecondary)
            .monospacedDigit()

            HStack(spacing: 16) {
                Button {
                    spotify.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17))
                        .foregroundStyle(spotify.shuffle ? Theme.accent : palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TeslaPressStyle())

                Button {
                    spotify.cycleRepeat()
                } label: {
                    Image(systemName: spotify.repeatMode == .track ? "repeat.1" : "repeat")
                        .font(.system(size: 17))
                        .foregroundStyle(spotify.repeatMode != .off ? Theme.accent : palette.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TeslaPressStyle())

                Spacer()

                Button {
                    withAnimation {
                        settings.libraryOpen = true
                    }
                } label: {
                    Label("Bibliothèque", systemImage: "square.stack")
                        .font(TeslaFont.ui(13, .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.panelSecondary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(TeslaPressStyle())

                SpotifyDeviceMenu()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite && time >= 0 else { return "0:00" }
        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
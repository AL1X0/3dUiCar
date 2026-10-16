import SwiftUI
import MediaPlayer
import Observation

/// Contrôleur gérant la lecture musicale via le lecteur système Apple Music.
@MainActor
@Observable
final class MusicController {
    var title: String = "Aucune lecture"
    var artist: String = "Apple Music"
    var artwork: UIImage? = nil
    var isPlaying: Bool = false
    var progress: Double = 0.0
    var duration: TimeInterval = 0.0
    var currentTime: TimeInterval = 0.0
    var recents: [UIImage] = []

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var hasLoadedRecents = false

    init() {
        setupNotifications()
        updateState()
        startTimer()
    }

    func togglePlay() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        updateState()
    }

    func next() {
        player.skipToNextItem()
        updateState()
    }

    func previous() {
        player.skipToPreviousItem()
        updateState()
    }

    func requestAccess() {
        let status = MPMediaLibrary.authorizationStatus()
        switch status {
        case .authorized:
            loadRecents()
            updateState()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { newStatus in
                Task { @MainActor in
                    if newStatus == .authorized {
                        self.loadRecents()
                        self.updateState()
                    }
                }
            }
        default:
            break
        }
    }

    private func setupNotifications() {
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default

        let itemToken = nc.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateState() }
        }

        let stateToken = nc.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateState() }
        }

        notificationTokens = [itemToken, stateToken]
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
            }
        }
    }

    private func updateProgress() {
        let time = player.currentPlaybackTime
        currentTime = time.isNaN ? 0 : max(0, time)

        let total = duration > 0 ? duration : (player.nowPlayingItem?.playbackDuration ?? 0)
        duration = total.isNaN ? 0 : max(0, total)

        if duration > 0 {
            progress = min(max(currentTime / duration, 0.0), 1.0)
        } else {
            progress = 0.0
        }
    }

    private func updateState() {
        isPlaying = player.playbackState == .playing

        if let item = player.nowPlayingItem {
            title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (item.title ?? "Titre inconnu") : "Titre inconnu"
            artist = item.artist ?? "Artiste inconnu"
            artwork = item.artwork?.image(at: CGSize(width: 300, height: 300))
            duration = item.playbackDuration.isNaN ? 0 : item.playbackDuration
            updateProgress()
        } else {
            title = "Aucune lecture"
            artist = "Apple Music"
            artwork = nil
            duration = 0
            currentTime = 0
            progress = 0
        }
    }

    private func loadRecents() {
        guard !hasLoadedRecents, MPMediaLibrary.authorizationStatus() == .authorized else { return }
        hasLoadedRecents = true

        let query = MPMediaQuery.albums()
        guard let collections = query.collections else { return }

        var loadedArtworks: [UIImage] = []
        for album in collections.prefix(8) {
            if let repItem = album.representativeItem,
               let art = repItem.artwork?.image(at: CGSize(width: 300, height: 300)) {
                loadedArtworks.append(art)
            }
        }
        self.recents = loadedArtworks
    }
}

/// Carte du lecteur multimédia intégrée au volet gauche.
struct MediaPlayerView: View {
    @State private var controller = MusicController()
    @State private var expanded = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            // Poignée de glissement / expansion
            Capsule()
                .fill(palette.inactive)
                .frame(width: 36, height: 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        expanded.toggle()
                    }
                }

            // Ligne principale : pochette, métadonnées, commandes
            HStack(spacing: 12) {
                Group {
                    if let artwork = controller.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(palette.panelSecondary)
                            Image(systemName: "music.note")
                                .font(.system(size: 24))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.title)
                        .font(TeslaFont.ui(18, .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    Text(controller.artist)
                        .font(TeslaFont.ui(14))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)

                    Label("Apple Music", systemImage: "dot.radiowaves.left.and.right")
                        .font(TeslaFont.ui(12))
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button {
                        // Thumbs up
                    } label: {
                        Image(systemName: "hand.thumbsup")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.togglePlay()
                    } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Favori
                    } label: {
                        Image(systemName: "star")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Affichage étendu : temps écoulé / restant
            if expanded {
                HStack {
                    Text(formatTime(controller.currentTime))
                        .font(TeslaFont.ui(12))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("-" + formatTime(max(0, controller.duration - controller.currentTime)))
                        .font(TeslaFont.ui(12))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, -4)
            }

            // Barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.outline)
                        .frame(height: 3)
                    Capsule()
                        .fill(palette.textPrimary)
                        .frame(width: max(0, geo.size.width * controller.progress), height: 3)
                }
            }
            .frame(height: 3)

            // Contenu du tiroir déplié
            if expanded {
                VStack(spacing: 14) {
                    HStack(spacing: 16) {
                        Text("Récents")
                            .font(TeslaFont.ui(14, .bold))
                            .foregroundStyle(palette.textPrimary)

                        Text("Favoris")
                            .font(TeslaFont.ui(14))
                            .foregroundStyle(palette.textSecondary)

                        Text("Sources")
                            .font(TeslaFont.ui(14))
                            .foregroundStyle(palette.textSecondary)

                        Spacer()

                        Button {
                            // Paramètres audio
                        } label: {
                            Image(systemName: "slider.vertical.3")
                                .font(.system(size: 16))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            // Recherche média
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            if controller.recents.isEmpty {
                                ForEach(0..<4, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(palette.panelSecondary)
                                        .frame(width: 110, height: 110)
                                        .overlay {
                                            Image(systemName: "music.note")
                                                .font(.system(size: 28))
                                                .foregroundStyle(palette.inactive)
                                        }
                                }
                            } else {
                                ForEach(Array(controller.recents.enumerated()), id: \.offset) { _, art in
                                    Image(uiImage: art)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { gesture in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if gesture.translation.height < -25 {
                            expanded = true
                        } else if gesture.translation.height > 25 {
                            expanded = false
                        }
                    }
                }
        )
        .task {
            controller.requestAccess()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
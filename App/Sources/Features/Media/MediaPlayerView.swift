import SwiftUI

/// Carte du lecteur Spotify intégrée au volet gauche (composant « Music » du Figma).
struct MediaPlayerView: View {
    @Environment(SpotifyController.self) private var controller
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

                    HStack(spacing: 5) {
                        Image("app.spotify").resizable().frame(width: 14, height: 14)
                        Text(controller.isConnected ? "Spotify" : (controller.lastError ?? "Spotify · non connecté"))
                            .lineLimit(1)
                    }
                    .font(TeslaFont.ui(12))
                    .foregroundStyle(palette.textSecondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { if !controller.isConnected { controller.authorize() } }

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
            controller.connect()
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
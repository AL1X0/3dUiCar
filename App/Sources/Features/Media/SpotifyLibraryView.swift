import SwiftUI
import UIKit

/// Panneau pleine hauteur affichant la bibliothèque et la recherche Spotify,
/// superposé à droite de l'écran lorsque `settings.libraryOpen` est vrai.
struct SpotifyLibraryView: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    @State private var query = ""
    @State private var drag: CGFloat = 0

    /// Glisser la poignée ou l'en-tête vers le bas ferme le panneau (la liste défile normalement).
    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = max(0, $0.translation.height) }
            .onEnded { g in
                if drag > 90 || g.predictedEndTranslation.height > 260 {
                    withAnimation(.spring(duration: 0.3)) { settings.libraryOpen = false }
                }
                withAnimation(.spring(duration: 0.3)) { drag = 0 }
            }
    }

    var body: some View {

        VStack(spacing: 0) {
            GrabHandle()
                .padding(.top, 6)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(closeGesture)

            // MARK: - En-tête
            HStack(spacing: 12) {
                Image("app.spotify")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Theme.telltaleGreen)

                Text("Spotify")
                    .font(TeslaFont.ui(22, .semibold))
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                SpotifyDeviceMenu()

                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        settings.libraryOpen = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer la bibliothèque Spotify")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .gesture(closeGesture)

            // MARK: - Champ de recherche
            SettingsSearchField(text: $query, placeholder: "Titres, artistes, playlists")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // MARK: - Contenu principal
            if !spotify.isConnected {
                notConnectedView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            searchResultsView
                        } else {
                            librarySectionsView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, Theme.dockHeight + 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.panel)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 12,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 12
            )
        )
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: -2)
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(400))
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    await spotify.search(trimmed)
                }
            } catch {
                // Tâche annulée lors d'une nouvelle frappe
            }
        }
        .offset(y: drag)
    }

    // MARK: - Vue Déconnectée

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundStyle(palette.textSecondary)

            Text("Spotify n'est pas connecté")
                .font(TeslaFont.ui(18, .semibold))
                .foregroundStyle(palette.textPrimary)

            if let error = spotify.lastError, !error.isEmpty {
                Text(error)
                    .font(TeslaFont.ui(14))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            AccentButton(title: "Connecter", systemImage: "music.note", width: 220) {
                spotify.authorize()
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Résultats de Recherche

    @ViewBuilder
    private var searchResultsView: some View {
        if spotify.isSearching {
            HStack {
                Spacer()
                ProgressView()
                    .tint(Theme.accent)
                    .padding(.vertical, 32)
                Spacer()
            }
        } else if spotify.searchResults.isEmpty {
            VStack(spacing: 8) {
                Text("Aucun résultat")
                    .font(TeslaFont.ui(16, .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Vérifiez l'orthographe ou lancez une autre recherche.")
                    .font(TeslaFont.ui(14))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 8) {
                ForEach(spotify.searchResults) { item in
                    searchResultRow(item)
                }
            }
        }
    }

    private func searchResultRow(_ item: SpotifyItem) -> some View {
        Button {
            spotify.play(item, in: spotify.searchResults)
        } label: {
            HStack(spacing: 14) {
                itemArtwork(for: item, size: 52, cornerRadius: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(TeslaFont.ui(16, .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(TeslaFont.ui(13))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
            }
            .padding(8)
            .background(palette.panelSecondary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections de la Bibliothèque

    @ViewBuilder
    private var librarySectionsView: some View {
        let nonEmptySections = spotify.sections.filter { !$0.items.isEmpty }

        if nonEmptySections.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                if spotify.isLoadingLibrary {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Text("Aucun contenu disponible")
                        .font(TeslaFont.ui(16, .semibold))
                        .foregroundStyle(palette.textSecondary)

                    AccentButton(title: "Recharger", isOn: true, width: 200) {
                        Task { await spotify.loadLibrary() }
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            ForEach(nonEmptySections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(TeslaFont.ui(18, .semibold))
                        .foregroundStyle(palette.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(section.items) { item in
                                tileView(for: item, in: section.items)
                            }
                        }
                    }
                }
            }
        }
    }

    private func tileView(for item: SpotifyItem, in list: [SpotifyItem]) -> some View {
        Button {
            spotify.play(item, in: list)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                itemArtwork(for: item, size: 150, cornerRadius: 6)

                Text(item.title)
                    .font(TeslaFont.ui(14, .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 150, alignment: .leading)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(TeslaFont.ui(12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                }
            }
            .frame(width: 150)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Vignettes / Artwork

    private func itemArtwork(for item: SpotifyItem, size: CGFloat, cornerRadius: CGFloat) -> some View {
        SpotifyThumb(url: item.imageURL, size: size, cornerRadius: cornerRadius,
                     placeholder: item.isContainer ? "square.stack.fill" : "music.note")
    }
}

/// Vignette chargée de façon indépendante (seule elle se redessine quand l'image arrive).
struct SpotifyThumb: View {
    let url: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let placeholder: String
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.palette) private var palette
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(palette.panelSecondary).overlay {
                    Image(systemName: placeholder)
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(palette.inactive)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            guard let url else { return }
            image = await spotify.image(url: url)
        }
    }
}

import SwiftUI

struct MusicPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var sp = spotify

        SettingsPage {
            SettingsTitle(title: "Spotify")

            HStack(spacing: 8) {
                Circle()
                    .fill(spotify.isConnected ? Theme.telltaleGreen : palette.inactive)
                    .frame(width: 10, height: 10)
                Text(spotify.isConnected ? "Connecté" : "Non connecté")
                    .font(TeslaFont.ui(15, .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                AccentButton(
                    title: spotify.isConnected ? "Bibliothèque" : "Connecter",
                    systemImage: "music.note",
                    width: 200
                ) {
                    if spotify.isConnected {
                        settings.libraryOpen = true
                        settings.settingsOpen = false
                    } else {
                        spotify.authorize()
                    }
                }
            }

            if spotify.isConnected {
                InfoRow(label: "En cours", value: spotify.title)
                InfoRow(label: "Artiste", value: spotify.artist)
            }

            ToggleRow(
                title: "Afficher le lecteur",
                description: "Carte Spotify en bas du panneau voiture",
                isOn: Binding(
                    get: { !settings.mediaHidden },
                    set: { settings.mediaHidden = !$0 }
                )
            )

            SettingsDivider()

            SettingsCaption(text: "Configuration")

            SettingsSearchField(text: $sp.clientID, placeholder: "Client ID Spotify")

            Text("Le Client ID est déjà intégré à l'app. Dans le tableau de bord developer.spotify.com, ajoute la redirect URI car3dui://spotify-login-callback. L'app Spotify doit être installée sur l'iPad ; la connexion se renouvelle via Spotify toutes les heures.")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)

            if let error = spotify.lastError {
                Text(error)
                    .font(TeslaFont.ui(13))
                    .foregroundStyle(Theme.warningRed)
            }
        }
    }
}
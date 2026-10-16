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
                    title: spotify.isConnected ? "Bibliothèque" : "Se connecter",
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
                InfoRow(label: "Appareil", value: spotify.deviceName ?? "Aucun actif")
                InfoRow(label: "En cours", value: spotify.title)
                InfoRow(label: "Artiste", value: spotify.artist)

                AccentButton(
                    title: "Se déconnecter",
                    systemImage: "rectangle.portrait.and.arrow.right",
                    isOn: false,
                    width: 220
                ) {
                    spotify.logout()
                }
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

            Text("Connexion sécurisée Spotify (une seule fois) : le jeton se renouvelle automatiquement. La lecture se fait dans l'app Spotify de l'iPad ou sur n'importe quel appareil Spotify Connect ; Spotify Premium est nécessaire pour piloter la lecture. Redirect URI à déclarer : car3dui://spotify-login-callback.")
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
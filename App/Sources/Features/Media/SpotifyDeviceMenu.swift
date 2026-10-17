import SwiftUI

/// Sélecteur Spotify Connect « Lire sur… » (iPad, iPhone, ordinateur, enceinte…).
struct SpotifyDeviceMenu: View {
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.palette) private var palette

    var body: some View {
        Menu {
            Section("Lire sur") {
                Button {
                    spotify.transfer(to: nil)
                } label: {
                    Label("Automatique (iPad)", systemImage: spotify.preferredDeviceID == nil ? "checkmark" : "wand.and.stars")
                }
                ForEach(spotify.devices) { device in
                    Button {
                        spotify.transfer(to: device)
                    } label: {
                        Label(device.isActive ? "\(device.name) · en cours" : device.name,
                              systemImage: spotify.preferredDeviceID == device.id ? "checkmark" : device.symbol)
                    }
                }
            }
            if spotify.devices.isEmpty {
                Text("Aucun appareil : Spotify sera réveillé automatiquement à la lecture.")
            }
            Button {
                spotify.reloadDevices()
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentSymbol)
                Text(spotify.deviceName ?? "Lire sur…").lineLimit(1)
            }
            .font(TeslaFont.ui(13, .semibold))
            .foregroundStyle(spotify.deviceName == nil ? palette.textSecondary : Theme.telltaleGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.panelSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
        .onAppear { spotify.reloadDevices() }
    }

    private var currentSymbol: String {
        spotify.devices.first { $0.isActive }?.symbol ?? "hifispeaker.2"
    }
}

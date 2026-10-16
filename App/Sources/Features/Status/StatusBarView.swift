import SwiftUI

/// Barre de statut flottante sur la carte : heure, température extérieure réelle,
/// état des liaisons (GPS, OBD, Spotify). Rien de décoratif.
struct StatusBarView: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(LocationFeed.self) private var feed
    @Environment(SpotifyController.self) private var spotify
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            TimelineView(.everyMinute) { timeline in
                Text(timeline.date.formatted(Date.FormatStyle().hour().minute()))
            }
            if let temp = vehicle.outsideTempC {
                Text("\(Int(temp.rounded())) °C")
            }
            if settings.demoMode {
                Text("DÉMO")
                    .font(TeslaFont.ui(11, .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent.opacity(0.18)))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            Image(systemName: "location.fill")
                .foregroundStyle(feed.source == .phone ? Theme.accent
                                 : (feed.source == .device ? palette.textSecondary : palette.inactive))
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(vehicle.obdConnected ? Theme.teal : palette.inactive)
            Image(systemName: "music.note")
                .foregroundStyle(spotify.isConnected ? Theme.telltaleGreen : palette.inactive)
        }
        .font(TeslaFont.ui(14, .medium))
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 4, x: 2, y: 4)
    }
}

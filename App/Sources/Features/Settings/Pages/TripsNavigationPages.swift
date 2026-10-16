import SwiftUI

struct TripsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        SettingsPage {
            SettingsTitle(
                title: "Trajet en cours",
                link: "Réinitialiser",
                linkAction: {
                    vehicle.resetTrip()
                }
            )

            InfoRow(
                label: "Distance",
                value: String(format: "%.1f km", vehicle.tripDistanceKm)
            )

            InfoRow(
                label: "Durée",
                value: formatDuration(vehicle.tripSeconds)
            )

            InfoRow(
                label: "Vitesse moyenne",
                value: "\(Int(vehicle.tripAverageKmh)) km/h"
            )

            InfoRow(
                label: "Vitesse max",
                value: "\(Int(vehicle.tripMaxSpeedKmh)) km/h"
            )

            SettingsDivider()

            SettingsTitle(title: "Compteur")

            InfoRow(
                label: "Kilométrage total",
                value: vehicle.odometerKm.formatted(.number.precision(.fractionLength(0))) + " km"
            )
        }
    }

    private func formatDuration(_ totalSeconds: Double) -> String {
        let total = max(0, Int(totalSeconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

struct NavigationSettingsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            ToggleRow(title: "Guidage vocal", isOn: $s.voiceGuidance)
            ToggleRow(title: "Éviter les péages", isOn: $s.avoidTolls)
            ToggleRow(title: "Éviter les autoroutes", isOn: $s.avoidHighways)

            SettingsDivider()

            SettingsCaption(text: "Source GPS")

            InfoRow(label: "Position", value: vehicle.locationSource.rawValue)

            Text("L'application compagnon pour iPhone transmettra la position GPS si l'iPad ne dispose pas d'une puce GPS intégrée.")
                .font(TeslaFont.ui(14))
                .foregroundStyle(palette.textSecondary)
        }
    }
}
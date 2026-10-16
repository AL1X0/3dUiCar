import SwiftUI

struct LocksPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        SettingsPage {
            AccentButton(
                title: vehicle.locked ? "Déverrouiller" : "Verrouiller",
                systemImage: vehicle.locked ? "lock.open.fill" : "lock.fill",
                isOn: true
            ) {
                vehicle.locked.toggle()
            }

            ToggleRow(
                title: "Verrouillage en s'éloignant",
                description: "Verrouille quand le téléphone s'éloigne",
                isOn: $s.walkAwayLock
            )

            ToggleRow(
                title: "Déverrouiller en position P",
                isOn: $s.unlockOnPark
            )

            ToggleRow(
                title: "Sécurité enfants",
                isOn: $s.childLock
            )

            SettingsDivider()

            SettingsCaption(text: "Ouvrants")

            ToggleRow(
                title: "Porte conducteur ouverte",
                isOn: $v.doorFLOpen
            )

            ToggleRow(
                title: "Porte passager ouverte",
                isOn: $v.doorFROpen
            )

            ToggleRow(
                title: "Capot ouvert",
                isOn: $v.hoodOpen
            )

            ToggleRow(
                title: "Coffre ouvert",
                isOn: $v.trunkOpen
            )
        }
    }
}

struct SafetyPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            ToggleRow(
                title: "Dashcam",
                description: "Enregistre la route avec la caméra arrière de l'iPad",
                isOn: $s.dashcamRecording
            )

            ToggleRow(
                title: "Alerte limitation de vitesse",
                isOn: $s.speedLimitWarning
            )

            SettingsDivider()

            SettingsCaption(text: "Témoins")

            InfoRow(
                label: "Ceinture",
                value: vehicle.seatbeltUnfastened ? "Non bouclée" : "Bouclée"
            )

            InfoRow(
                label: "Airbag passager",
                value: "Désactivé"
            )

            InfoRow(
                label: "Frein de stationnement",
                value: vehicle.gear == .park ? "Serré" : "Desserré"
            )
        }
    }
}
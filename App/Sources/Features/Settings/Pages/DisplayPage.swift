import SwiftUI

struct DisplayPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        SettingsPage {
            SettingsTitle(title: "Apparence")
            TeslaSegmented(
                options: [
                    (.auto, "Auto"),
                    (.light, "Clair"),
                    (.dark, "Sombre")
                ],
                selection: $s.appearance
            )

            SettingsTitle(title: "Luminosité")
            HStack(spacing: 12) {
                BrightnessSlider(value: $s.brightness)
                AccentButton(title: "Auto", isOn: s.brightnessAuto, width: 120) {
                    s.brightnessAuto.toggle()
                }
            }

            ToggleRow(
                title: "Grand texte",
                description: "Agrandit les textes de l'interface",
                isOn: $s.largeText
            )

            SettingsDivider()

            SettingsTitle(title: "Voiture 3D")
            TeslaSegmented(
                options: [
                    (.paint, "Peinture"),
                    (.clay, "Argile")
                ],
                selection: $s.carFinish
            )

            ToggleRow(
                title: "Afficher les voies",
                description: "Lignes bleues sous la voiture en conduite",
                isOn: $s.showLanes
            )

            SettingsDivider()

            SettingsTitle(title: "Unités")
            InfoRow(label: "Vitesse", value: "km/h")
            InfoRow(label: "Température", value: "°C")
            InfoRow(label: "Distance", value: "km")
        }
    }
}
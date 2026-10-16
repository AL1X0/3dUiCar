import SwiftUI

struct ControlsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        let anyOpen = v.hoodOpen || v.trunkOpen || v.doorFLOpen || v.doorFROpen

        SettingsPage {
            SettingsTitle(title: "Voiture 3D")

            TileRow {
                TileButton(
                    title: "Capot",
                    systemImage: "chevron.up.square",
                    isActive: v.hoodOpen
                ) {
                    v.hoodOpen.toggle()
                }

                TileButton(
                    title: "Coffre",
                    systemImage: "car.rear.waves.up",
                    isActive: v.trunkOpen
                ) {
                    v.trunkOpen.toggle()
                }

                TileButton(
                    title: "Porte G",
                    systemImage: "door.left.hand.open",
                    isActive: v.doorFLOpen
                ) {
                    v.doorFLOpen.toggle()
                }

                TileButton(
                    title: "Porte D",
                    systemImage: "door.right.hand.open",
                    isActive: v.doorFROpen
                ) {
                    v.doorFROpen.toggle()
                }
            }

            AccentButton(
                title: "Tout fermer",
                systemImage: "xmark.circle",
                isOn: anyOpen
            ) {
                v.hoodOpen = false
                v.trunkOpen = false
                v.doorFLOpen = false
                v.doorFROpen = false
            }

            SettingsDivider()

            SettingsTitle(title: "Apparence")

            TeslaSegmented(
                options: [
                    (value: Appearance.auto, label: "Auto"),
                    (value: Appearance.light, label: "Clair"),
                    (value: Appearance.dark, label: "Sombre")
                ],
                selection: $s.appearance
            )

            SettingsTitle(title: "Luminosité de l'écran")

            HStack(spacing: 12) {
                BrightnessSlider(value: $s.brightness)
                    .disabled(s.brightnessAuto)
                    .opacity(s.brightnessAuto ? 0.5 : 1)

                AccentButton(
                    title: "Auto",
                    isOn: s.brightnessAuto,
                    width: 120
                ) {
                    s.brightnessAuto.toggle()
                }
            }

            SettingsDivider()

            SettingsTitle(title: "Mode démo")

            ToggleRow(
                title: "Trajet simulé",
                description: "Désactive pour utiliser les capteurs réels de l'iPad, le GPS de l'iPhone et le module OBD",
                isOn: $s.demoMode
            )
        }
    }
}
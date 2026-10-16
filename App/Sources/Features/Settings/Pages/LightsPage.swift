import SwiftUI

struct LightsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        SettingsPage {
            SettingsTitle(
                title: "Phares",
                info: true,
                link: "Affichage",
                linkAction: {
                    s.selectedSection = .display
                }
            )

            TeslaSegmented(
                options: [
                    (.off, "Off"),
                    (.parking, "Feux de position"),
                    (.on, "On"),
                    (.auto, "Auto")
                ],
                selection: $s.headlightMode
            )

            AccentButton(
                title: "Antibrouillard AV",
                systemImage: "headlight.fog.fill",
                isOn: v.fogLights,
                width: 230
            ) {
                v.fogLights.toggle()
            }

            SettingsTitle(title: "Clignotants automatiques", info: true)

            TeslaSegmented(
                options: [
                    (.off, "Off"),
                    (.autoCancel, "Arrêt auto")
                ],
                selection: $s.turnSignals
            )
            .frame(width: 230)

            ToggleRow(
                title: "Feux de route automatiques",
                info: true,
                isOn: $s.autoHighBeam
            )

            ToggleRow(
                title: "Phares après sortie",
                isOn: $s.headlightsAfterExit
            )

            SettingsDivider()

            SettingsTitle(title: "Plafonnier")

            TeslaSegmented(
                options: [
                    (.off, "Off"),
                    (.on, "On"),
                    (.auto, "Auto")
                ],
                selection: $s.domeLights
            )
            .frame(width: 345)

            SettingsDivider()

            SettingsCaption(text: "État des feux")

            InfoRow(
                label: "Feux de croisement",
                value: v.lowBeam ? "Allumés" : "Éteints"
            )

            InfoRow(
                label: "Feux de route",
                value: v.highBeam ? "Allumés" : "Éteints"
            )

            InfoRow(
                label: "Antibrouillards",
                value: v.fogLights ? "Allumés" : "Éteints"
            )

            InfoRow(
                label: "Feux stop",
                value: v.braking ? "Allumés" : "Éteints"
            )

            InfoRow(
                label: "Clignotants",
                value: v.blinkerLeft && v.blinkerRight
                    ? "Détresse"
                    : v.blinkerLeft
                        ? "Gauche"
                        : v.blinkerRight
                            ? "Droite"
                            : "Aucun"
            )
        }
    }
}
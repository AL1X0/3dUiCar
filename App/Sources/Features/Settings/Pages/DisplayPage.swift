import SwiftUI

struct DisplayPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            SettingsTitle(title: "Apparence")
            TeslaSegmented(
                options: [
                    (value: Appearance.auto, label: "Auto"),
                    (value: Appearance.light, label: "Clair"),
                    (value: Appearance.dark, label: "Sombre")
                ],
                selection: $s.appearance
            )

            SettingsTitle(title: "Luminosité")
            HStack(spacing: 12) {
                BrightnessSlider(value: $s.brightness)
                    .disabled(s.brightnessAuto)
                    .opacity(s.brightnessAuto ? 0.4 : 1.0)

                AccentButton(
                    title: "Auto",
                    isOn: s.brightnessAuto,
                    width: 120
                ) {
                    s.brightnessAuto.toggle()
                }
            }

            ToggleRow(
                title: "Grand texte",
                description: "Agrandit tous les textes",
                isOn: $s.largeText
            )

            SettingsDivider()

            SettingsTitle(title: "Voiture 3D")
            TeslaSegmented(
                options: [
                    (value: CarFinish.paint, label: "Peinture blanche"),
                    (value: CarFinish.clay, label: "Argile")
                ],
                selection: $s.carFinish
            )

            ToggleRow(
                title: "Afficher les voies",
                description: "Lignes bleues sous la voiture en conduite",
                isOn: $s.showLanes
            )

            SettingsDivider()

            SettingsTitle(title: "Disposition")
            Text("Glisse le séparateur entre la voiture et la carte pour redimensionner. Double-tap dessus pour revenir à la taille par défaut.")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: 12) {
                AccentButton(
                    title: "Compacte",
                    isOn: abs(s.carPanelRatio - 0.25) < 0.02
                ) {
                    withAnimation(.spring) {
                        s.carPanelRatio = 0.25
                    }
                }

                AccentButton(
                    title: "Standard",
                    isOn: abs(s.carPanelRatio - 0.33) < 0.02
                ) {
                    withAnimation(.spring) {
                        s.carPanelRatio = 0.33
                    }
                }

                AccentButton(
                    title: "Large",
                    isOn: abs(s.carPanelRatio - 0.5) < 0.02
                ) {
                    withAnimation(.spring) {
                        s.carPanelRatio = 0.5
                    }
                }
            }
        }
    }
}
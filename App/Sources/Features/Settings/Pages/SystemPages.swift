import SwiftUI

struct ServicePage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        SettingsPage {
            SettingsTitle(title: "Module OBD ESP32")

            HStack(spacing: 8) {
                Circle()
                    .fill(vehicle.obdConnected ? Theme.teal : palette.inactive)
                    .frame(width: 10, height: 10)
                Text(vehicle.obdConnected ? "Connecté" : "Non connecté")
                    .font(TeslaFont.ui(15))
                    .foregroundStyle(palette.textPrimary)
            }

            Text("Le module ESP32 se branche sur le port OBD-II et transmet le régime moteur, les températures et l'état des clignotants.")
                .font(TeslaFont.ui(14))
                .foregroundStyle(palette.textSecondary)

            SettingsDivider()

            SettingsCaption(text: "Codes défaut")

            Text("Aucun code lu")
                .font(TeslaFont.ui(15))
                .foregroundStyle(palette.textSecondary)

            SettingsDivider()

            SettingsCaption(text: "Pneus")

            InfoRow(label: "Dimension", value: "205/40 R18")
            InfoRow(label: "Pression recommandée", value: "2,3 bar")
        }
    }
}

struct SoftwarePage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        SettingsPage {
            VStack(alignment: .leading, spacing: 4) {
                Text("v\(version) (\(build))")
                    .font(TeslaFont.ui(36, .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Installé via SideStore")
                    .font(TeslaFont.ui(14))
                    .foregroundStyle(palette.textSecondary)
            }

            ToggleRow(
                title: "Mode démo",
                description: "Trajet simulé pour tester la voiture 3D sans capteurs",
                isOn: $s.demoMode
            )

            SettingsDivider()

            SettingsCaption(text: "Mises à jour")

            InfoRow(label: "Source", value: "github.com/AL1X0/3dUiCar")

            SettingsDivider()

            SettingsCaption(text: "Crédits")

            Text("Modèle 3D « 2019 Ford Fiesta ST » par Ddiaz Design — CC BY-NC-SA 4.0. Interface inspirée de la librairie Figma « Tesla Dashboard UI Component Library ». Police Inter (OFL).")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)
        }
    }
}

struct UpgradesPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        SettingsPage {
            SettingsCaption(text: "À venir")

            VStack(spacing: 0) {
                InfoRow(label: "Navigation guidée", value: "Phase 3")
                InfoRow(label: "App iPhone (GPS)", value: "Phase 3")
                InfoRow(label: "Module OBD ESP32", value: "Phase 4")
                InfoRow(label: "Clignotants via CAN Ford", value: "Phase 5")
                InfoRow(label: "Dashcam", value: "Phase 6")
            }
        }
    }
}
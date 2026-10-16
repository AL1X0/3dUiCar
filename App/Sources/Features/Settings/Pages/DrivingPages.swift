import SwiftUI

struct PedalsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            SettingsTitle(title: "Mode de conduite", info: true)

            TeslaSegmented(
                options: [
                    (.normal, "Normal"),
                    (.sport, "Sport"),
                    (.track, "Piste")
                ],
                selection: $s.driveMode
            )

            Text(driveModeDescription(for: settings.driveMode))
                .font(TeslaFont.ui(14))
                .foregroundStyle(palette.textSecondary)

            SettingsTitle(title: "Direction")

            TeslaSegmented(
                options: [
                    (.comfort, "Confort"),
                    (.standard, "Standard"),
                    (.sport, "Sport")
                ],
                selection: $s.steeringMode
            )

            SettingsDivider()

            SettingsCaption(text: "Moteur")

            InfoRow(
                label: "Régime",
                value: vehicle.rpm.map { "\(Int($0)) tr/min" } ?? "—"
            )

            InfoRow(
                label: "Température eau",
                value: vehicle.coolantTempC.map { "\(Int($0)) °C" } ?? "— °C"
            )

            InfoRow(
                label: "Rapport",
                value: vehicle.gear.rawValue
            )
        }
    }

    private func driveModeDescription(for mode: DriveMode) -> String {
        switch mode {
        case .normal:
            return "Réponse moteur et direction standard."
        case .sport:
            return "Accélérateur plus réactif, échappement actif, direction plus ferme."
        case .track:
            return "ESP permissif, réglages pour circuit uniquement."
        }
    }
}

struct FuelPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            SettingsTitle(title: "Niveau de carburant")

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(Int(round(vehicle.fuelLevel * 100))) %")
                    .font(TeslaFont.ui(45, .semibold))
                    .foregroundStyle(palette.textPrimary)

                Text("≈ \(Int(vehicle.fuelLevel * 42 * 100 / 6.5)) km")
                    .font(TeslaFont.ui(22))
                    .foregroundStyle(palette.textSecondary)

                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.panelSecondary)

                    Capsule()
                        .fill(vehicle.fuelLevel < 0.15 ? Theme.warningRed : Theme.accent)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * vehicle.fuelLevel)))
                }
            }
            .frame(height: 14)

            SettingsDivider()

            SettingsCaption(text: "Spécifications")

            InfoRow(label: "Réservoir", value: "42 L")
            InfoRow(label: "Consommation moyenne", value: "6,5 L/100 km")
            InfoRow(label: "Carburant", value: "SP98")

            SettingsDivider()

            SettingsCaption(text: "Données OBD")

            Text("Les données réelles de niveau de carburant et de consommation sont transmises dès la connexion du module OBD ESP32.")
                .font(TeslaFont.ui(14))
                .foregroundStyle(palette.textSecondary)
        }
    }
}

struct AssistPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            CalibrationSection()

            SettingsDivider()

            SettingsTitle(title: "Aides à la conduite")

            ToggleRow(
                title: "Visualisation des voies",
                isOn: $s.showLanes
            )

            ToggleRow(
                title: "Alerte limitation de vitesse",
                description: "Signale un dépassement de la limitation affichée",
                isOn: $s.speedLimitWarning
            )

            SettingsDivider()

            SettingsCaption(text: "Capteurs")

            InfoRow(
                label: "Position",
                value: vehicle.locationSource.rawValue
            )

            InfoRow(
                label: "Vitesse",
                value: vehicle.speedSource.rawValue
            )

            InfoRow(
                label: "Module OBD",
                value: vehicle.obdConnected ? "Connecté" : "Non connecté"
            )
        }
    }
}
/// Calibration du support iPad (repère voiture pour le gyroscope / l'accéléromètre).
struct CalibrationSection: View {
    @Environment(SensorHub.self) private var sensors
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    private var status: (String, Color) {
        switch sensors.calibration {
        case .none: ("Non calibré", Theme.warningRed)
        case .level: ("Niveau enregistré · avant en apprentissage", .orange)
        case .complete: ("Calibré", Theme.telltaleGreen)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsTitle(title: "Capteurs de l'iPad", info: true)
            HStack(spacing: 10) {
                Circle().fill(status.1).frame(width: 10, height: 10)
                Text(status.0).font(TeslaFont.ui(15, .semibold)).foregroundStyle(palette.textPrimary)
            }
            Text(settings.demoMode
                 ? "Coupe le mode démo (Réglages › Logiciel) pour utiliser les vrais capteurs."
                 : "1. Voiture à l'arrêt sur le plat, iPad fixé : touche « Calibrer ».\n2. Démarre et accélère franchement en ligne droite : l'axe avant est appris tout seul.")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 12) {
                AccentButton(title: "Calibrer", systemImage: "level", isOn: !settings.demoMode) {
                    sensors.calibrateLevel()
                }
                AccentButton(title: "Réinitialiser", systemImage: "arrow.counterclockwise", isOn: false) {
                    sensors.resetCalibration()
                }
            }
            InfoRow(label: "Accélération longitudinale", value: String(format: "%+.2f g", vehicle.longitudinalG))
            InfoRow(label: "Accélération latérale", value: String(format: "%+.2f g", vehicle.lateralG))
            InfoRow(label: "Lacet", value: String(format: "%+.0f °/s", vehicle.yawRateDegS))
            InfoRow(label: "Pente", value: String(format: "%+.1f °", vehicle.roadPitchDeg))
            InfoRow(label: "GPS", value: sensors.hasGPS ? "Fix GNSS" : "Indisponible (iPhone compagnon en phase 3)")
        }
    }
}

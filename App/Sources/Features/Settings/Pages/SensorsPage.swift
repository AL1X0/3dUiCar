import CoreLocation
import SwiftUI

struct SensorsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LocationFeed.self) private var feed
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            CalibrationSection()

            SettingsDivider()

            SettingsCaption(text: "Position")

            InfoRow(
                label: "Source",
                value: feed.source == .phone ? "iPhone (GPS)" : feed.source == .device ? "iPad" : "Aucune"
            )

            InfoRow(
                label: "iPhone compagnon",
                value: feed.phoneConnected ? "Connecté" : "Non connecté"
            )

            InfoRow(
                label: "Précision",
                value: feed.location.map { "±\(Int($0.horizontalAccuracy)) m" } ?? "—"
            )

            Text("Installez l'application « 3dUiCar GPS » sur l'iPhone (même source SideStore), activez le partage de connexion de l'iPhone et connectez-y l'iPad.")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)

            SettingsDivider()

            ToggleRow(
                title: "Afficher les voies",
                isOn: $s.showLanes
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
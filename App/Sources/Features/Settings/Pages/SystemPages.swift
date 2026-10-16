import SwiftUI

struct ServicePage: View {
    @Environment(ESP32Source.self) private var esp32
    @Environment(LocationFeed.self) private var feed
    @Environment(\.palette) private var palette

    @State private var bus = 0

    private var statusColor: Color {
        switch esp32.state {
        case .connected: Theme.teal
        case .scanning, .connecting: .orange
        default: palette.inactive
        }
    }

    private var statusText: String {
        switch esp32.state {
        case .connected: "Connecté"
        case .scanning: "Recherche…"
        case .connecting: "Connexion…"
        case .unavailable: "Bluetooth indisponible"
        case .off: "Arrêté"
        }
    }

    var body: some View {
        SettingsPage {
            SettingsTitle(title: "Module OBD ESP32")

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(TeslaFont.ui(15))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(esp32.firmwareInfo)
                    .font(TeslaFont.ui(12))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            SettingsDivider()

            SettingsCaption(text: "Codes défaut")

            HStack(spacing: 12) {
                AccentButton(title: "Lire les codes", systemImage: "stethoscope", isOn: esp32.state == .connected) {
                    esp32.readDTC()
                }
                AccentButton(title: "Effacer", systemImage: "trash", isOn: false) {
                    esp32.clearDTC()
                }
            }

            if let codes = esp32.dtcCodes {
                if codes.isEmpty {
                    Text("Aucun code défaut")
                        .font(TeslaFont.ui(15))
                        .foregroundStyle(Theme.telltaleGreen)
                } else {
                    ForEach(codes, id: \.self) { code in
                        InfoRow(label: code, value: "Défaut")
                    }
                }
            }

            SettingsDivider()

            SettingsCaption(text: "Enregistrement du bus CAN")

            Text("Enregistre les trames CAN brutes dans un fichier CSV pour analyser et décoder les trames Ford (clignotants, ouvrants…).")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)

            TeslaSegmented(
                options: [(value: 0, label: "HS-CAN 500k"), (value: 1, label: "MS-CAN 125k")],
                selection: $bus
            )

            ToggleRow(
                title: "Enregistrer",
                description: esp32.recording ? "\(esp32.recordedFrames) trames" : nil,
                isOn: Binding(
                    get: { esp32.recording },
                    set: { esp32.setRecording($0, bus: UInt8(bus)) }
                )
            )

            if let url = esp32.lastRecordingURL, !esp32.recording {
                ShareLink(item: url) {
                    Label("Partager le dernier enregistrement", systemImage: "square.and.arrow.up")
                        .font(TeslaFont.ui(15))
                        .foregroundStyle(Theme.accent)
                }
            }

            SettingsDivider()

            SettingsCaption(text: "iPhone compagnon")

            InfoRow(label: "GPS iPhone", value: feed.phoneConnected ? "Connecté" : "Non connecté")
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
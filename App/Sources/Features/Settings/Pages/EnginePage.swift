import SwiftUI

struct EnginePage: View {
    @Environment(ESP32Source.self) private var esp32
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            if !vehicle.obdConnected && !s.demoMode {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.warningRed)

                    Text("Branche le module OBD ESP32 pour voir les données moteur")
                        .font(TeslaFont.ui(14))
                        .foregroundStyle(palette.textPrimary)

                    Spacer()

                    Button("Voir le module") {
                        s.selectedSection = .service
                    }
                    .font(TeslaFont.ui(13, .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(palette.panelSecondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            LazyVGrid(columns: columns, spacing: 12) {
                gaugeCard(
                    title: "Régime",
                    value: vehicle.rpm.map { "\(Int($0))" } ?? "—",
                    unit: "tr/min"
                )

                gaugeCard(
                    title: "Vitesse",
                    value: "\(vehicle.displaySpeed)",
                    unit: "km/h"
                )

                gaugeCard(
                    title: "Rapport",
                    value: esp32.manualGear.map(String.init) ?? vehicle.gear.rawValue,
                    unit: nil
                )

                gaugeCard(
                    title: "Température eau",
                    value: vehicle.coolantTempC.map { "\(Int($0))" } ?? "—",
                    unit: "°C"
                )

                let fuelPercent = vehicle.fuelLevel.map { Int($0 * 100) }
                gaugeCard(
                    title: "Carburant",
                    value: fuelPercent.map { "\($0)" } ?? "—",
                    unit: "%",
                    isWarning: vehicle.fuelLevel.map { $0 < 0.15 } ?? false
                )

                let rangeKm = vehicle.fuelLevel.map { Int($0 * 42.0 / 6.5 * 100) }
                gaugeCard(
                    title: "Autonomie estimée",
                    value: rangeKm.map { "\($0)" } ?? "—",
                    unit: "km"
                )
            }

            SettingsDivider()

            SettingsCaption(text: "Feux et ouvrants (CAN)")

            VStack(spacing: 0) {
                InfoRow(label: "Feux de croisement", value: vehicle.lowBeam ? "Allumés" : "Éteints")
                InfoRow(label: "Feux de route", value: vehicle.highBeam ? "Allumés" : "Éteints")
                InfoRow(label: "Antibrouillards", value: vehicle.fogLights ? "Allumés" : "Éteints")
                InfoRow(label: "Feux stop", value: vehicle.braking ? "Allumés" : "Éteints")
                InfoRow(label: "Clignotants", value: blinkersDescription)
                InfoRow(label: "Ceinture", value: vehicle.seatbeltUnfastened ? "Non bouclée" : "Bouclée")
            }

            Text("Les feux et ouvrants proviennent du bus CAN Ford une fois les trames décodées.")
                .font(TeslaFont.ui(12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var blinkersDescription: String {
        if vehicle.blinkerLeft && vehicle.blinkerRight {
            return "Les deux"
        } else if vehicle.blinkerLeft {
            return "Gauche"
        } else if vehicle.blinkerRight {
            return "Droite"
        } else {
            return "Aucun"
        }
    }

    @ViewBuilder
    private func gaugeCard(title: String, value: String, unit: String?, isWarning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(TeslaFont.ui(34, .semibold))
                    .foregroundStyle(isWarning ? Theme.warningRed : palette.textPrimary)
                    .monospacedDigit()

                if let unit {
                    Text(unit)
                        .font(TeslaFont.ui(13))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.panelSecondary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
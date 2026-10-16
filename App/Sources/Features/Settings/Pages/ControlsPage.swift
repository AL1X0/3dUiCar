import SwiftUI

/// Vue représentant la page « Commandes » de l'interface Tesla.
struct ControlsPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var s = settings
        @Bindable var v = vehicle

        SettingsPage {
            // Section Phares
            SettingsTitle(title: "Phares")
            HStack(spacing: 12) {
                TeslaSegmented(
                    options: [
                        (.off, "Off"),
                        (.parking, "Feux de position"),
                        (.on, "On"),
                        (.auto, "Auto")
                    ],
                    selection: $s.headlightMode,
                    icon: "sun.max"
                )

                AccentButton(
                    title: "",
                    systemImage: "headlight.high.beam.fill",
                    isOn: vehicle.highBeam,
                    width: 82
                ) {
                    v.highBeam.toggle()
                }
            }

            // Rangée d'accès rapide (Rétros, Sécurité enfants, Capot, Coffre)
            TileRow {
                TileButton(
                    title: "Rabattre rétros",
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    isActive: settings.mirrorsFolded
                ) {
                    s.mirrorsFolded.toggle()
                }

                TileButton(
                    title: "Sécurité enfants",
                    systemImage: "figure.and.child.holdinghands",
                    isActive: settings.childLock
                ) {
                    s.childLock.toggle()
                }

                TileButton(
                    title: "Capot",
                    asset: "app.car",
                    isActive: vehicle.hoodOpen
                ) {
                    v.hoodOpen.toggle()
                }

                TileButton(
                    title: "Coffre",
                    systemImage: "car.rear.waves.up",
                    isActive: vehicle.trunkOpen
                ) {
                    v.trunkOpen.toggle()
                }
            }

            // Section Essuie-glaces
            SettingsTitle(title: "Essuie-glaces")
            TeslaSegmented(
                options: [
                    (0, "Off"),
                    (1, "I"),
                    (2, "II"),
                    (3, "III"),
                    (4, "IIII"),
                    (5, "Auto")
                ],
                selection: $s.wiperSpeed,
                icon: "windshield.front.and.wiper"
            )

            // Colonnes de réglages secondaires
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 1) {
                    ControlRow(
                        title: "Rétroviseurs",
                        systemImage: "car.side.and.exclamationmark"
                    ) {}
                    ControlRow(
                        title: "Volant",
                        systemImage: "steeringwheel"
                    ) {}
                }
                .background(palette.outline)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.outline, lineWidth: 1))
                .frame(maxWidth: .infinity)

                VStack(spacing: 1) {
                    ControlRow(
                        title: "Dashcam",
                        systemImage: "video.fill",
                        showsRecordingDot: settings.dashcamRecording
                    ) {
                        s.dashcamRecording.toggle()
                    }
                    ControlRow(
                        title: "Verrouiller",
                        systemImage: vehicle.locked ? "lock.fill" : "lock.open.fill"
                    ) {
                        v.locked.toggle()
                    }
                }
                .background(palette.outline)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.outline, lineWidth: 1))
                .frame(maxWidth: .infinity)
            }

            // Section Luminosité
            SettingsTitle(title: "Luminosité")
            HStack(spacing: 12) {
                BrightnessSlider(value: $s.brightness)
                    .opacity(settings.brightnessAuto ? 0.5 : 1.0)
                    .allowsHitTesting(!settings.brightnessAuto)

                AccentButton(
                    title: "Auto",
                    isOn: settings.brightnessAuto,
                    width: 120
                ) {
                    s.brightnessAuto.toggle()
                }
            }
        }
    }
}

/// Ligne d'action compacte pour les panneaux de commandes secondaires.
private struct ControlRow: View {
    let title: String
    let systemImage: String
    var showsRecordingDot: Bool = false
    var action: () -> Void = {}
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)

                Text(title)
                    .font(TeslaFont.ui(15))

                Spacer()

                if showsRecordingDot {
                    Circle()
                        .fill(Theme.warningRed)
                        .frame(width: 10, height: 10)
                }
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 54)
            .background(palette.panelSecondary.opacity(0.35))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
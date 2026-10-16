import SwiftUI

/// Applications accessibles depuis la barre inférieure (Dock).
enum DockApp: String, CaseIterable, Sendable {
    case phone
    case audio
    case bluetooth
    case music
    case camera
    case theater
    case toybox

    var systemImage: String {
        switch self {
        case .phone: "phone.fill"
        case .audio: "waveform"
        case .bluetooth: "bolt.horizontal"
        case .music: "music.note"
        case .camera: "camera.fill"
        case .theater: "play.rectangle.fill"
        case .toybox: "gamecontroller.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .phone: .green
        case .audio: .orange
        case .bluetooth: .blue
        case .music: .green
        case .camera: .purple
        case .theater: .gray
        case .toybox: Theme.teal
        }
    }
}

/// Barre inférieure fixe (Dock) du Tesla Model 3.
struct DockView: View {
    @Environment(\.palette) var palette
    @Environment(VehicleState.self) var vehicle

    var onCarTap: () -> Void
    var onApp: (DockApp) -> Void

    @State private var volume: Double = 0.5

    init(
        onCarTap: @escaping () -> Void = {},
        onApp: @escaping (DockApp) -> Void = { _ in }
    ) {
        self.onCarTap = onCarTap
        self.onApp = onApp
    }

    var body: some View {
        @Bindable var v = vehicle

        HStack(spacing: 0) {
            // (1) Bouton voiture
            Button(action: onCarTap) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(palette.dockText)
            }
            .buttonStyle(.plain)
            .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
            .contentShape(Rectangle())

            // (2) Contrôle température conducteur
            HStack(spacing: 0) {
                Button {
                    v.driverTempC = max(15.0, min(28.0, (round((v.driverTempC - 0.5) * 2) / 2)))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                .contentShape(Rectangle())

                Text(v.driverTempC, format: .number.precision(.fractionLength(0)))
                    .font(TeslaFont.ui(26, .regular))
                    .foregroundStyle(palette.dockText)

                Button {
                    v.driverTempC = max(15.0, min(28.0, (round((v.driverTempC + 0.5) * 2) / 2)))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                .contentShape(Rectangle())
            }

            // (3) Espaceur gauche
            Spacer()

            // (4) Rangée d'icônes d'applications
            HStack(spacing: 8) {
                ForEach(DockApp.allCases, id: \.self) { app in
                    Button {
                        onApp(app)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(app.tintColor)
                                .frame(width: 40, height: 40)

                            Image(systemName: app.systemImage)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                    .contentShape(Rectangle())
                }
            }

            // (5) Espaceur droit
            Spacer()

            // (6) Contrôle température passager
            HStack(spacing: 0) {
                Button {
                    v.passengerTempC = max(15.0, min(28.0, (round((v.passengerTempC - 0.5) * 2) / 2)))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                .contentShape(Rectangle())

                Text(v.passengerTempC, format: .number.precision(.fractionLength(0)))
                    .font(TeslaFont.ui(26, .regular))
                    .foregroundStyle(palette.dockText)

                Button {
                    v.passengerTempC = max(15.0, min(28.0, (round((v.passengerTempC + 0.5) * 2) / 2)))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                .contentShape(Rectangle())
            }

            // (7) Contrôle du volume
            HStack(spacing: 0) {
                Button {
                    volume = max(0.0, min(1.0, (round((volume - 0.1) * 10) / 10)))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                .contentShape(Rectangle())

                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.dockText)
                    .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)

                Button {
                    volume = max(0.0, min(1.0, (round((volume + 0.1) * 10) / 10)))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.dockHeight)
        .background(palette.dock)
    }
}
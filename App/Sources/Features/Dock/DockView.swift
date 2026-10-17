import SwiftUI

/// Raccourcis du dock (tous fonctionnels).
enum DockApp: String, CaseIterable, Sendable {
    case navigation, spotify, trips, engine

    var title: String {
        switch self {
        case .navigation: "Naviguer"
        case .spotify: "Spotify"
        case .trips: "Trajets"
        case .engine: "Moteur"
        }
    }
}

/// Barre basse noire : réglages (icône voiture), température extérieure, raccourcis, volume système.
struct DockView: View {
    @Environment(\.palette) private var palette
    @Environment(VehicleState.self) private var vehicle
    @Environment(SystemVolume.self) private var volume
    @Environment(SpotifyController.self) private var spotify

    var onCarTap: () -> Void
    var onApp: (DockApp) -> Void

    var body: some View {
        HStack(spacing: 0) {
            dockButton(action: onCarTap) {
                Image("nav.car").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 38, height: 38)
                    .foregroundStyle(palette.dockText)
            }

            if let t = vehicle.outsideTempC {
                Text("\(Int(t.rounded()))°")
                    .font(TeslaFont.ui(24, .regular))
                    .foregroundStyle(palette.dockText)
                    .padding(.leading, 12)
            }

            Spacer()

            HStack(spacing: 18) {
                appButton(.navigation) { Image("dock.navigation").resizable().scaledToFit() }
                appButton(.spotify) {
                    Image("app.spotify").resizable().scaledToFit()
                        .overlay(alignment: .topTrailing) {
                            if spotify.isPlaying {
                                Circle().fill(Theme.telltaleGreen).frame(width: 10, height: 10).offset(x: 3, y: -3)
                            }
                        }
                }
                appButton(.trips) { Image("dock.trips").resizable().scaledToFit() }
                appButton(.engine) { Image("dock.engine").resizable().scaledToFit() }
            }

            Spacer()

            HStack(spacing: 0) {
                dockButton(action: { volume.step(-0.0625) }) { chevron("chevron.left") }
                Image(systemName: volume.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.dockText)
                    .frame(width: 34)
                    .contentTransition(.symbolEffect(.replace))
                dockButton(action: { volume.step(0.0625) }) { chevron("chevron.right") }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.dockHeight)
        .background(palette.dock)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(palette.textSecondary)
    }

    private func dockButton<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) { label() }
            .buttonStyle(TeslaPressStyle())
            .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
            .contentShape(Rectangle())
    }

    private func appButton<Icon: View>(_ app: DockApp, @ViewBuilder icon: () -> Icon) -> some View {
        Button { onApp(app) } label: {
            icon().frame(width: 50, height: 50)
        }
        .buttonStyle(TeslaPressStyle())
        .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
        .contentShape(Rectangle())
        .accessibilityLabel(app.title)
    }
}

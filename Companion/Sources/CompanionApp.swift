import SwiftUI
import CoreLocation
import UIKit

@main
struct CompanionApp: App {
    @State private var sender = LocationSender()

    var body: some Scene {
        WindowGroup {
            CompanionView()
                .environment(sender)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = false
                    sender.start()
                }
        }
    }
}

struct CompanionView: View {
    @Environment(LocationSender.self) private var sender

    private let accentColor = Color(red: 0, green: 0.353, blue: 1)
    private let cardBackground = Color.white.opacity(0.08)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header Title
                    Text("3dUiCar GPS")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    // Big Status Circle
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(sender.isConnected ? accentColor.opacity(0.2) : Color.white.opacity(0.05))
                                .frame(width: 140, height: 140)

                            Circle()
                                .stroke(sender.isConnected ? accentColor : Color.gray.opacity(0.4), lineWidth: 3)
                                .frame(width: 140, height: 140)

                            Image(systemName: "location.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(sender.isConnected ? accentColor : .gray)
                        }

                        Text(sender.isConnected ? "Connecté à \(sender.ipadName ?? "l'iPad")" : "Recherche de l'iPad…")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(sender.isConnected ? .white : .gray)
                    }
                    .padding(.vertical, 8)

                    // Metrics Grid / Cards
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        metricCard(
                            title: "VITESSE",
                            value: speedString
                        )
                        metricCard(
                            title: "PRÉCISION GPS",
                            value: accuracyString
                        )
                        metricCard(
                            title: "CAP",
                            value: courseString
                        )
                        metricCard(
                            title: "ENVOYÉS",
                            value: "\(sender.sentCount)"
                        )
                    }

                    // Authorization Warning if not "Always"
                    if sender.authorizationStatus != .authorizedAlways {
                        VStack(spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 18))

                                Text("Autorise la localisation « Toujours » pour l'envoi écran verrouillé")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Ouvrir les Réglages")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.35))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Action Toggle Button
                    Button {
                        if sender.isRunning {
                            sender.stop()
                        } else {
                            sender.start()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(sender.isRunning ? Color.green : Color.red)
                                .frame(width: 10, height: 10)

                            Text(sender.isRunning ? "Envoi actif" : "Envoi arrêté")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(sender.isRunning ? accentColor : Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Explanatory Footer
                    Text("Active le partage de connexion de l'iPhone et connecte l'iPad dessus. Laisse cette app ouverte ou en arrière-plan pendant le trajet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.gray)
                .tracking(0.5)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var speedString: String {
        guard let speed = sender.lastLocation?.speed, speed >= 0 else {
            return "—"
        }
        let kmh = speed * 3.6
        return String(format: "%.0f km/h", kmh)
    }

    private var accuracyString: String {
        guard let hAcc = sender.lastLocation?.horizontalAccuracy, hAcc >= 0 else {
            return "—"
        }
        return String(format: "±%.0f m", hAcc)
    }

    private var courseString: String {
        guard let course = sender.lastLocation?.course, course >= 0 else {
            return "—"
        }
        return String(format: "%.0f°", course)
    }
}
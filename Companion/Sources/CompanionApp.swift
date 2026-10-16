import SwiftUI
import CoreLocation
import UIKit

@main
struct CompanionApp: App {
    @State private var sender = LocationSender()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.startSession()
    }

    var body: some Scene {
        WindowGroup {
            CompanionView()
                .environment(sender)
                .onAppear {
                    sender.start()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Log.markCleanExit()
            }
        }
    }
}

struct CompanionView: View {
    @Environment(LocationSender.self) private var sender
    @State private var reportURL: URL?
    @State private var showLogs = false

    private let accentColor = Color(red: 0, green: 0.353, blue: 1)
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var speedText: String {
        guard let speed = sender.lastLocation?.speed, speed >= 0 else { return "—" }
        return String(format: "%.0f km/h", speed * 3.6)
    }

    private var accuracyText: String {
        guard let acc = sender.lastLocation?.horizontalAccuracy, acc >= 0 else { return "—" }
        return String(format: "±%.0f m", acc)
    }

    private var courseText: String {
        guard let course = sender.lastLocation?.course, course >= 0 else { return "—" }
        return String(format: "%.0f°", course)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Text("3dUiCar GPS")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    ZStack {
                        Circle()
                            .fill(sender.isConnected ? accentColor : Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)

                        Image(systemName: "location.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                    }

                    Text(sender.status)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        statCard(title: "Vitesse", value: speedText)
                        statCard(title: "Précision", value: accuracyText)
                        statCard(title: "Cap", value: courseText)
                        statCard(title: "Messages envoyés", value: "\(sender.sentCount)")
                    }

                    if sender.authorization != .authorizedAlways {
                        VStack(spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 20))
                                Text("L'autorisation « Toujours » est nécessaire pour maintenir le flux GPS en arrière-plan lorsque l'iPhone est verrouillé.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            }

                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Ouvrir les Réglages")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(Color.orange.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connexion manuelle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Si l'iPad n'est pas trouvé automatiquement, saisis son adresse IP (iPad › Réglages › Capteurs).")
                            .font(.system(size: 13))
                            .foregroundStyle(.gray)

                        HStack(spacing: 8) {
                            TextField(
                                "172.20.10.2",
                                text: Binding(
                                    get: { sender.manualHost },
                                    set: { sender.manualHost = $0 }
                                )
                            )
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            if !sender.manualHost.isEmpty {
                                Button("Effacer") {
                                    sender.manualHost = ""
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button {
                        if sender.isRunning {
                            sender.stop()
                        } else {
                            sender.start()
                        }
                    } label: {
                        Text(sender.isRunning ? "Envoi actif" : "Envoi arrêté")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(sender.isRunning ? accentColor : Color.gray)
                            .clipShape(Capsule())
                    }

                    Button {
                        sender.reconnect()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnecter")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Journal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)

                        HStack(spacing: 12) {
                            Button {
                                reportURL = LogFile.shared.exportReport(header: Log.deviceHeader())
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Partager le journal")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                            }

                            if let reportURL {
                                ShareLink(item: reportURL) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.forward.app")
                                        Text("Envoyer")
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(accentColor)
                                    .clipShape(Capsule())
                                }
                            }
                        }

                        Button {
                            showLogs.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showLogs ? "chevron.up" : "chevron.down")
                                Text(showLogs ? "Masquer le journal" : "Afficher le journal")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        }

                        if showLogs {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(LogStore.shared.entries.suffix(60)) { entry in
                                    Text(entry.line)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text("Active le partage de connexion de l'iPhone et connecte l'iPad dessus (ou laisse le Wi-Fi activé sur les deux appareils). Laisse cette app ouverte ou en arrière-plan pendant le trajet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
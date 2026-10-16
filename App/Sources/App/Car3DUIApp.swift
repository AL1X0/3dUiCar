import SwiftUI

@main
struct Car3DUIApp: App {
    @State private var vehicle: VehicleState
    @State private var sensors: SensorHub
    @State private var settings = AppSettings()
    @State private var spotify = SpotifyController()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        TeslaFont.registerFonts()
        let v = VehicleState()
        _vehicle = State(initialValue: v)
        _sensors = State(initialValue: SensorHub(vehicle: v))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vehicle)
                .environment(settings)
                .environment(spotify)
                .environment(sensors)
                .onOpenURL { spotify.handle(url: $0) }
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active: spotify.connect()
            case .background: spotify.disconnect()
            default: break
            }
        }
    }
}

/// Disposition Tesla : voiture à gauche (≈33 %), carte à droite, dock en bas.
struct RootView: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(AppSettings.self) private var settings
    @Environment(SpotifyController.self) private var spotify
    @Environment(SensorHub.self) private var sensors
    @Environment(\.colorScheme) private var systemScheme
    @State private var simulator: SimulatorSource?
    private let tripTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var scheme: ColorScheme {
        switch settings.appearance {
        case .auto: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        let palette = scheme == .dark ? Palette.dark : Palette.light
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    CarPanelView()
                        .frame(width: geo.size.width * Theme.leftPanelRatio)
                    MapPanelView()
                        .overlay(alignment: .bottom) {
                            if settings.settingsOpen {
                                SettingsPanel()
                                    .padding(.top, 68)
                                    .transition(.move(edge: .bottom))
                            }
                        }
                        .clipped()
                }
                DockView(onCarTap: toggleSettings, onApp: openApp)
                    .frame(height: Theme.dockHeight)
            }
        }
        .environment(\.palette, palette)
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(settings.appearance == .auto ? nil : scheme)
        .dynamicTypeSize(settings.largeText ? .xLarge : .large)
        .background(palette.dock)
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            applyDemoMode()
            applyBrightness()
        }
        .onChange(of: settings.demoMode) { applyDemoMode() }
        .onChange(of: settings.brightness) { applyBrightness() }
        .onChange(of: settings.brightnessAuto) { applyBrightness() }
        .onReceive(tripTimer) { _ in vehicle.integrateTrip(dt: 1) }
    }

    /// Icône voiture du dock = ouvre/ferme les Réglages sur « Commandes » (comme Tesla).
    private func toggleSettings() {
        withAnimation(.spring(duration: 0.35)) {
            if !settings.settingsOpen { settings.selectedSection = .controls }
            settings.settingsOpen.toggle()
        }
    }

    private func openApp(_ app: DockApp) {
        switch app {
        case .music, .audio:
            if spotify.isConnected {
                UIApplication.shared.open(URL(string: "spotify:")!)
            } else {
                spotify.authorize()
            }
        case .phone:
            UIApplication.shared.open(URL(string: "tel:")!)
        default:
            break
        }
    }

    /// Mode démo = trajet simulé ; sinon capteurs réels de l'iPad (gyroscope, GPS).
    private func applyDemoMode() {
        if simulator == nil { simulator = SimulatorSource(vehicle: vehicle) }
        guard let simulator else { return }
        if settings.demoMode {
            sensors.stop()
            simulator.start()
        } else {
            simulator.stop()
            vehicle.speedKmh = 0
            vehicle.gear = .park
            vehicle.blinkerLeft = false
            vehicle.blinkerRight = false
            vehicle.braking = false
            vehicle.speedLimitKmh = nil
            vehicle.rpm = nil
            sensors.start()
        }
    }

    private func applyBrightness() {
        guard !settings.brightnessAuto else { return }
        UIScreen.main.brightness = settings.brightness
    }
}

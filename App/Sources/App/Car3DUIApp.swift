import SwiftUI

@main
struct Car3DUIApp: App {
    @State private var vehicle: VehicleState
    @State private var sensors: SensorHub
    @State private var feed: LocationFeed
    @State private var esp32: ESP32Source
    @State private var nav = NavigationModel()
    @State private var companion: CompanionReceiver
    @State private var weather: WeatherService
    @State private var settings = AppSettings()
    @State private var spotify = SpotifyController()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Log.startSession()
        TeslaFont.registerFonts()
        let v = VehicleState()
        let f = LocationFeed()
        _vehicle = State(initialValue: v)
        _feed = State(initialValue: f)
        _sensors = State(initialValue: SensorHub(vehicle: v, feed: f))
        _esp32 = State(initialValue: ESP32Source(vehicle: v))
        _companion = State(initialValue: CompanionReceiver(feed: f, vehicle: v))
        _weather = State(initialValue: WeatherService(vehicle: v))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vehicle)
                .environment(settings)
                .environment(spotify)
                .environment(sensors)
                .environment(feed)
                .environment(esp32)
                .environment(nav)
                .onOpenURL { spotify.handle(url: $0) }
                .onChange(of: feed.location) { _, loc in
                    if let loc { weather.update(location: loc) }
                }
                .onAppear {
                    nav.settings = settings
                    feed.restartListener = { companion.restart() }
                    sensors.startLocation()
                    companion.start()
                    esp32.start()
                }
        }
        .onChange(of: scenePhase) {
            Log.info(.app, "Phase : \(scenePhase)")
            switch scenePhase {
            case .active: spotify.connect()
            case .background:
                spotify.disconnect()
                Log.markCleanExit()
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
    @Environment(LocationFeed.self) private var feed
    @Environment(NavigationModel.self) private var nav
    @Environment(\.colorScheme) private var systemScheme
    @State private var simulator: SimulatorSource?
    @State private var volume = SystemVolume()
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
                        .frame(width: geo.size.width * settings.carPanelRatio)
                    MapPanelView()
                        .overlay(alignment: .bottom) {
                            if settings.libraryOpen {
                                SpotifyLibraryView()
                                    .padding(.top, 68)
                                    .transition(.move(edge: .bottom))
                            }
                            if settings.settingsOpen {
                                SettingsPanel()
                                    .padding(.top, 68)
                                    .transition(.move(edge: .bottom))
                            }
                        }
                        .clipped()
                }
                .overlay(alignment: .leading) {
                    PanelDivider(totalWidth: geo.size.width)
                        .offset(x: geo.size.width * settings.carPanelRatio - PanelDivider.hitWidth / 2)
                }
                DockView(onCarTap: toggleSettings, onApp: openApp)
                    .frame(height: Theme.dockHeight)
            }
        }
        .background(VolumeHost(volume: volume).frame(width: 1, height: 1))
        .environment(volume)
        .environment(\.palette, palette)
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(settings.appearance == .auto ? nil : scheme)
        .dynamicTypeSize(settings.largeText ? .xxLarge : .large)
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
        .onReceive(tripTimer) { _ in
            vehicle.integrateTrip(dt: 1)
            feed.checkTimeout()
        }
    }

    /// Icône voiture du dock = ouvre/ferme les Réglages sur « Commandes » (comme Tesla).
    private func toggleSettings() {
        withAnimation(.spring(duration: 0.35)) {
            if !settings.settingsOpen { settings.selectedSection = .controls }
            settings.settingsOpen.toggle()
        }
    }

    private func openApp(_ app: DockApp) {
        withAnimation(.spring(duration: 0.35)) {
            switch app {
            case .navigation:
                settings.settingsOpen = false
                nav.beginSearch()
            case .spotify:
                settings.mediaHidden = false
                settings.libraryOpen.toggle()
                spotify.ensureConnected()
            case .trips, .engine:
                settings.selectedSection = app == .trips ? .trips : .engine
                settings.settingsOpen = true
            }
        }
    }

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

/// Séparateur voiture / carte : glisser pour redimensionner, double-tap pour revenir à 33 %.
struct PanelDivider: View {
    static let hitWidth: CGFloat = 36
    let totalWidth: CGFloat
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var startRatio: Double?

    var body: some View {
        ZStack {
            Rectangle().fill(.clear)
            Capsule()
                .fill(startRatio == nil ? palette.inactive.opacity(0.7) : Theme.accent)
                .frame(width: 5, height: 64)
                .shadow(color: .black.opacity(0.2), radius: 2)
        }
        .frame(width: Self.hitWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { g in
                    if startRatio == nil { startRatio = settings.carPanelRatio }
                    let r = (startRatio ?? 0.33) + Double(g.translation.width / totalWidth)
                    settings.carPanelRatio = min(max(r, AppSettings.carPanelRange.lowerBound),
                                                 AppSettings.carPanelRange.upperBound)
                }
                .onEnded { _ in startRatio = nil }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring(duration: 0.35)) { settings.carPanelRatio = 0.33 }
        }
        .accessibilityLabel("Séparateur voiture / carte")
    }
}

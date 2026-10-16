import SwiftUI

@main
struct Car3DUIApp: App {
    @State private var vehicle = VehicleState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vehicle)
        }
    }
}

/// Disposition Tesla : voiture à gauche (≈33 %), carte à droite, dock en bas.
struct RootView: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.colorScheme) private var colorScheme
    @State private var simulator: SimulatorSource?

    var body: some View {
        let palette = colorScheme == .dark ? Palette.dark : Palette.light
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    CarPanelView()
                        .frame(width: geo.size.width * Theme.leftPanelRatio)
                    MapPanelView()
                }
                DockView(onCarTap: toggleSimulator, onApp: { _ in })
                    .frame(height: Theme.dockHeight)
            }
        }
        .environment(\.palette, palette)
        .background(palette.dock)
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            toggleSimulator()
        }
    }

    /// Phase 0 : la démo simulée tourne au lancement ; l'icône voiture du dock la coupe/relance.
    private func toggleSimulator() {
        if simulator == nil { simulator = SimulatorSource(vehicle: vehicle) }
        guard let simulator else { return }
        simulator.isRunning ? simulator.stop() : simulator.start()
    }
}

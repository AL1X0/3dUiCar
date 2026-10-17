import SwiftUI
import RealityKit

/// Vue RealityKit (ARView non-AR) intégrée en SwiftUI.
struct CarSceneView: UIViewRepresentable {
    let controller: CarSceneController

    func makeUIView(context: Context) -> ARView { controller.arView }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Panneau gauche : voiture 3D + HUD (rapport, vitesse, témoins) + raccourcis ouvrants à l'arrêt.
struct CarPanelView: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var controller: CarSceneController?

    var body: some View {
        ZStack(alignment: .top) {
            palette.background
            if let controller {
                CarSceneView(controller: controller)
            }
            CarHUDView()
            if vehicle.gear == .park {
                openingShortcuts
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            MediaPlayerView()
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            if controller == nil { controller = CarSceneController(vehicle: vehicle) }
            syncController()
        }
        .onChange(of: vehicle.gear) { syncController() }
        .onChange(of: colorScheme) { syncController() }
        .onChange(of: settings.showLanes) { syncController() }
        .onChange(of: settings.carFinish) { syncController() }
        .onChange(of: settings.mediaHidden) { syncController() }
    }

    /// Étiquettes « Ouvrir capot / coffre » du Figma (Frunk / Trunk Open).
    private var openingShortcuts: some View {
        @Bindable var v = vehicle
        return HStack {
            shortcut(title: "Capot", open: $v.hoodOpen)
            Spacer()
            shortcut(title: "Coffre", open: $v.trunkOpen)
        }
        .buttonStyle(TeslaPressStyle())
        .padding(.horizontal, 32)
        .offset(y: -120)
    }

    private func shortcut(title: String, open: Binding<Bool>) -> some View {
        Button {
            open.wrappedValue.toggle()
        } label: {
            VStack(spacing: 2) {
                Text(open.wrappedValue ? "Fermer" : "Ouvrir")
                    .font(TeslaFont.ui(11))
                    .foregroundStyle(palette.textSecondary)
                Text(title)
                    .font(TeslaFont.ui(14, .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(minWidth: Theme.minTouch, minHeight: Theme.minTouch)
            .contentShape(Rectangle())
        }
    }

    private func syncController() {
        guard let controller else { return }
        controller.cameraMode = vehicle.gear == .park ? .parked : .drive
        controller.backgroundColor = UIColor(palette.background)
        controller.showLanes = settings.showLanes
        // Zones masquées par le HUD (haut) et le lecteur Spotify (bas) : la caméra cadre le reste
        controller.topInset = vehicle.gear == .park ? 130 : 290
        controller.bottomInset = settings.mediaHidden ? 30 : 250
        controller.clayFinish = settings.carFinish == .clay
    }
}

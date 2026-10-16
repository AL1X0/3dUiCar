import SwiftUI

/// Panneau Réglages superposé à la carte : arbre de navigation à gauche, page à droite.
struct SettingsPanel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            navTree
                .frame(width: 270)
            VStack(spacing: 0) {
                SettingsHeader()
                page(for: settings.selectedSection)
                    .id(settings.selectedSection)
                    .transition(.opacity)
            }
        }
        .background(palette.panel)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: -2)
    }

    private var navTree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    let selected = section == settings.selectedSection
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { settings.selectedSection = section }
                    } label: {
                        HStack(spacing: 16) {
                            Image(section.icon).renderingMode(.template)
                                .resizable().scaledToFit().frame(width: 22, height: 22)
                                .foregroundStyle(palette.textSecondary)
                            Text(section.title)
                                .font(TeslaFont.ui(17, selected ? .semibold : .medium))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(selected ? palette.background : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func page(for section: SettingsSection) -> some View {
        switch section {
        case .search: SearchPage()
        case .controls: ControlsPage()
        case .pedals: PedalsPage()
        case .fuel: FuelPage()
        case .assist: AssistPage()
        case .locks: LocksPage()
        case .lights: LightsPage()
        case .display: DisplayPage()
        case .trips: TripsPage()
        case .navigation: NavigationSettingsPage()
        case .safety: SafetyPage()
        case .service: ServicePage()
        case .software: SoftwarePage()
        case .upgrades: UpgradesPage()
        }
    }
}

/// En-tête profil du Figma (« Easy Entry » + icônes d'état).
struct SettingsHeader: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "person.fill").font(.system(size: 18))
            Text("Profil conducteur").font(TeslaFont.ui(20, .medium))
            Spacer()
            Image(systemName: "arrow.down.to.line").font(.system(size: 13))
            Image(systemName: "bell.fill").font(.system(size: 13))
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13))
                .foregroundStyle(vehicle.obdConnected ? Theme.teal : palette.textSecondary)
            Image(systemName: "cellularbars").font(.system(size: 13))
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 32)
        .frame(height: 64)
    }
}

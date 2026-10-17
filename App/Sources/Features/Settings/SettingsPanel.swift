import SwiftUI

/// Panneau Réglages superposé à la carte : arbre de navigation à gauche, page à droite.
struct SettingsPanel: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette
    @State private var drag: CGFloat = 0

    /// Glisser la poignée ou l'en-tête vers le bas déplace tout le panneau et le ferme.
    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = max(0, $0.translation.height) }
            .onEnded { g in
                if drag > 90 || g.predictedEndTranslation.height > 260 {
                    withAnimation(Motion.panel) { settings.settingsOpen = false }
                }
                withAnimation(Motion.panel) { drag = 0 }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Zone de prise : glisser vers le bas ferme le panneau
            GrabHandle()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(closeGesture)
            HStack(spacing: 0) {
                navTree
                    .frame(width: 250)
                VStack(spacing: 0) {
                    SettingsHeader()
                        .contentShape(Rectangle())
                        .gesture(closeGesture)
                    page(for: settings.selectedSection)
                        .id(settings.selectedSection)
                        .transition(.opacity)
                }
            }
        }
        .background(palette.panel)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: -2)
        .offset(y: drag)
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
                    .buttonStyle(TeslaPressStyle())
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
        case .display: DisplayPage()
        case .navigation: NavigationSettingsPage()
        case .music: MusicPage()
        case .trips: TripsPage()
        case .engine: EnginePage()
        case .sensors: SensorsPage()
        case .service: ServicePage()
        case .software: SoftwarePage()
        case .logs: LogsPage()
        }
    }
}

/// En-tête : titre de la section + état réel des liaisons (GPS iPhone, OBD, Spotify) + fermeture.
struct SettingsHeader: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(LocationFeed.self) private var feed
    @Environment(SpotifyController.self) private var spotify
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            Text(settings.selectedSection.title).font(TeslaFont.ui(22, .semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
            indicator("location.fill", on: feed.phoneConnected, color: Theme.accent)
            indicator("antenna.radiowaves.left.and.right", on: vehicle.obdConnected, color: Theme.teal)
            indicator("music.note", on: spotify.isConnected, color: Theme.telltaleGreen)
            Button {
                withAnimation(Motion.panel) { settings.settingsOpen = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(TeslaPressStyle())
        }
        .padding(.leading, 32)
        .padding(.trailing, 16)
        .frame(height: 60)
    }

    private func indicator(_ symbol: String, on: Bool, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .foregroundStyle(on ? color : palette.inactive)
    }
}

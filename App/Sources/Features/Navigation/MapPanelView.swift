import SwiftUI
import MapKit
import CoreLocation

/// Panneau droit : carte qui suit la position (iPhone compagnon ou iPad), itinéraire,
/// recherche, bandeau de manœuvre et carte d'arrivée.
struct MapPanelView: View {
    @Environment(\.palette) private var palette
    @Environment(LocationFeed.self) private var feed
    @Environment(NavigationModel.self) private var nav
    @Environment(VehicleState.self) private var vehicle
    @State private var position: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: .init(latitude: 48.8566, longitude: 2.3522), distance: 1500, heading: 0, pitch: 45))
    @State private var following = true
    @State private var etaCollapsed = false

    var body: some View {
        Map(position: $position, interactionModes: .all) {
            ForEach(Array(nav.routes.enumerated()), id: \.offset) { index, route in
                if index != nav.selectedRouteIndex {
                    MapPolyline(route.polyline).stroke(.gray.opacity(0.6), lineWidth: 6)
                }
            }
            if let route = nav.route {
                MapPolyline(route.polyline).stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            }
            if let dest = nav.destination {
                Marker(dest.name ?? "Destination", coordinate: dest.placemark.coordinate).tint(Theme.accent)
            }
            if let loc = feed.location {
                Annotation("", coordinate: loc.coordinate, anchor: .center) {
                    CarMarker(heading: loc.course >= 0 ? loc.course : 0, mapHeading: position.camera?.heading ?? 0)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if position.positionedByUser { following = false }
        }
        .onChange(of: nav.phase) { _, phase in
            if phase != .navigating { etaCollapsed = false }
        }
        .onChange(of: feed.location) { _, loc in
            guard let loc else { return }
            nav.update(location: loc)
            if following { follow(loc) }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                StatusBarView()
                HStack(alignment: .top) {
                    if nav.phase == .navigating {
                        TurnBanner()
                    } else {
                        NavSearchBar()
                            .swipeToDismiss(.up) { nav.cancel() }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .overlay(alignment: .bottomLeading) {
            Group {
                switch nav.phase {
                case .preview:
                    RoutePreviewCard()
                        .swipeToDismiss(.down) { nav.cancel() }
                case .navigating:
                    if etaCollapsed {
                        etaPill
                    } else {
                        TripETACard()
                            .swipeToDismiss(.down) { etaCollapsed = true }
                    }
                default: EmptyView()
                }
            }
            .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            if !following {
                Button {
                    following = true
                    if let loc = feed.location { follow(loc) }
                } label: {
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(20)
            }
        }
    }

    /// Carte d'arrivée réduite : touche ou glisse vers le haut pour la rouvrir.
    private var etaPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered")
            Text(nav.arrivalDate.formatted(.dateTime.hour().minute()))
                .font(TeslaFont.ui(17, .semibold))
            Text("· \(Int(nav.remainingTime / 60)) min")
                .font(TeslaFont.ui(15))
                .foregroundStyle(palette.textSecondary)
        }
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(palette.panel, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .onTapGesture { withAnimation(.spring(duration: 0.3)) { etaCollapsed = false } }
        .swipeToDismiss(.up, threshold: 30) { etaCollapsed = false }
    }

    /// Caméra derrière la voiture, cap en haut, zoom selon la vitesse (comme Tesla).
    private func follow(_ loc: CLLocation) {
        let kmh = max(0, vehicle.speedKmh)
        let distance = 600 + min(kmh, 130) * 18
        let heading = loc.course >= 0 ? loc.course : (position.camera?.heading ?? 0)
        withAnimation(.linear(duration: 1)) {
            position = .camera(MapCamera(centerCoordinate: loc.coordinate, distance: distance,
                                         heading: heading, pitch: nav.phase == .navigating ? 60 : 45))
        }
    }
}

/// Flèche bleue Tesla orientée selon le cap.
struct CarMarker: View {
    let heading: Double
    let mapHeading: Double

    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.18)).frame(width: 44, height: 44)
            Image(systemName: "location.north.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white, Theme.accent)
                .padding(7)
                .background(Circle().fill(Theme.accent))
                .rotationEffect(.degrees(heading - mapHeading))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
    }
}

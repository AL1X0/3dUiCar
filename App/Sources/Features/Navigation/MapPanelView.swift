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
                case .preview: RoutePreviewCard()
                case .navigating: TripETACard()
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

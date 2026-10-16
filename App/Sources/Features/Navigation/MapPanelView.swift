import SwiftUI
import MapKit
import CoreLocation

/// Demande l'autorisation de localisation (GPS iPad). Le flux iPhone compagnon arrivera en phase 3.
@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func request() {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

/// Panneau droit : carte (suivi de cap) + barre de statut flottante.
struct MapPanelView: View {
    @Environment(\.palette) private var palette
    @State private var position: MapCameraPosition = .userLocation(
        followsHeading: true,
        fallback: .camera(MapCamera(centerCoordinate: .init(latitude: 48.8566, longitude: 2.3522),
                                    distance: 1500, heading: 0, pitch: 45))
    )
    @State private var permission = LocationPermission()

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .top) {
            StatusBarView()
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
        .onAppear { permission.request() }
    }
}

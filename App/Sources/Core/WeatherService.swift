import CoreLocation
import Foundation

/// Température extérieure réelle (Open-Meteo, sans clé) à la position courante, toutes les 15 min.
@MainActor
final class WeatherService {
    private let vehicle: VehicleState
    private var lastFetch: Date?
    private var lastCoordinate: CLLocation?

    init(vehicle: VehicleState) { self.vehicle = vehicle }

    func update(location: CLLocation) {
        let moved = lastCoordinate.map { location.distance(from: $0) > 5000 } ?? true
        let stale = lastFetch.map { Date().timeIntervalSince($0) > 900 } ?? true
        guard moved || stale else { return }
        lastFetch = Date()
        lastCoordinate = location
        let c = location.coordinate
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m")!
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let t = current["temperature_2m"] as? Double else { return }
            vehicle.outsideTempC = t
        }
    }
}

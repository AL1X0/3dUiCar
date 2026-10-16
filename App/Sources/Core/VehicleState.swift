import Foundation
import Observation

/// Rapport de boîte affiché dans le sélecteur P R N D.
enum Gear: String, CaseIterable, Sendable {
    case park = "P", reverse = "R", neutral = "N", drive = "D"
}

/// Source qui a fourni la valeur courante d'un signal (affichée dans la barre de statut).
enum SignalSource: String, Sendable {
    case none, simulator, device, phone, obd
}

/// État unique du véhicule, observé par toute l'UI et par la scène 3D.
/// Les sources de données (simulateur, capteurs, ESP32) écrivent ici sur le MainActor.
@MainActor
@Observable
final class VehicleState {
    // Conduite. La vitesse brute change en continu : elle n'est pas observée,
    // l'interface lit `displaySpeed` (entier) qui ne notifie qu'au changement.
    @ObservationIgnored var speedKmh: Double = 0 {
        didSet {
            let rounded = Int(speedKmh.rounded())
            if rounded != displaySpeed { displaySpeed = rounded }
        }
    }
    private(set) var displaySpeed = 0
    var gear: Gear = .park
    var speedLimitKmh: Int? = nil
    var rpm: Double? = nil            // nil tant qu'aucune source OBD
    var fuelLevel: Double? = nil      // 0...1, nil tant qu'aucune source

    // Dynamique (repère voiture) — lue à chaque image par la scène 3D, jamais par SwiftUI
    // directement (50 Hz) : non observée.
    @ObservationIgnored var longitudinalG: Double = 0     // + = accélération
    @ObservationIgnored var lateralG: Double = 0          // + = virage à gauche
    @ObservationIgnored var yawRateDegS: Double = 0       // + = vers la gauche
    @ObservationIgnored var roadPitchDeg: Double = 0      // + = montée

    // Carrosserie / éclairage
    var blinkerLeft = false
    var blinkerRight = false
    var lowBeam = false
    var highBeam = false
    var fogLights = false
    var braking = false
    var seatbeltUnfastened = false
    var locked = true
    var hoodOpen = false
    var trunkOpen = false
    var doorFLOpen = false
    var doorFROpen = false

    // Températures
    var outsideTempC: Double? = nil
    var coolantTempC: Double? = nil
    var driverTempC: Double = 20
    var passengerTempC: Double = 20

    // Provenance des données
    var speedSource: SignalSource = .none
    var locationSource: SignalSource = .none
    var obdConnected = false

    // Ordinateur de bord
    var odometerKm: Double = 48_250
    var tripDistanceKm: Double = 0
    var tripSeconds: Double = 0
    var tripMaxSpeedKmh: Double = 0

    var isMoving: Bool { speedKmh > 1 }

    /// Affecte seulement si la valeur change (évite des rendus SwiftUI inutiles).
    func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<VehicleState, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
    var tripAverageKmh: Double { tripSeconds > 0 ? tripDistanceKm / (tripSeconds / 3600) : 0 }

    /// Intègre la distance parcourue (appelé à 1 Hz).
    func integrateTrip(dt: Double) {
        let km = speedKmh / 3600 * dt
        odometerKm += km
        tripDistanceKm += km
        if isMoving { tripSeconds += dt }
        tripMaxSpeedKmh = max(tripMaxSpeedKmh, speedKmh)
    }

    func resetTrip() {
        tripDistanceKm = 0
        tripSeconds = 0
        tripMaxSpeedKmh = 0
    }
}

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
    // Conduite
    var speedKmh: Double = 0
    var gear: Gear = .park
    var speedLimitKmh: Int? = nil
    var rpm: Double? = nil            // nil tant qu'aucune source OBD
    var fuelLevel: Double = 0.9       // 0...1

    // Dynamique (repère voiture) — alimente l'animation de caisse
    var longitudinalG: Double = 0     // + = accélération
    var lateralG: Double = 0          // + = virage à gauche
    var yawRateDegS: Double = 0       // + = vers la gauche
    var roadPitchDeg: Double = 0      // + = montée

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
    var outsideTempC: Double? = 18
    var coolantTempC: Double? = nil
    var driverTempC: Double = 20
    var passengerTempC: Double = 20

    // Provenance des données
    var speedSource: SignalSource = .none
    var locationSource: SignalSource = .none
    var obdConnected = false

    var isMoving: Bool { speedKmh > 1 }
}

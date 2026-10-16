import CoreLocation
import CoreMotion
import Foundation
import Observation
import simd

/// Capteurs réels de l'iPad → `VehicleState` (quand le mode démo est coupé).
///
/// Repère voiture : haut = opposé de la gravité mesurée à la calibration, avant = axe appris
/// (par défaut : l'arrière de l'iPad, écran tourné vers le conducteur), gauche = haut × avant.
@MainActor
@Observable
final class SensorHub: NSObject {
    enum CalibrationState: Equatable { case none, level, complete }

    private(set) var running = false
    private(set) var calibration: CalibrationState = .none
    private(set) var hasGPS = false

    @ObservationIgnored private let vehicle: VehicleState
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let location = CLLocationManager()

    // Repère voiture exprimé dans le repère de l'iPad
    @ObservationIgnored private var up = SIMD3<Double>(0, 1, 0)
    @ObservationIgnored private var forward = SIMD3<Double>(0, 0, -1)
    @ObservationIgnored private var left = SIMD3<Double>(-1, 0, 0)

    // Filtres
    @ObservationIgnored private var longG = 0.0
    @ObservationIgnored private var latG = 0.0
    @ObservationIgnored private var yaw = 0.0
    @ObservationIgnored private var pitch = 0.0
    @ObservationIgnored private var forwardSamples = SIMD3<Double>(0, 0, 0)
    @ObservationIgnored private var forwardSampleCount = 0
    @ObservationIgnored private var stoppedSince: Date?
    @ObservationIgnored private var lastGPSFix: Date?

    private static let defaultsKey = "SensorHub.calibration.v1"

    init(vehicle: VehicleState) {
        self.vehicle = vehicle
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        location.activityType = .automotiveNavigation
        loadCalibration()
    }

    // MARK: - Démarrage

    func start() {
        guard !running else { return }
        running = true
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()

        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.process(data) }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
        location.stopUpdatingLocation()
    }

    // MARK: - Calibration

    /// Étape 1 (voiture à l'arrêt, sur le plat) : la gravité actuelle définit « haut ».
    /// L'axe avant est ensuite appris automatiquement à la première accélération en ligne droite.
    func calibrateLevel() {
        guard let g = motion.deviceMotion?.gravity else { return }
        up = -simd_normalize(SIMD3(g.x, g.y, g.z))
        forward = orthonormalForward(SIMD3(0, 0, -1))
        left = simd_cross(up, forward)
        forwardSamples = .zero
        forwardSampleCount = 0
        calibration = .level
        saveCalibration()
    }

    func resetCalibration() {
        up = SIMD3(0, 1, 0)
        forward = SIMD3(0, 0, -1)
        left = SIMD3(-1, 0, 0)
        calibration = .none
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    private func orthonormalForward(_ f: SIMD3<Double>) -> SIMD3<Double> {
        let h = f - simd_dot(f, up) * up
        return simd_length(h) > 1e-3 ? simd_normalize(h) : simd_normalize(simd_cross(SIMD3(1, 0, 0), up))
    }

    /// Accumule la direction de l'accélération horizontale pendant les accélérations franches
    /// en ligne droite ; après ~2 s cumulées, elle devient l'axe avant.
    private func learnForward(userAccel a: SIMD3<Double>, yawRate: Double) {
        guard calibration == .level else { return }
        let h = a - simd_dot(a, up) * up
        guard simd_length(h) > 0.12, abs(yawRate) < 0.05, vehicle.speedKmh < 60 else { return }
        // Les freinages comptent aussi, en sens inverse
        let sign: Double = simd_dot(h, forward) >= 0 ? 1 : -1
        forwardSamples += sign * h
        forwardSampleCount += 1
        if forwardSampleCount >= 100 {
            forward = orthonormalForward(forwardSamples)
            left = simd_cross(up, forward)
            calibration = .complete
            saveCalibration()
        }
    }

    // MARK: - Traitement

    private func process(_ m: CMDeviceMotion) {
        let a = SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)   // en g
        let r = SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)               // rad/s
        let g = simd_normalize(SIMD3(m.gravity.x, m.gravity.y, m.gravity.z))

        let yawRate = simd_dot(r, up)                       // + = vers la gauche
        learnForward(userAccel: a, yawRate: yawRate)

        let k = 0.12                                        // passe-bas ≈ 1,2 Hz à 50 Hz
        longG += (simd_dot(a, forward) - longG) * k
        latG += (simd_dot(a, left) - latG) * k
        yaw += (yawRate * 180 / .pi - yaw) * 0.2
        let slope = asin(max(-1, min(1, -simd_dot(g, forward)))) * 180 / .pi
        pitch += (slope - pitch) * 0.02                     // pente : très basse fréquence

        vehicle.longitudinalG = longG
        vehicle.lateralG = latG
        vehicle.yawRateDegS = yaw
        vehicle.roadPitchDeg = max(-15, min(15, pitch))
        if !vehicle.obdConnected {
            vehicle.braking = longG < -0.15 && vehicle.speedKmh > 3
        }
        if !hasGPS {
            estimateSpeedWithoutGPS()
        }
        updateGear()
    }

    /// Sans GPS : vitesse inconnue ; on reste à 0 (la caisse bouge quand même).
    private func estimateSpeedWithoutGPS() {
        if let last = lastGPSFix, Date().timeIntervalSince(last) < 3 { return }
        vehicle.speedSource = .none
    }

    /// Sans OBD : D dès que la voiture roule, P après 10 s d'arrêt.
    private func updateGear() {
        guard !vehicle.obdConnected else { return }
        if vehicle.speedKmh > 3 {
            stoppedSince = nil
            vehicle.gear = .drive
        } else if vehicle.gear == .drive {
            if stoppedSince == nil { stoppedSince = Date() }
            if let s = stoppedSince, Date().timeIntervalSince(s) > 10 { vehicle.gear = .park }
        }
    }

    // MARK: - Persistance

    private func saveCalibration() {
        let v = [up.x, up.y, up.z, forward.x, forward.y, forward.z, calibration == .complete ? 2 : 1]
        UserDefaults.standard.set(v, forKey: Self.defaultsKey)
    }

    private func loadCalibration() {
        guard let v = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [Double], v.count == 7 else { return }
        up = simd_normalize(SIMD3(v[0], v[1], v[2]))
        forward = orthonormalForward(SIMD3(v[3], v[4], v[5]))
        left = simd_cross(up, forward)
        calibration = v[6] >= 2 ? .complete : .level
    }
}

extension SensorHub: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let speed = loc.speed, accuracy = loc.horizontalAccuracy, speedAccuracy = loc.speedAccuracy
        Task { @MainActor in
            guard self.running else { return }
            self.vehicle.locationSource = .device
            // Vitesse valide uniquement avec un vrai fix GNSS (iPad Cellular / GPS externe)
            if speed >= 0, speedAccuracy >= 0, accuracy < 50 {
                self.hasGPS = true
                self.lastGPSFix = Date()
                self.vehicle.speedKmh = speed * 3.6
                self.vehicle.speedSource = .device
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

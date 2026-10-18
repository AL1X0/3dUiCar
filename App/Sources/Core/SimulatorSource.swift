import Foundation

/// Trajet de démo scripté (90 s en boucle) pour tester l'UI et la 3D sans capteurs.
@MainActor
final class SimulatorSource {
    private let vehicle: VehicleState
    private var loopTask: Task<Void, Never>?

    var isRunning: Bool {
        loopTask != nil
    }

    init(vehicle: VehicleState) {
        self.vehicle = vehicle
    }

    func start() {
        guard loopTask == nil else { return }
        Log.info(.app, "Mode démo : trajet simulé démarré")

        loopTask = Task { [weak self] in
            let clock = ContinuousClock()
            let startInstant = clock.now

            while !Task.isCancelled {
                guard let self else { return }

                let elapsed = clock.now - startInstant
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
                let cycleTime = seconds.truncatingRemainder(dividingBy: 90.0)

                self.updateVehicle(at: cycleTime)

                do {
                    try await Task.sleep(for: .milliseconds(33))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: - Simulation Update

    private func updateVehicle(at t: Double) {
        vehicle.set(\.speedSource, .simulator)
        vehicle.set(\.locationSource, .simulator)
        vehicle.set(\.lowBeam, true)
        vehicle.set(\.fuelLevel, 0.9)
        if vehicle.outsideTempC == nil { vehicle.outsideTempC = 18 }

        // Phase calculations
        var speed: Double = 0
        var longG: Double = 0
        var yawRate: Double = 0
        var pitch: Double = 0
        var isBraking = false
        var blinkLeft = false
        var blinkRight = false
        var gear: Gear = .park
        var limit: Int = 50

        switch t {
        case 0..<5:
            gear = .park
            speed = 0

        case 5..<6:
            gear = .drive
            speed = 0

        case 6..<20:
            gear = .drive
            let progress = (t - 6) / 14.0
            speed = smoothstep(0, 1, progress) * 50.0
            longG = sin(progress * .pi) * 0.25
            if t >= 18 {
                blinkLeft = true
            }

        case 20..<35:
            gear = .drive
            speed = 50.0
            let curveProgress = (t - 20) / 15.0
            yawRate = sin(curveProgress * .pi) * 15.0
            if t >= 33 {
                blinkRight = true
            }

        case 35..<45:
            gear = .drive
            speed = 50.0
            let curveProgress = (t - 35) / 10.0
            yawRate = -sin(curveProgress * .pi) * 15.0

        case 45..<55:
            gear = .drive
            limit = 90
            let progress = (t - 45) / 10.0
            speed = 50.0 + smoothstep(0, 1, progress) * 40.0
            longG = sin(progress * .pi) * 0.20
            pitch = sin(progress * .pi) * 4.0

        case 55..<70:
            gear = .drive
            limit = 90
            speed = 90.0

        case 70..<82:
            gear = .drive
            limit = 90
            let progress = (t - 70) / 12.0
            speed = 90.0 * (1.0 - smoothstep(0, 1, progress))
            longG = -sin(progress * .pi) * 0.35
            isBraking = speed > 0.1

        default:
            gear = .park
            speed = 0
            limit = 50
        }

        // Dynamics & Telemetry assignment
        vehicle.set(\.gear, gear)
        vehicle.speedKmh = max(0, speed)
        vehicle.set(\.speedLimitKmh, limit)
        vehicle.longitudinalG = longG
        vehicle.yawRateDegS = yawRate
        vehicle.roadPitchDeg = pitch

        let speedMps = vehicle.speedKmh / 3.6
        let yawRateRad = yawRate * .pi / 180.0
        vehicle.lateralG = (speedMps * yawRateRad) / 9.81

        vehicle.set(\.braking, isBraking)
        vehicle.set(\.blinkerLeft, blinkLeft)
        vehicle.set(\.blinkerRight, blinkRight)

        if vehicle.gear == .drive && vehicle.isMoving {
            vehicle.set(\.rpm, min(6500.0, max(800.0, 800.0 + vehicle.speedKmh * 35.0)))
        } else {
            vehicle.set(\.rpm, 800.0)
        }
        vehicle.set(\.coolantTempC, 90.0)
        vehicle.set(\.oilTempC, (95.0 + vehicle.speedKmh * 0.1).rounded())
        vehicle.set(\.boostBar, (max(-0.6, min(1.4, longG * 4)) * 10).rounded() / 10)
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
        return t * t * (3.0 - 2.0 * t)
    }
}
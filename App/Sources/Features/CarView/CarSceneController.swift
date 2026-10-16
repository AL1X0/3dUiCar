import RealityKit
import UIKit
import Combine

/// Pilote la scène 3D : charge Car.usdz, anime caisse / roues / ouvrants / feux
/// à partir de `VehicleState` à chaque frame.
///
/// Repère du modèle (voir Tools/model/build_car.py) : Y haut, avant = +Z, gauche = +X, mètres.
@MainActor
final class CarSceneController {
    enum CameraMode { case drive, parked }

    let arView: ARView
    private let vehicle: VehicleState
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let carRoot = Entity()      // tangage route
    private let sprung = Entity()       // masse suspendue : roulis / tangage dynamique
    private var ground: ModelEntity?
    private var laneLeft: [ModelEntity] = []
    private var laneRight: [ModelEntity] = []
    private var blinkers: [(entity: ModelEntity, left: Bool)] = []
    private var brakeLightModels: [ModelEntity] = []

    private var steer: [String: Entity] = [:]
    private var spin: [String: Entity] = [:]
    private var doorFL: Entity?, doorFR: Entity?, hood: Entity?, trunk: Entity?

    // État animé
    private var roll = Spring(), pitch = Spring()
    private var wheelAngle: Float = 0
    private var steerAngle: Float = 0
    private var doorFLAngle: Float = 0, doorFRAngle: Float = 0, hoodAngle: Float = 0, trunkAngle: Float = 0
    private var camPos = SIMD3<Float>(0, 3, -7.5)
    private var camTarget = SIMD3<Float>(0, 0.6, 4)
    private var lastBraking = false
    private var time: Double = 0
    private var updateSub: Cancellable?

    var cameraMode: CameraMode = .parked
    var backgroundColor: UIColor = .white {
        didSet {
            arView.environment.background = .color(backgroundColor)
            ground?.model?.materials = [Self.groundMaterial(backgroundColor)]
        }
    }

    private static let wheelRadius: Float = 0.31   // 205/40 R18
    private static let wheelBase: Float = 2.49

    init(vehicle: VehicleState) {
        self.vehicle = vehicle
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(backgroundColor)
        arView.renderOptions.insert(.disableMotionBlur)
        arView.renderOptions.insert(.disableDepthOfField)
        arView.renderOptions.insert(.disableCameraGrain)
        arView.scene.addAnchor(anchor)

        camera.camera.fieldOfViewInDegrees = 38
        anchor.addChild(camera)
        anchor.addChild(carRoot)
        sprung.position = [0, 0.5, 0]   // centre de gravité approximatif
        carRoot.addChild(sprung)

        setupLights()
        setupGround()
        setupLanes()

        updateSub = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated { self?.tick(dt: dt) }
        }
        Task { await loadCar() }
    }

    // MARK: - Mise en place

    private func loadCar() async {
        do {
            let car = try await Entity(named: "Car", in: .main)
            carRoot.addChild(car)
            for w in ["FL", "FR", "RL", "RR"] {
                steer[w] = car.findEntity(named: "Wheel_\(w)_Steer")
                spin[w] = car.findEntity(named: "Wheel_\(w)_Spin")
            }
            doorFL = car.findEntity(named: "Door_FL")
            doorFR = car.findEntity(named: "Door_FR")
            hood = car.findEntity(named: "Hood")
            trunk = car.findEntity(named: "Trunk")
            // Les éléments suspendus passent sous `sprung` (les roues restent au sol)
            for e in [car.findEntity(named: "Body"), doorFL, doorFR, hood, trunk].compactMap({ $0 }) {
                e.setParent(sprung, preservingWorldTransform: true)
            }
            brakeLightModels = Self.models(in: car).filter { $0.name.lowercased().contains("red_glass") }
            setupBlinkers(bounds: car.visualBounds(relativeTo: carRoot))
        } catch {
            print("Car.usdz introuvable : \(error)")
        }
    }

    private func setupLights() {
        let sun = DirectionalLight()
        sun.light.intensity = 3500
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 15, depthBias: 2)
        sun.look(at: .zero, from: [3, 8, 4], relativeTo: nil)
        anchor.addChild(sun)

        let fill = DirectionalLight()
        fill.light.intensity = 1200
        fill.look(at: .zero, from: [-4, 3, -5], relativeTo: nil)
        anchor.addChild(fill)
    }

    private static func groundMaterial(_ color: UIColor) -> SimpleMaterial {
        var m = SimpleMaterial(color: color, roughness: 1, isMetallic: false)
        m.metallic = 0
        return m
    }

    private func setupGround() {
        let plane = ModelEntity(mesh: .generatePlane(width: 200, depth: 200),
                                materials: [Self.groundMaterial(backgroundColor)])
        anchor.addChild(plane)
        ground = plane
    }

    /// Lignes de voie bleues (vue conduite) : segments repositionnés selon la courbure.
    private func setupLanes() {
        let mat = UnlitMaterial(color: UIColor(red: 0, green: 0.35, blue: 1, alpha: 1))
        let mesh = MeshResource.generateBox(width: 0.12, height: 0.01, depth: 2.05)
        for _ in 0..<30 {
            let l = ModelEntity(mesh: mesh, materials: [mat]); anchor.addChild(l); laneLeft.append(l)
            let r = ModelEntity(mesh: mesh, materials: [mat]); anchor.addChild(r); laneRight.append(r)
        }
    }

    /// Clignotants : petits blocs émissifs aux 4 coins (le modèle n'a pas de mesh dédié).
    private func setupBlinkers(bounds: BoundingBox) {
        let mat = UnlitMaterial(color: UIColor(red: 1, green: 0.6, blue: 0, alpha: 1))
        let mesh = MeshResource.generateBox(width: 0.1, height: 0.06, depth: 0.06, cornerRadius: 0.02)
        let x = bounds.max.x - 0.12, zf = bounds.max.z - 0.15, zr = bounds.min.z + 0.12
        for (pos, left) in [([x, 0.72, zf], true), ([-x, 0.72, zf], false),
                            ([x, 0.85, zr], true), ([-x, 0.85, zr], false)] as [(SIMD3<Float>, Bool)] {
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.position = pos - sprung.position
            e.isEnabled = false
            sprung.addChild(e)
            blinkers.append((e, left))
        }
    }

    private static func models(in e: Entity) -> [ModelEntity] {
        var out: [ModelEntity] = []
        if let m = e as? ModelEntity { out.append(m) }
        for c in e.children { out += models(in: c) }
        return out
    }

    // MARK: - Boucle

    private func tick(dt: Float) {
        guard dt > 0 else { return }
        time += Double(dt)
        let v = vehicle
        let speed = Float(v.speedKmh / 3.6)

        // Caisse : ressort-amortisseur (≈3° de roulis par g latéral, 2° de tangage par g)
        roll.target = Float(v.lateralG) * 3 * .pi / 180
        pitch.target = -Float(v.longitudinalG) * 2 * .pi / 180
        roll.step(dt); pitch.step(dt)
        sprung.orientation = simd_quatf(angle: roll.value, axis: [0, 0, 1])
            * simd_quatf(angle: pitch.value, axis: [1, 0, 0])
        carRoot.orientation = slerpTo(carRoot.orientation,
                                      simd_quatf(angle: -Float(v.roadPitchDeg) * .pi / 180, axis: [1, 0, 0]), dt * 2)

        // Roues : rotation selon la vitesse, braquage selon le lacet (modèle bicyclette)
        wheelAngle += speed / Self.wheelRadius * dt * (v.gear == .reverse ? -1 : 1)
        wheelAngle = wheelAngle.truncatingRemainder(dividingBy: 2 * .pi)
        let yaw = Float(v.yawRateDegS) * .pi / 180
        let targetSteer = speed > 1.5 ? max(-0.6, min(0.6, atan(Self.wheelBase * yaw / speed))) : steerAngle
        steerAngle += (targetSteer - steerAngle) * min(1, dt * 6)
        for e in spin.values { e.orientation = simd_quatf(angle: wheelAngle, axis: [1, 0, 0]) }
        steer["FL"]?.orientation = simd_quatf(angle: steerAngle, axis: [0, 1, 0])
        steer["FR"]?.orientation = simd_quatf(angle: steerAngle, axis: [0, 1, 0])

        // Ouvrants
        doorFLAngle = approach(doorFLAngle, v.doorFLOpen ? -65 : 0, dt)
        doorFRAngle = approach(doorFRAngle, v.doorFROpen ? 65 : 0, dt)
        hoodAngle = approach(hoodAngle, v.hoodOpen ? -55 : 0, dt)
        trunkAngle = approach(trunkAngle, v.trunkOpen ? 70 : 0, dt)
        rotate(doorFL, doorFLAngle, [0, 1, 0])
        rotate(doorFR, doorFRAngle, [0, 1, 0])
        rotate(hood, hoodAngle, [1, 0, 0])
        rotate(trunk, trunkAngle, [1, 0, 0])

        // Feux
        let blinkOn = Int(time * 3) % 2 == 0
        for b in blinkers {
            b.entity.isEnabled = blinkOn && (b.left ? v.blinkerLeft : v.blinkerRight)
        }
        if v.braking != lastBraking {
            lastBraking = v.braking
            setBrakeLights(v.braking)
        }

        updateLanes(speed: speed, yaw: yaw)
        updateCamera(dt: dt)
    }

    private func updateLanes(speed: Float, yaw: Float) {
        let show = cameraMode == .drive
        let k = speed > 1.5 ? yaw / speed : 0          // courbure (1/m), + = gauche
        for (i, pair) in zip(laneLeft, laneRight).enumerated() {
            let z = Float(i) * 2 - 6
            let dx = 0.5 * k * z * z
            let heading = atan(k * z)
            for (e, side) in [(pair.0, Float(1)), (pair.1, Float(-1))] {
                e.isEnabled = show
                e.position = [side * 1.7 + dx, 0.006, z]
                e.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
            }
        }
    }

    private func updateCamera(dt: Float) {
        let (pos, target): (SIMD3<Float>, SIMD3<Float>) = switch cameraMode {
        case .drive: ([0, 3.4, -8.5], [0, 0.4, 6])
        case .parked: ([4.6, 2.3, 5.8], [0, 0.55, 0])
        }
        let a = min(1, dt * 2.5)
        camPos += (pos - camPos) * a
        camTarget += (target - camTarget) * a
        camera.look(at: camTarget, from: camPos, relativeTo: nil)
    }

    private func setBrakeLights(_ on: Bool) {
        for m in brakeLightModels {
            guard var model = m.model else { continue }
            model.materials = model.materials.map { mat in
                guard var pbr = mat as? PhysicallyBasedMaterial else { return mat }
                pbr.emissiveColor = .init(color: on ? .red : .black)
                pbr.emissiveIntensity = on ? 2.5 : 0
                return pbr
            }
            m.model = model
        }
    }

    // MARK: - Utilitaires

    private func rotate(_ e: Entity?, _ deg: Float, _ axis: SIMD3<Float>) {
        e?.orientation = simd_quatf(angle: deg * .pi / 180, axis: axis)
    }

    private func approach(_ cur: Float, _ target: Float, _ dt: Float) -> Float {
        cur + (target - cur) * min(1, dt * 3)
    }

    private func slerpTo(_ a: simd_quatf, _ b: simd_quatf, _ t: Float) -> simd_quatf {
        simd_slerp(a, b, min(1, t))
    }
}

/// Ressort-amortisseur critique-ish pour un mouvement de caisse naturel.
struct Spring {
    var value: Float = 0
    var velocity: Float = 0
    var target: Float = 0
    var stiffness: Float = 60
    var damping: Float = 11

    mutating func step(_ dt: Float) {
        let a = stiffness * (target - value) - damping * velocity
        velocity += a * dt
        value += velocity * dt
    }
}

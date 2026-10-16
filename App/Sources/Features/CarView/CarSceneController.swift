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
    var showLanes = true
    /// Finition « argile » gris clair façon visualisation Tesla, ou peinture d'origine.
    var clayFinish = false {
        didSet { if clayFinish != oldValue { applyFinish() } }
    }
    private var originalMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]
    private var carModels: [ModelEntity] = []
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
            // Chaque pièce animée est placée sous un pivot aligné sur le repère voiture :
            // l'orientation d'origine des nœuds USD (conversion d'axes) est conservée.
            for w in ["FL", "FR", "RL", "RR"] {
                let st = pivot(for: car.findEntity(named: "Wheel_\(w)_Steer"), under: carRoot)
                steer[w] = st
                if let st { spin[w] = pivot(for: car.findEntity(named: "Wheel_\(w)_Spin"), under: st) }
            }
            // Les éléments suspendus passent sous `sprung` (les roues restent au sol)
            car.findEntity(named: "Body")?.setParent(sprung, preservingWorldTransform: true)
            doorFL = pivot(for: car.findEntity(named: "Door_FL"), under: sprung)
            doorFR = pivot(for: car.findEntity(named: "Door_FR"), under: sprung)
            hood = pivot(for: car.findEntity(named: "Hood"), under: sprung)
            trunk = pivot(for: car.findEntity(named: "Trunk"), under: sprung)
            carModels = Self.models(in: car)
            brakeLightModels = carModels.filter { $0.name.lowercased().contains("red_glass") }
            applyFinish()
            setupBlinkers(bounds: car.visualBounds(relativeTo: carRoot))
        } catch {
            print("Car.usdz introuvable : \(error)")
        }
    }

    /// Insère un pivot sans rotation à l'origine de `e` (charnière / centre de roue).
    private func pivot(for e: Entity?, under parent: Entity) -> Entity? {
        guard let e else { return nil }
        let p = Entity()
        p.name = e.name + "_Pivot"
        parent.addChild(p)
        p.position = e.position(relativeTo: parent)
        e.setParent(p, preservingWorldTransform: true)
        return p
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

    /// Sol non éclairé de la couleur du fond : pas d'horizon visible (rendu Tesla).
    private static func groundMaterial(_ color: UIColor) -> UnlitMaterial {
        UnlitMaterial(color: color)
    }

    private func setupGround() {
        let plane = ModelEntity(mesh: .generatePlane(width: 400, depth: 400),
                                materials: [Self.groundMaterial(backgroundColor)])
        anchor.addChild(plane)
        ground = plane

        // Ombre de contact douce sous la voiture
        if let tex = Self.contactShadowTexture() {
            var m = UnlitMaterial()
            m.color = .init(tint: .black, texture: .init(tex))
            m.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            let shadow = ModelEntity(mesh: .generatePlane(width: 2.9, depth: 5.4), materials: [m])
            shadow.position.y = 0.003
            carRoot.addChild(shadow)
        }
    }

    private static func contactShadowTexture() -> TextureResource? {
        let size = 256
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor(white: 0, alpha: 0.6).cgColor,
                                                 UIColor(white: 0, alpha: 0.25).cgColor,
                                                 UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 0.55, 1])
        else { return nil }
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                               endRadius: CGFloat(size) / 2, options: [])
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
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
        let show = cameraMode == .drive && showLanes
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

    private func applyFinish() {
        let clay = SimpleMaterial(color: UIColor(white: 0.93, alpha: 1), roughness: 0.55, isMetallic: false)
        let glass = SimpleMaterial(color: UIColor(white: 0.15, alpha: 1), roughness: 0.1, isMetallic: false)
        for m in carModels where !brakeLightModels.contains(where: { $0 === m }) {
            guard var model = m.model else { continue }
            let id = ObjectIdentifier(m)
            if originalMaterials[id] == nil { originalMaterials[id] = model.materials }
            if clayFinish {
                let isGlass = m.name.lowercased().contains("glass")
                model.materials = model.materials.map { _ in isGlass ? glass : clay }
            } else if let orig = originalMaterials[id] {
                model.materials = orig
            }
            m.model = model
        }
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

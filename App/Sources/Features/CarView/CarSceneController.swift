import RealityKit
import UIKit
import Combine

/// Pilote la scène 3D : charge Car.usdz, anime caisse / roues / ouvrants / feux
/// à partir de `VehicleState` à chaque frame.
///
/// Repère du modèle (voir Tools/model/build_car.py) : Y haut, avant = +Z, gauche = +X, mètres.
@MainActor
final class CarSceneController: NSObject {
    enum CameraMode { case drive, parked }

    let arView: ARView
    private let vehicle: VehicleState
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let carRoot = Entity()      // tangage route
    private var sprung: Entity?         // nœud « Sprung » du modèle : roulis / tangage dynamique
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
    private var doorFL_s = Spring(stiffness: 28, damping: 7.5), doorFR_s = Spring(stiffness: 28, damping: 7.5)
    private var hood_s = Spring(stiffness: 24, damping: 7), trunk_s = Spring(stiffness: 24, damping: 7)
    private var camPos = SIMD3<Float>(0, 3, -7.5)
    private var camTarget = SIMD3<Float>(0, 0.6, 4)
    private var lastBraking = false
    private var time: Double = 0
    private var updateSub: Cancellable?

    // Orbite manuelle (glisser = tourner, pincer = zoomer, double-tap = vue par défaut)
    private var userAzimuth: Float = 0
    private var userElevation: Float = 0
    private var userZoom: Float = 1
    private var lastTouch = Date.distantPast

    // Mesure de performance (journal toutes les 10 s)
    private var perfFrames = 0
    private var perfWorst: Float = 0
    private var perfElapsed: Float = 0

    var cameraMode: CameraMode = .parked
    /// Zones masquées par l'interface (points) : HUD en haut, lecteur Spotify en bas.
    /// La caméra cadre la voiture dans l'espace libre restant, quelle que soit la taille du panneau.
    var topInset: CGFloat = 260
    var bottomInset: CGFloat = 240
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
        super.init()
        arView.environment.background = .color(backgroundColor)
        arView.renderOptions.insert(.disableMotionBlur)
        arView.renderOptions.insert(.disableDepthOfField)
        arView.renderOptions.insert(.disableCameraGrain)
        arView.renderOptions.insert(.disableGroundingShadows)
        arView.renderOptions.insert(.disableAREnvironmentLighting)
        arView.scene.addAnchor(anchor)

        camera.camera.fieldOfViewInDegrees = 38
        anchor.addChild(camera)
        anchor.addChild(carRoot)

        setupLights()
        setupGround()
        setupLanes()

        updateSub = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            let dt = Float(event.deltaTime)
            MainActor.assumeIsolated { self?.tick(dt: dt) }
        }
        Task { await loadCar() }
        installGestures()
        enableHighFrameRate()
    }

    /// ProMotion : demande 120 i/s au rendu RealityKit si possible (sinon 60, limite d'Apple).
    private func enableHighFrameRate() {
        let maxFPS = UIScreen.main.maximumFramesPerSecond
        let selector = NSSelectorFromString("setPreferredFramesPerSecond:")
        if arView.responds(to: selector) {
            arView.setValue(maxFPS, forKey: "preferredFramesPerSecond")
            Log.info(.perf, "Rendu 3D demandé à \(maxFPS) i/s")
        } else {
            Log.info(.perf, "Écran \(maxFPS) Hz · le rendu RealityKit ne permet pas de changer la cadence")
        }
    }

    // MARK: - Gestes d'orbite

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset))
        reset.numberOfTapsRequired = 2
        [pan, pinch, reset].forEach(arView.addGestureRecognizer)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: arView)
        g.setTranslation(.zero, in: arView)
        userAzimuth -= Float(t.x) * 0.008
        userElevation = max(-0.2, min(1.0, userElevation + Float(t.y) * 0.005))
        lastTouch = Date()
        if g.state == .ended { Log.debug(.scene3D, "orbite az=\(userAzimuth) el=\(userElevation)") }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        userZoom = max(0.45, min(2.2, userZoom / Float(g.scale)))
        g.scale = 1
        lastTouch = Date()
    }

    @objc private func handleReset() {
        userAzimuth = 0
        userElevation = 0
        userZoom = 1
        lastTouch = .distantPast
    }

    // MARK: - Mise en place

    private func loadCar() async {
        do {
            let car = try await Entity(named: "Car", in: .main)
            carRoot.addChild(car)
            // Le modèle porte déjà sa hiérarchie finale avec des pivots sans rotation
            // (Tools/model/build_car.py) : on oriente ces nœuds directement.
            for w in ["FL", "FR", "RL", "RR"] {
                steer[w] = car.findEntity(named: "Wheel_\(w)_Steer")
                spin[w] = car.findEntity(named: "Wheel_\(w)_Spin")
            }
            sprung = car.findEntity(named: "Sprung")
            doorFL = car.findEntity(named: "Door_FL")
            doorFR = car.findEntity(named: "Door_FR")
            hood = car.findEntity(named: "Hood")
            trunk = car.findEntity(named: "Trunk")
            carModels = Self.models(in: car)
            brakeLightModels = carModels.filter { $0.name.lowercased().contains("red_glass") }
            applyFinish()
            setupBlinkers(bounds: car.visualBounds(relativeTo: carRoot))
            Log.info(.scene3D, "Car.usdz chargé : \(carModels.count) maillages, pivots \(steer.count) roues")
        } catch {
            Log.error(.scene3D, "Car.usdz introuvable : \(error)")
        }
    }

    private func setupLights() {
        let sun = DirectionalLight()
        sun.light.intensity = 3500
        // Pas d'ombre temps réel (coûteuse sur A12X) : l'ombre de contact suffit
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
            e.isEnabled = false
            if let sprung {
                sprung.addChild(e)
                e.setPosition(pos, relativeTo: carRoot)
            } else {
                carRoot.addChild(e)
                e.position = pos
            }
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
        roll.target = Float(v.lateralG) * 6 * .pi / 180
        pitch.target = -Float(v.longitudinalG) * 4.5 * .pi / 180
        roll.step(dt); pitch.step(dt)
        sprung?.orientation = simd_quatf(angle: roll.value, axis: [0, 0, 1])
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
        doorFL_s.target = v.doorFLOpen ? -65 : 0
        doorFR_s.target = v.doorFROpen ? 65 : 0
        hood_s.target = v.hoodOpen ? -55 : 0
        trunk_s.target = v.trunkOpen ? 70 : 0
        for i in 0..<2 {   // 2 sous-pas : stable même si une image dure longtemps
            let h = min(dt, 0.05) / 2
            _ = i
            doorFL_s.step(h); doorFR_s.step(h); hood_s.step(h); trunk_s.step(h)
        }
        rotate(doorFL, doorFL_s.value, [0, 1, 0])
        rotate(doorFR, doorFR_s.value, [0, 1, 0])
        rotate(hood, hood_s.value, [1, 0, 0])
        rotate(trunk, trunk_s.value, [1, 0, 0])

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
        measure(dt: dt)
    }

    private func measure(dt: Float) {
        perfFrames += 1
        perfElapsed += dt
        perfWorst = max(perfWorst, dt)
        guard perfElapsed >= 10 else { return }
        let fps = Float(perfFrames) / perfElapsed
        let level: LogLevel = fps < 40 ? .warning : .debug
        Log.write(level, .perf, String(format: "3D %.0f fps · pire image %.0f ms · %llu Mo · thermique %@",
                                       fps, perfWorst * 1000, Log.memoryMB(),
                                       ProcessInfo.processInfo.thermalState.label))
        perfFrames = 0
        perfElapsed = 0
        perfWorst = 0
    }

    private var lanesVisible = true

    private func updateLanes(speed: Float, yaw: Float) {
        let show = cameraMode == .drive && showLanes
        if show != lanesVisible {
            lanesVisible = show
            (laneLeft + laneRight).forEach { $0.isEnabled = show }
        }
        guard show else { return }
        let k = speed > 1.5 ? yaw / speed : 0          // courbure (1/m), + = gauche
        for (i, pair) in zip(laneLeft, laneRight).enumerated() {
            let z = Float(i) * 2 - 6
            let dx = 0.5 * k * z * z
            let heading = atan(k * z)
            for (e, side) in [(pair.0, Float(1)), (pair.1, Float(-1))] {
                e.position = [side * 1.7 + dx, 0.006, z]
                e.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
            }
        }
    }

    /// Caméra en coordonnées sphériques autour d'une cible ; l'orbite de l'utilisateur s'ajoute.
    /// En conduite, elle revient seule à la vue arrière 6 s après le dernier geste.
    private static let vFOV: Float = 38 * .pi / 180

    /// Caméra en coordonnées sphériques autour de la voiture. La distance est calculée pour que
    /// la voiture (et les voies en conduite) tienne en largeur ET en hauteur dans la zone libre
    /// du panneau : un panneau étroit recule la caméra, un panneau large la rapproche.
    /// L'orbite de l'utilisateur s'ajoute ; en conduite elle revient seule 6 s après le dernier geste.
    private func updateCamera(dt: Float) {
        let (center, azimuth, elevation, width, height): (SIMD3<Float>, Float, Float, Float, Float) = switch cameraMode {
        case .drive: ([0, 0.5, 1.2], .pi, 0.34, 4.8, 2.6)      // voiture + voies
        case .parked: ([0, 0.6, 0], 0.67, 0.22, 4.6, 2.2)
        }
        if cameraMode == .drive, Date().timeIntervalSince(lastTouch) > 6 {
            let k = min(1, dt * 1.5)
            userAzimuth -= userAzimuth * k
            userElevation -= userElevation * k
            userZoom += (1 - userZoom) * k
        }

        let size = arView.bounds.size
        let viewH = Float(max(size.height, 1)), viewW = Float(max(size.width, 1))
        let freeH = max(viewH - Float(topInset + bottomInset), viewH * 0.35)
        let freeFraction = freeH / viewH
        let tanV = tan(Self.vFOV / 2)
        let tanH = tanV * viewW / viewH
        let fitWidth = (width / 2) / tanH
        let fitHeight = (height / 2) / (tanV * freeFraction)
        let distance = max(fitWidth, fitHeight, 5) * 1.08 * userZoom

        // Décale le point visé pour centrer la voiture dans la zone libre (et non dans tout le panneau)
        let shiftFraction = Float(bottomInset - topInset) / viewH / 2      // > 0 : centre libre plus haut
        let el = max(0.05, min(1.35, elevation + userElevation))
        let verticalShift = shiftFraction * 2 * distance * tanV / max(cos(el), 0.3)
        let target = center - SIMD3(0, verticalShift, 0)

        let az = azimuth + userAzimuth
        let pos = target + distance * SIMD3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
        // Transitions caméra plus amples (P ↔ D), suivi du doigt réactif
        let follow: Float = Date().timeIntervalSince(lastTouch) < 0.3 ? 14 : 3.2
        let a = 1 - exp(-dt * follow)
        camPos += (pos - camPos) * a
        camTarget += (target - camTarget) * (1 - exp(-dt * 3.2))
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
    var stiffness: Float = 42
    var damping: Float = 6.5

    mutating func step(_ dt: Float) {
        let a = stiffness * (target - value) - damping * velocity
        velocity += a * dt
        value += velocity * dt
    }
}

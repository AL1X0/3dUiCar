import CoreLocation
import MapKit
import Observation
import simd

/// Géométrie de la route devant la voiture, pour les lignes bleues de la vue 3D.
///
/// Sources, par priorité :
/// 1. l'itinéraire de navigation en cours (tracé exact de la route) ;
/// 2. un « itinéraire d'anticipation » MapKit vers un point ~350 m devant, recalé sur la route ;
/// 3. à défaut (démo, pas de GPS) : arc déduit du lacet (gyroscope), comme avant.
///
/// Le tracé est gardé en coordonnées locales est/nord (mètres) autour du dernier fix GPS, puis
/// projeté à chaque image dans le repère voiture (x = gauche, z = avant) en extrapolant la position
/// avec la vitesse, pour que les lignes glissent en continu entre deux fixes (1 Hz).
@MainActor
@Observable
final class RoadAhead {
    enum Source: String { case route = "itinéraire", lookahead = "anticipation", none = "aucune" }

    @ObservationIgnored private(set) var source: Source = .none
    @ObservationIgnored private var fix: CLLocation?
    @ObservationIgnored private var fixTime = Date.distantPast
    @ObservationIgnored private var pathENU: [SIMD2<Double>] = []          // relatif à `fix`, mètres (est, nord)
    @ObservationIgnored private var lookaheadPolyline: MKPolyline?
    @ObservationIgnored private var lookaheadOrigin: CLLocation?
    @ObservationIgnored private var lookaheadPending = false
    @ObservationIgnored private var routePolyline: MKPolyline?

    /// Itinéraire de navigation (nil quand on ne navigue pas).
    func setRoute(_ polyline: MKPolyline?) {
        routePolyline = polyline
        rebuild()
    }

    /// Nouveau fix GPS (iPhone ou iPad).
    func update(location: CLLocation) {
        fix = location
        fixTime = Date()
        if routePolyline == nil { requestLookaheadIfNeeded(from: location) }
        rebuild()
    }

    /// Tracé dans le repère voiture (x gauche, z avant), points tous les ~2 m jusqu'à 90 m.
    func localPath() -> [SIMD2<Float>]? {
        guard source != .none, let fix, fix.course >= 0, pathENU.count >= 2 else { return nil }
        let heading = fix.course * .pi / 180
        let forward = SIMD2(sin(heading), cos(heading))           // (est, nord)
        let left = SIMD2(-cos(heading), sin(heading))
        // position estimée depuis le fix (extrapolation à vitesse constante, 2 s max)
        let dt = min(Date().timeIntervalSince(fixTime), 2)
        let car = forward * max(fix.speed, 0) * dt
        var out: [SIMD2<Float>] = []
        for p in pathENU {
            let d = p - car
            let z = simd_dot(d, forward), x = simd_dot(d, left)
            if z < -2 { continue }
            if z > 90 { break }
            out.append(SIMD2(Float(x), Float(z)))
        }
        return out.count >= 2 ? out : nil
    }

    // MARK: - Construction du tracé

    private func rebuild() {
        guard let fix else { source = .none; return }
        let (poly, src): (MKPolyline?, Source) = routePolyline != nil ? (routePolyline, .route)
            : (lookaheadPolyline != nil ? (lookaheadPolyline, .lookahead) : (nil, .none))
        guard let poly, poly.pointCount >= 2 else {
            setSource(.none)
            pathENU = []
            return
        }
        // Points de la polyligne à partir du plus proche de la voiture, rééchantillonnés à 2 m
        let pts = poly.points()
        let here = MKMapPoint(fix.coordinate)
        var nearest = 0
        var best = Double.greatestFiniteMagnitude
        for i in 0..<poly.pointCount {
            let d = here.distance(to: pts[i])
            if d < best { best = d; nearest = i }
        }
        // Trop loin de la route : tracé non pertinent
        guard best < 60 else { setSource(.none); pathENU = []; return }
        let origin = fix.coordinate
        var enu: [SIMD2<Double>] = []
        for i in max(0, nearest - 1)..<min(poly.pointCount, nearest + 200) {
            enu.append(Self.toENU(pts[i].coordinate, origin: origin))
        }
        pathENU = Self.resample(enu, step: 2, maxLength: 140)
        setSource(src)
    }

    private func setSource(_ s: Source) {
        guard s != source else { return }
        source = s
        Log.info(.nav, "Lignes de route : source \(s.rawValue)")
    }

    /// Demande un court itinéraire MapKit vers un point ~350 m devant pour connaître le tracé de
    /// la route empruntée. Validé seulement s'il part dans la direction du véhicule.
    private func requestLookaheadIfNeeded(from loc: CLLocation) {
        guard !lookaheadPending, loc.course >= 0, loc.speed > 4, loc.horizontalAccuracy < 30 else { return }
        if let origin = lookaheadOrigin, lookaheadPolyline != nil, loc.distance(from: origin) < 140 { return }
        lookaheadPending = true
        let target = Self.offset(loc.coordinate, meters: 350, bearing: loc.course)
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        request.transportType = .automobile
        Task {
            defer { lookaheadPending = false }
            guard let route = try? await MKDirections(request: request).calculate().routes.first else {
                lookaheadPolyline = nil
                rebuild()
                return
            }
            // Validation : distance raisonnable et départ dans le sens de marche
            let pts = route.polyline.points()
            var valid = route.distance < 350 * 1.7 && route.polyline.pointCount >= 2
            if valid {
                let a = pts[0].coordinate
                let k = min(route.polyline.pointCount - 1, 6)
                let bearing = Self.bearing(from: a, to: pts[k].coordinate)
                let diff = abs(((bearing - loc.course) + 540).truncatingRemainder(dividingBy: 360) - 180)
                valid = diff < 45
            }
            lookaheadPolyline = valid ? route.polyline : nil
            lookaheadOrigin = loc
            rebuild()
        }
    }

    // MARK: - Géodésie locale

    private static func toENU(_ c: CLLocationCoordinate2D, origin o: CLLocationCoordinate2D) -> SIMD2<Double> {
        let east = (c.longitude - o.longitude) * cos(o.latitude * .pi / 180) * 111_320
        let north = (c.latitude - o.latitude) * 110_540
        return SIMD2(east, north)
    }

    private static func offset(_ c: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let b = bearing * .pi / 180
        return CLLocationCoordinate2D(
            latitude: c.latitude + meters * cos(b) / 110_540,
            longitude: c.longitude + meters * sin(b) / (111_320 * cos(c.latitude * .pi / 180)))
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let d = toENU(b, origin: a)
        let deg = atan2(d.x, d.y) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    private static func resample(_ pts: [SIMD2<Double>], step: Double, maxLength: Double) -> [SIMD2<Double>] {
        guard var prev = pts.first else { return [] }
        var out = [prev]
        var carry = 0.0, total = 0.0
        for p in pts.dropFirst() {
            var seg = p - prev
            var len = simd_length(seg)
            while carry + len >= step, total < maxLength {
                let t = (step - carry) / len
                prev = prev + seg * t
                out.append(prev)
                total += step
                seg = p - prev
                len = simd_length(seg)
                carry = 0
            }
            carry += len
            prev = p
            if total >= maxLength { break }
        }
        return out
    }
}

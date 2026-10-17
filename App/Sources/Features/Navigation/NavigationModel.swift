import AVFoundation
import CoreLocation
import MapKit
import Observation

/// Type de manœuvre déduit du texte de l'étape MapKit (MKRoute.Step n'expose pas de type).
enum Maneuver: Sendable {
    case straight, left, right, slightLeft, slightRight, uTurn, roundabout, exit, merge, arrive

    var symbol: String {
        switch self {
        case .straight: "arrow.up"
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .slightLeft: "arrow.up.left"
        case .slightRight: "arrow.up.right"
        case .uTurn: "arrow.uturn.down"
        case .roundabout: "arrow.triangle.turn.up.right.circle"
        case .exit: "arrow.up.right.square"
        case .merge: "arrow.merge"
        case .arrive: "mappin.circle.fill"
        }
    }

    init(instruction: String, isLast: Bool) {
        let t = instruction.lowercased()
        if isLast || t.contains("destination") || t.contains("arrivée") { self = .arrive }
        else if t.contains("rond-point") || t.contains("giratoire") { self = .roundabout }
        else if t.contains("demi-tour") { self = .uTurn }
        else if t.contains("sortie") { self = .exit }
        else if t.contains("rejoignez") || t.contains("insérez") { self = .merge }
        else if t.contains("légèrement à gauche") || t.contains("serrez à gauche") { self = .slightLeft }
        else if t.contains("légèrement à droite") || t.contains("serrez à droite") { self = .slightRight }
        else if t.contains("à gauche") { self = .left }
        else if t.contains("à droite") { self = .right }
        else { self = .straight }
    }
}

/// Recherche de destination, calcul d'itinéraire et guidage étape par étape.
@MainActor
@Observable
final class NavigationModel: NSObject {
    enum Phase: Equatable { case idle, searching, preview, navigating }

    // Recherche
    var query = "" { didSet { completer.queryFragment = query } }
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var phase: Phase = .idle

    // Itinéraire
    private(set) var destination: MKMapItem?
    private(set) var routes: [MKRoute] = []
    var selectedRouteIndex = 0
    var route: MKRoute? { routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil }
    private(set) var isCalculating = false
    private(set) var errorMessage: String?

    // Guidage
    private(set) var stepIndex = 0
    private(set) var distanceToNextStep: CLLocationDistance = 0
    private(set) var remainingDistance: CLLocationDistance = 0
    private(set) var remainingTime: TimeInterval = 0

    var currentStep: MKRoute.Step? {
        guard let route, route.steps.indices.contains(stepIndex) else { return nil }
        return route.steps[stepIndex]
    }
    var maneuver: Maneuver {
        guard let route, let step = currentStep else { return .straight }
        return Maneuver(instruction: step.instructions, isLast: stepIndex == route.steps.count - 1)
    }
    var arrivalDate: Date { Date().addingTimeInterval(remainingTime) }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var offRouteSince: Date?
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored weak var settings: AppSettings?

    override init() {
        super.init()
        speech.delegate = self
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    // MARK: - Recherche

    func beginSearch() { phase = .searching }

    func cancel() {
        phase = .idle
        query = ""
        suggestions = []
        routes = []
        destination = nil
        errorMessage = nil
    }

    func select(_ completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
                errorMessage = "Adresse introuvable"
                return
            }
            await preview(to: item)
        }
    }

    // MARK: - Itinéraire

    func preview(to item: MKMapItem) async {
        destination = item
        phase = .preview
        await calculate(alternatives: true)
    }

    private func calculate(alternatives: Bool) async {
        guard let destination else { return }
        isCalculating = true
        defer { isCalculating = false }
        let request = MKDirections.Request()
        if let loc = lastLocation {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        } else {
            request.source = .forCurrentLocation()
        }
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = alternatives
        if settings?.avoidTolls == true { request.tollPreference = .avoid }
        if settings?.avoidHighways == true { request.highwayPreference = .avoid }
        do {
            let response = try await MKDirections(request: request).calculate()
            routes = response.routes
            Log.info(.nav, "\(routes.count) itinéraire(s) vers \(destination.name ?? "?")")
            selectedRouteIndex = 0
            errorMessage = nil
            if let route {
                remainingDistance = route.distance
                remainingTime = route.expectedTravelTime
            }
        } catch {
            errorMessage = "Itinéraire impossible : \(error.localizedDescription)"
            Log.error(.nav, "Calcul d'itinéraire : \(error)")
        }
    }

    func start() {
        guard route != nil else { return }
        phase = .navigating
        Log.info(.nav, "Guidage démarré")
        stepIndex = firstMeaningfulStep()
        announced = []
        speak(currentStep?.instructions)
    }

    func stop() {
        speech.stopSpeaking(at: .immediate)
        cancel()
    }

    private func firstMeaningfulStep() -> Int {
        // La 1re étape MapKit est souvent vide (« Départ »)
        guard let route else { return 0 }
        return route.steps.firstIndex { $0.distance > 0 && !$0.instructions.isEmpty } ?? 0
    }

    // MARK: - Suivi

    /// À appeler à chaque nouvelle position (iPhone ou iPad).
    func update(location: CLLocation) {
        lastLocation = location
        guard phase == .navigating, let route else { return }

        // Avance d'étape quand on est à moins de 25 m du point final de l'étape courante
        while let step = currentStep, stepIndex < route.steps.count - 1,
              location.distance(from: step.polyline.lastCoordinateLocation) < 25 {
            stepIndex += 1
            speak(currentStep?.instructions)
        }
        guard let step = currentStep else { return }
        distanceToNextStep = location.distance(from: step.polyline.lastCoordinateLocation)
        let after = route.steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        remainingDistance = distanceToNextStep + after
        let speed = max(location.speed, 8)
        remainingTime = max(remainingDistance / speed, route.expectedTravelTime * remainingDistance / max(route.distance, 1))

        announce(step: step)
        checkArrival(location: location, route: route)
        checkOffRoute(location: location, route: route)
    }

    private func announce(step: MKRoute.Step) {
        for threshold in [800.0, 200.0] where distanceToNextStep < threshold && distanceToNextStep > threshold - 120 {
            let key = "\(stepIndex)-\(Int(threshold))"
            guard !announced.contains(key) else { continue }
            announced.insert(key)
            speak("Dans \(Int(threshold)) mètres, \(step.instructions.lowercasedFirst)")
        }
    }

    private func checkArrival(location: CLLocation, route: MKRoute) {
        guard let dest = destination?.placemark.location, location.distance(from: dest) < 30 else { return }
        speak("Vous êtes arrivé.")
        phase = .idle
        routes = []
    }

    private func checkOffRoute(location: CLLocation, route: MKRoute) {
        let d = route.polyline.distance(to: location.coordinate)
        guard d > 60, location.horizontalAccuracy < 30 else { offRouteSince = nil; return }
        if offRouteSince == nil { offRouteSince = Date() }
        guard let since = offRouteSince, Date().timeIntervalSince(since) > 4, !isCalculating else { return }
        offRouteSince = nil
        speak("Recalcul de l'itinéraire.")
        Log.info(.nav, "Hors itinéraire (\(Int(d)) m) : recalcul")
        Task {
            await calculate(alternatives: false)
            stepIndex = firstMeaningfulStep()
            announced = []
        }
    }

    private func speak(_ text: String?) {
        guard let text, !text.isEmpty, settings?.voiceGuidance ?? true else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "fr-FR")
        u.rate = 0.5
        AudioSession.beginVoicePrompt()
        speech.speak(u)
    }
}

extension NavigationModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(8))
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Géométrie

extension MKPolyline {
    var lastCoordinateLocation: CLLocation {
        var c = CLLocationCoordinate2D()
        getCoordinates(&c, range: NSRange(location: max(0, pointCount - 1), length: 1))
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
    }

    /// Distance minimale (m) entre un point et la polyligne (projection sur chaque segment).
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let p = MKMapPoint(coordinate)
        let pts = points()
        var best = CLLocationDistance.greatestFiniteMagnitude
        guard pointCount > 1 else { return pointCount == 1 ? p.distance(to: pts[0]) : best }
        for i in 0..<(pointCount - 1) {
            let a = pts[i], b = pts[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0
            let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            best = min(best, p.distance(to: proj))
        }
        return best
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

extension NavigationModel: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !synthesizer.isSpeaking { AudioSession.endVoicePrompt() }
        }
    }
}

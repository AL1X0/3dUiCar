import CoreLocation
import Foundation
import Network
import Observation
import UIKit

/// Envoie le GPS de l'iPhone à l'iPad (docs/protocols.md §1).
/// Découverte Bonjour (Wi-Fi, partage de connexion ou Wi-Fi pair-à-pair AWDL) avec repli
/// sur une adresse IP saisie à la main ; reconnexion automatique toutes les 3 s.
@MainActor
@Observable
final class LocationSender: NSObject, CLLocationManagerDelegate {
    static let serviceType = "_car3dui._udp"
    static let port: NWEndpoint.Port = 47800

    var isRunning = false
    var ipadName: String?
    var isConnected = false
    var status = "Arrêté"
    var lastLocation: CLLocation?
    var sentCount = 0
    var authorization: CLAuthorizationStatus
    /// Adresse IP de l'iPad (affichée dans Réglages › Capteurs sur l'iPad), vide = Bonjour.
    var manualHost: String {
        didSet {
            UserDefaults.standard.set(manualHost, forKey: "manualHost")
            Log.info(.companion, "Adresse manuelle : \(manualHost.isEmpty ? "aucune (Bonjour)" : manualHost)")
            reconnect()
        }
    }

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var results: Set<NWBrowser.Result> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSend = Date.distantPast
    @ObservationIgnored private var sendErrors = 0

    override init() {
        authorization = locationManager.authorizationStatus
        manualHost = UserDefaults.standard.string(forKey: "manualHost") ?? ""
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    private var parameters: NWParameters {
        let p = NWParameters.udp
        p.includePeerToPeer = true
        return p
    }

    // MARK: - Démarrage

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Log.info(.companion, "Démarrage de l'envoi")
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
        startBrowser()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        Log.info(.companion, "Arrêt de l'envoi")
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        browser?.cancel()
        browser = nil
        drop()
        status = "Arrêté"
    }

    func reconnect() {
        drop()
        if isRunning { connectIfNeeded() }
    }

    /// 1 Hz : heartbeat toutes les 2 s, reconnexion si besoin.
    private func tick() {
        if connection == nil { connectIfNeeded() }
        if Date().timeIntervalSince(lastSend) >= 2 {
            send(["v": 1, "type": "heartbeat", "t": Date().timeIntervalSince1970, "name": UIDevice.current.name])
        }
    }

    // MARK: - Découverte et connexion

    private func startBrowser() {
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.results = results
                Log.info(.companion, "Bonjour : \(results.count) iPad trouvé(s) \(results.map { "\($0.endpoint)" })")
                self.connectIfNeeded()
            }
        }
        b.stateUpdateHandler = { state in
            switch state {
            case .failed(let e): Log.error(.companion, "Recherche Bonjour en échec : \(e)")
            case .waiting(let e): Log.warning(.companion, "Recherche Bonjour en attente : \(e) — autorisation « Réseau local » ?")
            case .ready: Log.info(.companion, "Recherche Bonjour active")
            default: break
            }
        }
        b.start(queue: .main)
        browser = b
        status = "Recherche de l'iPad…"
    }

    private func connectIfNeeded() {
        guard isRunning, connection == nil else { return }
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        if !host.isEmpty {
            ipadName = host
            open(.hostPort(host: NWEndpoint.Host(host), port: Self.port), label: "IP \(host)")
        } else if let result = results.first {
            if case let .service(name, _, _, _) = result.endpoint { ipadName = name }
            open(result.endpoint, label: "Bonjour \(ipadName ?? "?")")
        } else {
            status = "Recherche de l'iPad…"
        }
    }

    private func open(_ endpoint: NWEndpoint, label: String) {
        Log.info(.companion, "Connexion vers \(label)")
        let c = NWConnection(to: endpoint, using: parameters)
        connection = c
        c.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionChanged(state, label: label) }
        }
        c.start(queue: .main)
    }

    private func connectionChanged(_ state: NWConnection.State, label: String) {
        switch state {
        case .ready:
            isConnected = true
            sendErrors = 0
            status = "Connecté à \(ipadName ?? "l'iPad")"
            Log.info(.companion, "Liaison prête (\(label))")
        case .waiting(let e):
            isConnected = false
            status = "En attente : \(e.localizedDescription)"
            Log.warning(.companion, "Liaison en attente : \(e)")
        case .failed(let e):
            Log.error(.companion, "Liaison en échec : \(e)")
            drop()
        case .cancelled:
            isConnected = false
        default:
            break
        }
    }

    private func drop() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    // MARK: - Envoi

    private func send(_ payload: [String: Any]) {
        guard let connection, isConnected else { return }
        // JSON n'accepte pas NaN / infini
        let clean = payload.mapValues { v -> Any in
            if let d = v as? Double, !d.isFinite { return -1.0 }
            return v
        }
        guard let data = try? JSONSerialization.data(withJSONObject: clean) else {
            Log.error(.companion, "Encodage JSON impossible")
            return
        }
        lastSend = Date()
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.sendErrors += 1
                    Log.warning(.companion, "Envoi en échec : \(error)")
                    if self.sendErrors >= 3 { self.drop() }   // reconnexion au prochain tick
                } else {
                    self.sentCount += 1
                }
            }
        })
    }

    private func sendLocation(_ l: CLLocation) {
        send([
            "v": 1, "type": "location", "t": l.timestamp.timeIntervalSince1970,
            "lat": l.coordinate.latitude, "lon": l.coordinate.longitude, "alt": l.altitude,
            "hAcc": l.horizontalAccuracy, "speed": l.speed, "sAcc": l.speedAccuracy,
            "course": l.course, "cAcc": l.courseAccuracy,
        ])
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            Log.info(.gps, "Autorisation localisation : \(status.rawValue)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = latest
            self.sendLocation(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.warning(.gps, "Erreur localisation : \(error.localizedDescription)")
    }
}

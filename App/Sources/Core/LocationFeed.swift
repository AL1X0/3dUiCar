import CoreLocation
import Foundation
import Network
import Observation

/// Position courante unifiée : iPhone compagnon (prioritaire, vrai GPS) ou iPad.
@MainActor
@Observable
final class LocationFeed {
    private(set) var location: CLLocation?
    private(set) var source: SignalSource = .none
    private(set) var phoneConnected = false
    private(set) var phoneName: String?

    // Diagnostic de la liaison iPhone (affiché dans Réglages › Capteurs)
    var listenerState = "arrêté"
    var messagesReceived = 0
    var lastMessageDate: Date?
    var localAddresses: [String] = []
    /// Relance l'écoute (bouton du diagnostic) ; fourni par l'app.
    @ObservationIgnored var restartListener: (() -> Void)?

    @ObservationIgnored private var lastPhoneFix: Date?

    /// Position iPad : ignorée tant que l'iPhone fournit un flux récent.
    func updateFromDevice(_ loc: CLLocation) {
        if let last = lastPhoneFix, Date().timeIntervalSince(last) < 5 { return }
        location = loc
        source = .device
    }

    func updateFromPhone(_ loc: CLLocation) {
        if !phoneConnected { Log.info(.companion, "Flux GPS iPhone reçu") }
        lastPhoneFix = Date()
        location = loc
        source = .phone
        phoneConnected = true
    }

    func phoneHeartbeat(name: String?) {
        lastPhoneFix = lastPhoneFix ?? Date()
        phoneConnected = true
        if let name { phoneName = name }
    }

    /// Appelé à 1 Hz : le flux iPhone est perdu après 5 s sans message.
    func checkTimeout() {
        guard let last = lastPhoneFix, Date().timeIntervalSince(last) > 5 else { return }
        Log.warning(.companion, "Flux GPS iPhone perdu (aucun message depuis 5 s)")
        phoneConnected = false
        lastPhoneFix = nil
        if source == .phone { source = .none }
    }
}

/// Reçoit le GPS de l'app iPhone compagnon (docs/protocols.md §1) :
/// service Bonjour `_car3dui._udp`, datagrammes JSON.
@MainActor
final class CompanionReceiver {
    static let serviceType = "_car3dui._udp"
    /// Port fixe : permet aussi une connexion manuelle par adresse IP depuis l'iPhone.
    static let port: NWEndpoint.Port = 47800

    private let feed: LocationFeed
    private let vehicle: VehicleState
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var retry: Task<Void, Never>?

    init(feed: LocationFeed, vehicle: VehicleState) {
        self.feed = feed
        self.vehicle = vehicle
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.udp
        params.includePeerToPeer = true           // AWDL : marche même hors réseau commun
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params, on: Self.port)
            l.service = NWListener.Service(name: UIDeviceName.current, type: Self.serviceType)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            l.serviceRegistrationUpdateHandler = { change in
                if case .add(let endpoint) = change { Log.info(.companion, "Service Bonjour publié : \(endpoint)") }
            }
            l.start(queue: .main)
            listener = l
            feed.localAddresses = Self.localIPv4Addresses()
            Log.info(.companion, "Écoute UDP port \(Self.port) · IP \(feed.localAddresses.joined(separator: ", "))")
        } catch {
            feed.listenerState = "erreur : \(error.localizedDescription)"
            Log.error(.companion, "NWListener impossible : \(error)")
            scheduleRetry()
        }
    }

    func stop() {
        retry?.cancel()
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    func restart() {
        Log.info(.companion, "Redémarrage de l'écoute")
        stop()
        start()
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            feed.listenerState = "en écoute"
            Log.info(.companion, "Écoute prête")
        case .waiting(let error):
            feed.listenerState = "en attente : \(error.localizedDescription)"
            Log.warning(.companion, "Écoute en attente : \(error) — autorisation « Réseau local » refusée ?")
        case .failed(let error):
            feed.listenerState = "échec : \(error.localizedDescription)"
            Log.error(.companion, "Écoute en échec : \(error)")
            listener = nil
            scheduleRetry()
        case .cancelled:
            feed.listenerState = "arrêté"
        default:
            break
        }
    }

    private func scheduleRetry() {
        retry?.cancel()
        retry = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            start()
        }
    }

    private func accept(_ conn: NWConnection) {
        Log.info(.companion, "Nouvelle liaison depuis \(conn.endpoint)")
        connections.removeAll { $0.state == .cancelled }
        connections.append(conn)
        conn.stateUpdateHandler = { state in
            if case .failed(let e) = state { Log.warning(.companion, "Liaison en échec : \(e)") }
        }
        conn.start(queue: .main)
        receive(on: conn)
        feed.localAddresses = Self.localIPv4Addresses()
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.handle(data) }
                if let error {
                    Log.warning(.companion, "Réception interrompue : \(error)")
                } else {
                    self.receive(on: conn)
                }
            }
        }
    }

    /// Adresses IPv4 locales (à saisir dans l'app iPhone si Bonjour ne trouve pas l'iPad).
    static func localIPv4Addresses() -> [String] {
        var out: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return out }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append("\(String(cString: host)) (\(name))")
            }
        }
        return out
    }

    private struct Message: Decodable {
        let v: Int
        let type: String
        let t: Double
        let lat, lon, alt, hAcc, speed, sAcc, course, cAcc: Double?
        let name: String?
    }

    private func handle(_ data: Data) {
        feed.messagesReceived += 1
        feed.lastMessageDate = Date()
        let m: Message
        do {
            m = try JSONDecoder().decode(Message.self, from: data)
        } catch {
            Log.warning(.companion, "Message illisible (\(data.count) o) : \(error.localizedDescription) — \(String(decoding: data.prefix(120), as: UTF8.self))")
            return
        }
        if feed.messagesReceived == 1 || feed.messagesReceived % 60 == 0 {
            Log.debug(.companion, "Message n°\(feed.messagesReceived) type=\(m.type)")
        }
        switch m.type {
        case "location":
            guard let lat = m.lat, let lon = m.lon else { return }
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: m.alt ?? 0,
                horizontalAccuracy: m.hAcc ?? 10,
                verticalAccuracy: -1,
                course: m.course ?? -1,
                courseAccuracy: m.cAcc ?? -1,
                speed: m.speed ?? -1,
                speedAccuracy: m.sAcc ?? -1,
                timestamp: Date(timeIntervalSince1970: m.t)
            )
            feed.updateFromPhone(loc)
            vehicle.set(\.locationSource, .phone)
            if let speed = m.speed, speed >= 0, !vehicle.obdConnected {
                vehicle.speedKmh = speed * 3.6
                vehicle.set(\.speedSource, .phone)
            }
        case "heartbeat":
            feed.phoneHeartbeat(name: m.name)
        default:
            break
        }
    }
}

/// Nom lisible de l'appareil pour le service Bonjour.
enum UIDeviceName {
    @MainActor static var current: String { "3dUiCar iPad" }
}

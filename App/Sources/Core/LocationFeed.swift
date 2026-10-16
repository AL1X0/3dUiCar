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

    @ObservationIgnored private var lastPhoneFix: Date?

    /// Position iPad : ignorée tant que l'iPhone fournit un flux récent.
    func updateFromDevice(_ loc: CLLocation) {
        if let last = lastPhoneFix, Date().timeIntervalSince(last) < 5 { return }
        location = loc
        source = .device
    }

    func updateFromPhone(_ loc: CLLocation) {
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

    private let feed: LocationFeed
    private let vehicle: VehicleState
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    init(feed: LocationFeed, vehicle: VehicleState) {
        self.feed = feed
        self.vehicle = vehicle
    }

    func start() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .udp)
            l.service = NWListener.Service(name: UIDeviceName.current, type: Self.serviceType)
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.stateUpdateHandler = { state in
                if case .failed(let error) = state { print("Bonjour : \(error)") }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            print("NWListener : \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ conn: NWConnection) {
        connections.append(conn)
        conn.start(queue: .main)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.handle(data) }
                if error == nil { self.receive(on: conn) }
            }
        }
    }

    private struct Message: Decodable {
        let v: Int
        let type: String
        let t: Double
        let lat, lon, alt, hAcc, speed, sAcc, course, cAcc: Double?
        let name: String?
    }

    private func handle(_ data: Data) {
        guard let m = try? JSONDecoder().decode(Message.self, from: data) else { return }
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
            vehicle.locationSource = .phone
            if let speed = m.speed, speed >= 0, !vehicle.obdConnected {
                vehicle.speedKmh = speed * 3.6
                vehicle.speedSource = .phone
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

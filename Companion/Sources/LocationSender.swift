import CoreLocation
import Foundation
import Network
import Observation
import UIKit

@MainActor
@Observable
final class LocationSender: NSObject, CLLocationManagerDelegate {
    // MARK: - Observable UI State

    var isRunning: Bool = false
    var ipadName: String? = nil
    var isConnected: Bool = false
    var lastLocation: CLLocation? = nil
    var sentCount: Int = 0
    var authorization: CLAuthorizationStatus

    // MARK: - Internal Dependencies

    @ObservationIgnored
    private let locationManager: CLLocationManager

    @ObservationIgnored
    private var browser: NWBrowser?

    @ObservationIgnored
    private var connection: NWConnection?

    @ObservationIgnored
    private var heartbeatTimer: Timer?

    @ObservationIgnored
    private var currentResults: Set<NWBrowser.Result> = []

    // MARK: - Initialization

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager
        self.authorization = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    deinit {
        heartbeatTimer?.invalidate()
        browser?.cancel()
        connection?.cancel()
    }

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }
        isRunning = true

        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()

        startBrowser()
        startHeartbeatTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        locationManager.stopUpdatingLocation()
        stopHeartbeatTimer()
        stopBrowser()
        dropConnection()
    }

    // MARK: - Networking (Bonjour Discovery & Connection)

    private func startBrowser() {
        stopBrowser()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_car3dui._udp", domain: nil)
        let parameters = NWParameters.udp
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }

        newBrowser.start(queue: .main)
        self.browser = newBrowser
    }

    private func stopBrowser() {
        browser?.cancel()
        browser = nil
        currentResults.removeAll()
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        currentResults = results
        checkAndConnect()
    }

    private func checkAndConnect() {
        guard connection == nil else { return }

        for result in currentResults {
            if case let .service(name, _, _, _) = result.endpoint {
                ipadName = name
                connect(to: result.endpoint)
                break
            }
        }
    }

    private func connect(to endpoint: NWEndpoint) {
        let newConnection = NWConnection(to: endpoint, using: .udp)
        self.connection = newConnection

        newConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionStateChange(state)
            }
        }

        newConnection.start(queue: .main)
    }

    private func handleConnectionStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
        case .failed, .cancelled:
            dropConnection()
            if isRunning {
                checkAndConnect()
            }
        case .waiting, .preparing, .setup:
            isConnected = false
        @unknown default:
            isConnected = false
        }
    }

    private func dropConnection() {
        isConnected = false
        ipadName = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: - Data Sending

    private func sendLocation(_ location: CLLocation) {
        guard let connection, isConnected else { return }

        let payload: [String: Any] = [
            "v": 1,
            "type": "location",
            "t": location.timestamp.timeIntervalSince1970,
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "alt": location.altitude,
            "hAcc": location.horizontalAccuracy,
            "speed": location.speed,
            "sAcc": location.speedAccuracy,
            "course": location.course,
            "cAcc": location.courseAccuracy
        ]

        sendJSONPayload(payload, via: connection)
    }

    private func sendHeartbeat() {
        guard let connection, isConnected else { return }

        let payload: [String: Any] = [
            "v": 1,
            "type": "heartbeat",
            "t": Date().timeIntervalSince1970,
            "name": UIDevice.current.name
        ]

        sendJSONPayload(payload, via: connection)
    }

    private func sendJSONPayload(_ payload: [String: Any], via connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error == nil {
                Task { @MainActor in
                    self?.sentCount += 1
                }
            }
        })
    }

    // MARK: - Heartbeat Timer

    private func startHeartbeatTimer() {
        stopHeartbeatTimer()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Location Handling

    private func handleLocationUpdate(_ location: CLLocation) {
        lastLocation = location
        sendLocation(location)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.handleLocationUpdate(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // CoreLocation errors handled gracefully; updates continue automatically when signal recovers
    }
}
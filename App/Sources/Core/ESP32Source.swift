import CoreBluetooth
import Foundation
import Observation

/// Module OBD ESP32 en Bluetooth LE (docs/protocols.md §2) → `VehicleState`.
@MainActor
@Observable
final class ESP32Source: NSObject {
    enum State: Equatable { case off, scanning, connecting, connected, unavailable }

    static let service = CBUUID(string: "6E3D0001-8C3B-4E4B-9A1F-3D5543415200")
    static let signalsChar = CBUUID(string: "6E3D0002-8C3B-4E4B-9A1F-3D5543415200")
    static let commandChar = CBUUID(string: "6E3D0003-8C3B-4E4B-9A1F-3D5543415200")
    static let rawChar = CBUUID(string: "6E3D0004-8C3B-4E4B-9A1F-3D5543415200")
    static let infoChar = CBUUID(string: "6E3D0005-8C3B-4E4B-9A1F-3D5543415200")
    static let dtcChar = CBUUID(string: "6E3D0006-8C3B-4E4B-9A1F-3D5543415200")

    private(set) var state: State = .off
    private(set) var firmwareInfo = ""
    private(set) var dtcCodes: [String]?
    private(set) var recording = false
    private(set) var recordedFrames = 0
    private(set) var lastRecordingURL: URL?

    /// Rapport engagé (boîte manuelle 6), déduit du rapport vitesse / régime.
    private(set) var manualGear: Int?

    @ObservationIgnored private let vehicle: VehicleState
    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var command: CBCharacteristic?
    @ObservationIgnored private var recorder: FileHandle?
    @ObservationIgnored private var wanted = false

    init(vehicle: VehicleState) {
        self.vehicle = vehicle
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        wanted = true
        scanIfPossible()
    }

    func stop() {
        wanted = false
        central.stopScan()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        state = .off
    }

    private func scanIfPossible() {
        guard wanted, central.state == .poweredOn, peripheral == nil else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.service])
    }

    // MARK: - Commandes

    func readDTC() { send([0x01]) }
    func clearDTC() { send([0x02]); dtcCodes = nil }

    /// Enregistre les trames CAN brutes dans Documents/can-<date>.csv (bus 0 = HS, 1 = MS).
    func setRecording(_ on: Bool, bus: UInt8 = 0) {
        if on {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("can-\(f.string(from: Date())).csv")
            FileManager.default.createFile(atPath: url.path, contents: Data("ts_ms,id,ext,dlc,data\n".utf8))
            recorder = try? FileHandle(forWritingTo: url)
            recorder?.seekToEndOfFile()
            lastRecordingURL = url
            recordedFrames = 0
            send([0x11, bus])
        } else {
            try? recorder?.close()
            recorder = nil
        }
        recording = on
        send([0x10, on ? 1 : 0])
    }

    private func send(_ bytes: [UInt8]) {
        guard let peripheral, let command else { return }
        peripheral.writeValue(Data(bytes), for: command, type: .withResponse)
    }

    // MARK: - Décodage

    private func decodeSignals(_ data: Data) {
        let b = [UInt8](data)
        guard let n = b.first, b.count >= 1 + Int(n) * 5 else { return }
        for i in 0..<Int(n) {
            let o = 1 + i * 5
            let raw = UInt32(b[o + 1]) | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3]) << 16 | UInt32(b[o + 4]) << 24
            apply(id: b[o], value: Double(Float(bitPattern: raw)))
        }
        updateManualGear()
    }

    private func apply(id: UInt8, value v: Double) {
        let on = v >= 0.5
        switch id {
        case 0x01: vehicle.rpm = v
        case 0x02:
            vehicle.speedKmh = v
            vehicle.speedSource = .obd
        case 0x03: vehicle.coolantTempC = v
        case 0x07: vehicle.fuelLevel = max(0, min(1, v / 100))
        case 0x20: vehicle.blinkerLeft = on
        case 0x21: vehicle.blinkerRight = on
        case 0x22: vehicle.lowBeam = on
        case 0x23: vehicle.highBeam = on
        case 0x24: vehicle.braking = on
        case 0x25: if on { vehicle.gear = .reverse }
        case 0x26: vehicle.doorFLOpen = on
        case 0x27: vehicle.doorFROpen = on
        case 0x28: vehicle.trunkOpen = on
        case 0x29: vehicle.hoodOpen = on
        case 0x2A: vehicle.seatbeltUnfastened = on
        case 0x2B: if on, vehicle.speedKmh < 1 { vehicle.gear = .park }
        default: break
        }
    }

    /// Fiesta ST (1.5 EcoBoost, BV6) : km/h pour 1000 tr/min sur chaque rapport (approx.).
    private static let kmhPer1000 = [8.0, 13.6, 19.7, 25.5, 31.4, 37.5]

    private func updateManualGear() {
        guard let rpm = vehicle.rpm, rpm > 900, vehicle.speedKmh > 5 else {
            manualGear = nil
            if vehicle.gear != .reverse, vehicle.speedKmh < 1 { vehicle.gear = .park }
            return
        }
        let ratio = vehicle.speedKmh / rpm * 1000
        let best = Self.kmhPer1000.enumerated().min { abs($0.element - ratio) < abs($1.element - ratio) }
        manualGear = best.map { $0.offset + 1 }
        if vehicle.gear != .reverse { vehicle.gear = .drive }
    }

    private func decodeRaw(_ data: Data) {
        guard let recorder else { return }
        let b = [UInt8](data)
        guard let n = b.first, b.count >= 1 + Int(n) * 17 else { return }
        var out = ""
        for i in 0..<Int(n) {
            let o = 1 + i * 17
            let ts = UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
            let rawID = UInt32(b[o + 4]) | UInt32(b[o + 5]) << 8 | UInt32(b[o + 6]) << 16 | UInt32(b[o + 7]) << 24
            let dlc = Int(min(8, b[o + 8]))
            let payload = b[(o + 9)..<(o + 9 + dlc)].map { String(format: "%02X", $0) }.joined(separator: " ")
            let ext = rawID & 0x8000_0000 != 0
            out += "\(ts),\(String(format: "%X", rawID & 0x1FFF_FFFF)),\(ext ? 1 : 0),\(dlc),\(payload)\n"
        }
        recorder.write(Data(out.utf8))
        recordedFrames += Int(n)
    }
}

// MARK: - CoreBluetooth

extension ESP32Source: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn { scanIfPossible() }
            else if central.state == .unauthorized || central.state == .unsupported { state = .unavailable }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard self.peripheral == nil else { return }
            self.peripheral = peripheral
            peripheral.delegate = self
            state = .connecting
            central.stopScan()
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { reset() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { reset() }
    }

    private func reset() {
        peripheral = nil
        command = nil
        vehicle.obdConnected = false
        vehicle.rpm = nil
        manualGear = nil
        state = wanted ? .scanning : .off
        scanIfPossible()
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
            peripheral.discoverCharacteristics(
                [Self.signalsChar, Self.commandChar, Self.rawChar, Self.infoChar, Self.dtcChar], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                switch c.uuid {
                case Self.commandChar: command = c
                case Self.infoChar: peripheral.readValue(for: c)
                case Self.signalsChar, Self.rawChar, Self.dtcChar: peripheral.setNotifyValue(true, for: c)
                default: break
                }
            }
            state = .connected
            vehicle.obdConnected = true
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        MainActor.assumeIsolated {
            switch uuid {
            case Self.signalsChar: decodeSignals(data)
            case Self.rawChar: decodeRaw(data)
            case Self.infoChar: firmwareInfo = String(decoding: data, as: UTF8.self)
            case Self.dtcChar:
                let s = String(decoding: data, as: UTF8.self)
                dtcCodes = s.isEmpty ? [] : s.split(separator: ",").map(String.init)
            default: break
            }
        }
    }
}

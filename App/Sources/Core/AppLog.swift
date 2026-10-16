import Foundation
import Observation
import OSLog
import UIKit

/// Journal de l'app : console (os.Logger), fichier (Documents/Logs) et tampon en mémoire
/// affiché dans Réglages › Journal. Partageable pour les remontées de bugs.
///
/// Usage : `Log.info(.spotify, "connecté")`, `Log.error(.gps, "…")`.
enum LogCategory: String, CaseIterable, Sendable {
    case app, ui, scene3D = "3d", sensors, gps, companion, nav, spotify, obd, weather, perf
}

enum LogLevel: Int, Comparable, Sendable {
    case debug, info, warning, error
    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    var tag: String { ["DBG", "INF", "WRN", "ERR"][rawValue] }
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let category: LogCategory
    let message: String

    var line: String {
        "\(Log.timestamp.string(from: date)) [\(level.tag)] [\(category.rawValue)] \(message)"
    }
}

enum Log {
    static func debug(_ c: LogCategory, _ m: @autoclosure () -> String) { write(.debug, c, m()) }
    static func info(_ c: LogCategory, _ m: @autoclosure () -> String) { write(.info, c, m()) }
    static func warning(_ c: LogCategory, _ m: @autoclosure () -> String) { write(.warning, c, m()) }
    static func error(_ c: LogCategory, _ m: @autoclosure () -> String) { write(.error, c, m()) }

    static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static let queue = DispatchQueue(label: "app.log", qos: .utility)
    private static let loggers: [LogCategory: Logger] = Dictionary(uniqueKeysWithValues:
        LogCategory.allCases.map { ($0, Logger(subsystem: "com.al1x0.car3dui", category: $0.rawValue)) })

    static func write(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        let entry = LogEntry(date: Date(), level: level, category: category, message: message)
        let osLogger = loggers[category]
        switch level {
        case .debug: osLogger?.debug("\(message, privacy: .public)")
        case .info: osLogger?.info("\(message, privacy: .public)")
        case .warning: osLogger?.warning("\(message, privacy: .public)")
        case .error: osLogger?.error("\(message, privacy: .public)")
        }
        queue.async { LogFile.shared.append(entry.line) }
        Task { @MainActor in LogStore.shared.append(entry) }
    }
}

/// Fichier journal du jour, rotation : 7 fichiers conservés.
final class LogFile: @unchecked Sendable {
    static let shared = LogFile()

    let directory: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private var handle: FileHandle?
    private var currentDay = ""

    var currentURL: URL { directory.appendingPathComponent("app-\(Self.day()).log") }

    private static func day() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Appelé uniquement depuis la file de Log.
    func append(_ line: String) {
        let today = Self.day()
        if today != currentDay || handle == nil {
            try? handle?.close()
            currentDay = today
            let url = currentURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                prune()
            }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        handle?.write(Data((line + "\n").utf8))
    }

    private func prune() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files.filter({ $0.pathExtension == "log" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(7) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Rapport complet à partager : infos appareil + journaux des derniers jours.
    func exportReport(header: String) -> URL {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var text = header + "\n\n"
        for f in files.suffix(3) {
            text += "===== \(f.lastPathComponent) =====\n"
            text += (try? String(contentsOf: f, encoding: .utf8)) ?? ""
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("3dUiCar-logs-\(Self.day()).txt")
        try? text.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    func clear() {
        try? handle?.close()
        handle = nil
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

/// Tampon mémoire observé par la page Journal (1 500 dernières lignes).
@MainActor
@Observable
final class LogStore {
    static let shared = LogStore()
    private(set) var entries: [LogEntry] = []

    func append(_ e: LogEntry) {
        entries.append(e)
        if entries.count > 1500 { entries.removeFirst(entries.count - 1500) }
    }

    func clear() {
        entries.removeAll()
        Log.queueClear()
    }
}

extension Log {
    static func queueClear() {
        queue.async { LogFile.shared.clear() }
    }

    /// En-tête du rapport : version, appareil, état.
    @MainActor static func deviceHeader() -> String {
        let info = Bundle.main.infoDictionary
        let d = UIDevice.current
        return """
        3dUiCar \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))
        \(d.model) · \(d.systemName) \(d.systemVersion) · \(Self.hardwareModel())
        Mémoire : \(memoryMB()) Mo · Thermique : \(ProcessInfo.processInfo.thermalState.label)
        Généré le \(Date().formatted(date: .abbreviated, time: .standard))
        """
    }

    static func hardwareModel() -> String {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// Mémoire utilisée (Mo).
    static func memoryMB() -> UInt64 {
        var vmInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let ok = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return ok == KERN_SUCCESS ? vmInfo.phys_footprint / 1_048_576 : 0
    }

    /// À appeler au lancement : signale si la session précédente s'est arrêtée brutalement.
    static func startSession() {
        let key = "Log.sessionRunning"
        if UserDefaults.standard.bool(forKey: key) {
            warning(.app, "La session précédente s'est terminée brutalement (crash, arrêt système ou mémoire).")
        }
        UserDefaults.standard.set(true, forKey: key)
        NSSetUncaughtExceptionHandler { exc in
            let line = "\(Log.timestamp.string(from: Date())) [ERR] [app] Exception : \(exc.name.rawValue) \(exc.reason ?? "") \(exc.callStackSymbols.prefix(15).joined(separator: " | "))"
            LogFile.shared.append(line)
        }
        info(.app, "Démarrage · \(hardwareModel()) · iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }

    /// Fin propre (passage en arrière-plan).
    static func markCleanExit() { UserDefaults.standard.set(false, forKey: "Log.sessionRunning") }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "normal"
        case .fair: "tiède"
        case .serious: "chaud"
        case .critical: "critique"
        @unknown default: "?"
        }
    }
}

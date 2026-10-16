import Foundation
import Observation

enum Appearance: String, CaseIterable, Sendable { case auto, light, dark }
enum HeadlightMode: String, CaseIterable, Sendable { case off, parking, on, auto }
enum DomeLightMode: String, CaseIterable, Sendable { case off, on, auto }
enum TurnSignalMode: String, CaseIterable, Sendable { case off, autoCancel }
enum DriveMode: String, CaseIterable, Sendable { case normal, sport, track }
enum SteeringMode: String, CaseIterable, Sendable { case comfort, standard, sport }
enum CarFinish: String, CaseIterable, Sendable { case paint, clay }

/// Sections du panneau Réglages (ordre de l'arbre de navigation du Figma).
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case search, controls, pedals, fuel, assist, locks, lights, display,
         trips, navigation, safety, service, software, upgrades

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "Rechercher"
        case .controls: "Commandes"
        case .pedals: "Pédales et direction"
        case .fuel: "Carburant"
        case .assist: "Aides à la conduite"
        case .locks: "Verrous"
        case .lights: "Éclairage"
        case .display: "Affichage"
        case .trips: "Trajets"
        case .navigation: "Navigation"
        case .safety: "Sécurité"
        case .service: "Entretien"
        case .software: "Logiciel"
        case .upgrades: "Mises à niveau"
        }
    }

    /// Icône Figma (Assets.xcassets/Icons, gabarit).
    var icon: String {
        switch self {
        case .search: "nav.search"
        case .controls: "nav.controls"
        case .pedals: "nav.model3"
        case .fuel: "nav.power"
        case .assist: "nav.steering"
        case .locks: "nav.lock"
        case .lights: "nav.lights"
        case .display: "nav.display"
        case .trips: "nav.trip"
        case .navigation: "nav.navigation"
        case .safety: "nav.security"
        case .service: "nav.service"
        case .software: "nav.software"
        case .upgrades: "nav.shop"
        }
    }
}

/// Réglages de l'app, persistés dans UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var appearance: Appearance = .auto { didSet { save() } }
    var headlightMode: HeadlightMode = .auto { didSet { save() } }
    var autoHighBeam = true { didSet { save() } }
    var headlightsAfterExit = false { didSet { save() } }
    var domeLights: DomeLightMode = .auto { didSet { save() } }
    var turnSignals: TurnSignalMode = .autoCancel { didSet { save() } }
    var wiperSpeed = 5 { didSet { save() } }          // 0 = off, 1...4, 5 = auto
    var brightness = 0.8 { didSet { save() } }
    var brightnessAuto = true { didSet { save() } }
    var largeText = false { didSet { save() } }
    var driveMode: DriveMode = .normal { didSet { save() } }
    var steeringMode: SteeringMode = .standard { didSet { save() } }
    var showLanes = true { didSet { save() } }
    var carFinish: CarFinish = .paint { didSet { save() } }
    var dashcamRecording = false { didSet { save() } }
    var mirrorsFolded = false { didSet { save() } }
    var childLock = false { didSet { save() } }
    var walkAwayLock = true { didSet { save() } }
    var unlockOnPark = true { didSet { save() } }
    var speedLimitWarning = true { didSet { save() } }
    var voiceGuidance = true { didSet { save() } }
    var avoidTolls = false { didSet { save() } }
    var avoidHighways = false { didSet { save() } }
    var demoMode = true { didSet { save() } }

    var selectedSection: SettingsSection = .controls
    var settingsOpen = false

    private let key = "AppSettings.v1"
    private var loading = false

    init() { load() }

    private var snapshot: [String: Any] {
        [
            "appearance": appearance.rawValue, "headlightMode": headlightMode.rawValue,
            "autoHighBeam": autoHighBeam, "headlightsAfterExit": headlightsAfterExit,
            "domeLights": domeLights.rawValue, "turnSignals": turnSignals.rawValue,
            "wiperSpeed": wiperSpeed, "brightness": brightness, "brightnessAuto": brightnessAuto,
            "largeText": largeText, "driveMode": driveMode.rawValue, "steeringMode": steeringMode.rawValue,
            "showLanes": showLanes, "carFinish": carFinish.rawValue, "dashcamRecording": dashcamRecording,
            "mirrorsFolded": mirrorsFolded, "childLock": childLock, "walkAwayLock": walkAwayLock,
            "unlockOnPark": unlockOnPark, "speedLimitWarning": speedLimitWarning,
            "voiceGuidance": voiceGuidance, "avoidTolls": avoidTolls, "avoidHighways": avoidHighways,
            "demoMode": demoMode,
        ]
    }

    private func save() {
        guard !loading else { return }
        UserDefaults.standard.set(snapshot, forKey: key)
    }

    private func load() {
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return }
        loading = true
        defer { loading = false }
        if let v = d["appearance"] as? String, let e = Appearance(rawValue: v) { appearance = e }
        if let v = d["headlightMode"] as? String, let e = HeadlightMode(rawValue: v) { headlightMode = e }
        if let v = d["domeLights"] as? String, let e = DomeLightMode(rawValue: v) { domeLights = e }
        if let v = d["turnSignals"] as? String, let e = TurnSignalMode(rawValue: v) { turnSignals = e }
        if let v = d["driveMode"] as? String, let e = DriveMode(rawValue: v) { driveMode = e }
        if let v = d["steeringMode"] as? String, let e = SteeringMode(rawValue: v) { steeringMode = e }
        if let v = d["carFinish"] as? String, let e = CarFinish(rawValue: v) { carFinish = e }
        autoHighBeam = d["autoHighBeam"] as? Bool ?? autoHighBeam
        headlightsAfterExit = d["headlightsAfterExit"] as? Bool ?? headlightsAfterExit
        wiperSpeed = d["wiperSpeed"] as? Int ?? wiperSpeed
        brightness = d["brightness"] as? Double ?? brightness
        brightnessAuto = d["brightnessAuto"] as? Bool ?? brightnessAuto
        largeText = d["largeText"] as? Bool ?? largeText
        showLanes = d["showLanes"] as? Bool ?? showLanes
        dashcamRecording = d["dashcamRecording"] as? Bool ?? dashcamRecording
        mirrorsFolded = d["mirrorsFolded"] as? Bool ?? mirrorsFolded
        childLock = d["childLock"] as? Bool ?? childLock
        walkAwayLock = d["walkAwayLock"] as? Bool ?? walkAwayLock
        unlockOnPark = d["unlockOnPark"] as? Bool ?? unlockOnPark
        speedLimitWarning = d["speedLimitWarning"] as? Bool ?? speedLimitWarning
        voiceGuidance = d["voiceGuidance"] as? Bool ?? voiceGuidance
        avoidTolls = d["avoidTolls"] as? Bool ?? avoidTolls
        avoidHighways = d["avoidHighways"] as? Bool ?? avoidHighways
        demoMode = d["demoMode"] as? Bool ?? demoMode
    }
}

import Foundation
import Observation

enum Appearance: String, CaseIterable, Sendable { case auto, light, dark }
enum CarFinish: String, CaseIterable, Sendable { case paint, clay }

/// Sections du panneau Réglages : uniquement des fonctions qui agissent réellement.
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case search, controls, display, navigation, music, trips, engine, sensors, service, software

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "Rechercher"
        case .controls: "Commandes"
        case .display: "Affichage"
        case .navigation: "Navigation"
        case .music: "Musique"
        case .trips: "Trajets"
        case .engine: "Moteur"
        case .sensors: "Capteurs"
        case .service: "Module OBD"
        case .software: "Logiciel"
        }
    }

    /// Icône Figma (Assets.xcassets/Icons, gabarit).
    var icon: String {
        switch self {
        case .search: "nav.search"
        case .controls: "nav.controls"
        case .display: "nav.display"
        case .navigation: "nav.navigation"
        case .music: "app.music"
        case .trips: "nav.trip"
        case .engine: "nav.power"
        case .sensors: "nav.steering"
        case .service: "nav.service"
        case .software: "nav.software"
        }
    }
}

/// Réglages de l'app, persistés dans UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var appearance: Appearance = .auto { didSet { save() } }
    var brightness = 0.8 { didSet { save() } }
    var brightnessAuto = true { didSet { save() } }
    var largeText = false { didSet { save() } }
    var showLanes = true { didSet { save() } }
    var carFinish: CarFinish = .paint { didSet { save() } }
    var voiceGuidance = true { didSet { save() } }
    var avoidTolls = false { didSet { save() } }
    var avoidHighways = false { didSet { save() } }
    var demoMode = true { didSet { save() } }
    /// Largeur du panneau voiture (fraction de l'écran), réglée en glissant le séparateur.
    var carPanelRatio = 0.33 { didSet { save() } }

    // État d'interface (non persisté)
    var selectedSection: SettingsSection = .controls
    var settingsOpen = false
    var mediaHidden = false
    var libraryOpen = false

    static let carPanelRange = 0.2...0.7

    private let key = "AppSettings.v2"
    private var loading = false

    init() { load() }

    private func save() {
        guard !loading else { return }
        UserDefaults.standard.set([
            "appearance": appearance.rawValue, "brightness": brightness, "brightnessAuto": brightnessAuto,
            "largeText": largeText, "showLanes": showLanes, "carFinish": carFinish.rawValue,
            "voiceGuidance": voiceGuidance, "avoidTolls": avoidTolls, "avoidHighways": avoidHighways,
            "demoMode": demoMode, "carPanelRatio": carPanelRatio,
        ] as [String: Any], forKey: key)
    }

    private func load() {
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return }
        loading = true
        defer { loading = false }
        if let v = d["appearance"] as? String, let e = Appearance(rawValue: v) { appearance = e }
        if let v = d["carFinish"] as? String, let e = CarFinish(rawValue: v) { carFinish = e }
        brightness = d["brightness"] as? Double ?? brightness
        brightnessAuto = d["brightnessAuto"] as? Bool ?? brightnessAuto
        largeText = d["largeText"] as? Bool ?? largeText
        showLanes = d["showLanes"] as? Bool ?? showLanes
        voiceGuidance = d["voiceGuidance"] as? Bool ?? voiceGuidance
        avoidTolls = d["avoidTolls"] as? Bool ?? avoidTolls
        avoidHighways = d["avoidHighways"] as? Bool ?? avoidHighways
        demoMode = d["demoMode"] as? Bool ?? demoMode
        carPanelRatio = (d["carPanelRatio"] as? Double).map { min(max($0, Self.carPanelRange.lowerBound), Self.carPanelRange.upperBound) } ?? carPanelRatio
    }
}

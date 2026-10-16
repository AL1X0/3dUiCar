import SwiftUI
import CoreText

// Tokens issus de la librairie Figma « Tesla Dashboard UI Component Library ».

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Theme {
    static let accent = Color(hex: 0x005AFF)      // func/blue dark
    static let teal = Color(hex: 0x2FCCBB)
    static let telltaleGreen = Color(hex: 0x1DB954)
    static let telltaleBlue = Color(hex: 0x2F6BFF)
    static let warningRed = Color(hex: 0xE82127)
    static let blinkerGreen = Color(hex: 0x2ECC40)

    static let dockHeight: CGFloat = 72
    static let leftPanelRatio: CGFloat = 0.33
    static let cornerRadius: CGFloat = 8
    static let minTouch: CGFloat = 60
}

/// Couleurs dépendantes du mode clair / sombre (les deux existent dans le Figma).
struct Palette: Sendable {
    var background: Color      // fond panneau gauche
    var panel: Color           // panneaux superposés (réglages, cartes)
    var panelSecondary: Color  // tuiles, onglets inactifs
    var textPrimary: Color
    var textSecondary: Color
    var inactive: Color
    var outline: Color
    var dock: Color
    var dockText: Color

    static let light = Palette(
        background: Color(hex: 0xF7F7F7),
        panel: Color(hex: 0xF0F0F0),
        panelSecondary: Color(hex: 0xE0E0E0),
        textPrimary: Color(hex: 0x171717),
        textSecondary: Color(hex: 0x757575),
        inactive: Color(hex: 0xA2A3A5),
        outline: Color(hex: 0xD0D1D2),
        dock: Color(hex: 0x0A0A0A),
        dockText: Color(hex: 0xE0E0E0)
    )

    static let dark = Palette(
        background: Color(hex: 0x2B2B2B),
        panel: Color(hex: 0x414141),
        panelSecondary: Color(hex: 0x4D4D4D),
        textPrimary: Color(hex: 0xFFFFFF),
        textSecondary: Color(hex: 0xA2A3A5),
        inactive: Color(hex: 0x757575),
        outline: Color(hex: 0x5A5A5A),
        dock: Color(hex: 0x000000),
        dockText: Color(hex: 0xE0E0E0)
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Typo Figma : Inter (Medium 14/18, SemiBold 18–28, Bold 24), embarquée dans Resources/Fonts.
enum TeslaFont {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name = switch weight {
        case .bold, .heavy, .black: "Inter-Bold"
        case .semibold: "Inter-SemiBold"
        case .medium: "Inter-Medium"
        default: "Inter-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }
    static let speed = ui(72, .regular)
    static let caption = ui(12, .semibold)

    /// Enregistre les TTF du bundle (évite de dépendre de UIAppFonts dans l'Info.plist).
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

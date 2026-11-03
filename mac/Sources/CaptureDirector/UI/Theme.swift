import AppKit
import Observation
import SwiftUI

/// One accent color in four shades. Everything else is Apple's look.
/// Capture Director ships with one accent, mulberry; there is no picker.
/// Light and dark mode follow the Mac.
///   APP_ACCENT=system CaptureDirector     run with another accent, to compare
struct Theme: Identifiable, Hashable {
    struct Shades: Hashable {
        /// Accent text and symbols in dark mode.
        let light: UInt32
        /// Fills and tint in light mode.
        let base: UInt32
        /// Fills and tint in dark mode: lighter, so it stands off a dark window.
        let darkBase: UInt32
        /// Accent text and symbols in light mode.
        let deep: UInt32
    }

    let id: String
    let name: String
    /// nil follows the accent color in System Settings.
    let shades: Shades?
    /// Text on the accent: white, or dark ink for bright accents like yellow.
    var darkText = false

    /// For `.tint`. nil keeps the system accent.
    var tint: Color? { shades.map { Color(light: $0.base, dark: $0.darkBase) } }
    /// The flat accent color.
    var accent: Color { tint ?? .accentColor }
    /// Accent-colored text and symbols on a plain or tinted background: the
    /// deep shade in light mode, the light shade in dark mode, so both read.
    var accentText: Color { shades.map { Color(light: $0.deep, dark: $0.light) } ?? .accentColor }
    /// Text and symbols on an accent fill.
    var onAccent: Color { darkText ? Color(hex: 0x16161C) : .white }

    /// Mulberry #4c1637 from the brand. In dark mode the fill lifts to #b04a80
    /// (3.3:1 against a dark window, 5.1:1 under white text) and accent text to
    /// #e39bc0 (7.7:1).
    static let mulberry = Theme(id: "mulberry", name: "Mulberry",
                                shades: .init(light: 0xE39BC0, base: 0x4C1637, darkBase: 0xB04A80, deep: 0x4C1637))

    static let all: [Theme] = [
        mulberry,
        Theme(id: "system", name: "System", shades: nil),
    ]
}

/// The accent in use: mulberry, or APP_ACCENT for a comparison snapshot.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    static let defaultID = "mulberry"

    let themeID: String

    var theme: Theme { Theme.all.first { $0.id == themeID } ?? Theme.mulberry }

    private init() {
        themeID = ProcessInfo.processInfo.environment["APP_ACCENT"] ?? Self.defaultID
    }
}

/// Accent tokens for views. Never hard-code an accent hex in a view.
enum Palette {
    static var accent: Color { ThemeStore.shared.theme.accent }
    static var accentText: Color { ThemeStore.shared.theme.accentText }
    static var onAccent: Color { ThemeStore.shared.theme.onAccent }

    /// Citron, the Final badge. Always with `onFinal` text.
    static let final = Color(hex: 0xE5D935)
    /// Dark ink on citron (12:1).
    static let onFinal = Color(hex: 0x16161C)
    /// Pool, for quiet highlights like a hovered card. A deep pool in dark mode.
    static let highlight = Color(light: 0xD4E9ED, dark: 0x1F3A40, highContrastLight: 0xB9DCE3, highContrastDark: 0x2A5058)
    /// Behind text and badges that sit on video frames.
    static let scrim = Color.black.opacity(0.6)
    /// On the scrim.
    static let onScrim = Color.white
    /// The empty frame where a thumbnail goes.
    static let placeholder = Color(light: 0xE7E3E6, dark: 0x2C282B)
}

/// Corner radii. Inner corners are concentric: inner = outer - inset.
enum Radius {
    /// Badges and small capsules.
    static let xs: CGFloat = 6
    /// Banners and controls.
    static let sm: CGFloat = 8
    /// Thumbnails.
    static let md: CGFloat = 12
    /// A card with its selection fill: thumbnail radius plus the 4 pt inset.
    static let card: CGFloat = 16
}

/// Durations, so Reduce Motion and timing change in one place.
enum Motion {
    static let hover = Animation.easeOut(duration: 0.12)
}

/// How long typing pauses before a field saves itself.
enum Pause {
    static let notes: Duration = .milliseconds(600)
}

extension View {
    /// Applies the chosen accent to everything below. Put it on every scene's root.
    func themed() -> some View {
        modifier(Themed())
    }
}

private struct Themed: ViewModifier {
    private var store = ThemeStore.shared

    func body(content: Content) -> some View {
        content.tint(store.theme.tint)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A color with a light and a dark value: Color(light: 0x0064D2, dark: 0x7CC0FF).
    /// Add the two high-contrast values for Increase Contrast; they default
    /// to the normal ones.
    init(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                               .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: NSColor(hex: dark)
            case .accessibilityHighContrastAqua: NSColor(hex: highContrastLight ?? light)
            case .accessibilityHighContrastDarkAqua: NSColor(hex: highContrastDark ?? dark)
            default: NSColor(hex: light)
            }
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

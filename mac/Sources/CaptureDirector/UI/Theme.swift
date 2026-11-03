import AppKit
import SwiftUI

/// Colors for views. Never hard-code a hex in a view.
///
/// Controls, selection, and focus use the Mac's own accent color. The app is
/// built with Command Line Tools, which can't compile an asset-catalog accent,
/// and without one AppKit draws the sidebar selection and its icons in the
/// system accent whatever SwiftUI's `.tint` says. A custom tint would mix two
/// accents in one window, so there is none. A committed Xcode-built
/// `Assets.car` with `NSAccentColorName` could bring mulberry back later.
///
/// The brand colors stay fixed and mark brand things only: mulberry for the
/// star, citron for the Final badge, and pool for quiet highlights.
enum Palette {
    /// The system accent, for selection rings and drop targets.
    static let accent = Color.accentColor

    /// Mulberry #4C1637 from the brand, for the star. In dark mode it lifts to
    /// #B04A80 (3.3:1 against a dark window) so the symbol still stands out.
    static let star = Color(light: 0x4C1637, dark: 0xB04A80)
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

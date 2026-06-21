import SwiftUI

// Design tokens for matching the Cursor desktop app look.
// Values are extracted from Cursor's default dark theme ("Cursor Dark Anysphere")
// and its workbench font stacks. See cursor_operator/design.md for the rationale.

extension Color {
    /// Builds a Color from a 0xRRGGBB integer, with optional opacity.
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Cursor-like color and radius tokens.
public enum CursorTheme {
    // Base overlay color — almost every text shade, border, hover, and
    // selection is this near-white painted at a low alpha over the dark bg.
    static let base = Color(hex: 0xE4E4E4)

    // Opaque backgrounds (note: chrome is DARKER than the content canvas).
    public static let bgContent = Color(hex: 0x181818) // main canvas
    public static let bgChrome = Color(hex: 0x141414) // sidebar / panels / popovers

    // base @ alpha
    public static let textPrimary = base.opacity(0.92)
    public static let textSecondary = base.opacity(0.55)
    public static let textPlaceholder = base.opacity(0.37)
    public static let surfaceWash = base.opacity(0.04) // input / card fill
    public static let borderSubtle = base.opacity(0.07)
    public static let selectHover = base.opacity(0.07)
    public static let selectActive = base.opacity(0.12)
    public static let borderFocus = base.opacity(0.15)

    // Accents
    public static let blue = Color(hex: 0x81A1C1) // primary button, links, paths
    public static let blueHover = Color(hex: 0x87A6C4)
    public static let onAccent = Color(hex: 0x191C22) // text on blue
    public static let cyan = Color(hex: 0x88C0D0) // badges
    public static let green = Color(hex: 0x3FA266) // toggle on / success
    public static let orange = Color(hex: 0xF1B467) // warnings / slash commands
    public static let orangeDeep = Color(hex: 0xD2943E)
    public static let danger = Color(hex: 0xE34671) // errors (pink-red)
    public static let btnSecondary = Color(hex: 0x626262) // solid neutral button

    // Radii (use Capsule() for `full` — pills, toggles).
    public static let radiusSM: CGFloat = 6
    public static let radiusMD: CGFloat = 8
    public static let radiusLG: CGFloat = 10
    public static let radiusXL: CGFloat = 12
}

// Type roles — system font (= SF Pro, what Cursor actually uses) for UI.
// Code uses a monospaced face; JetBrains Mono is Cursor's bundled mono, but it
// is not yet bundled here, so fall back to the system monospaced design.
public extension Font {
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    static let sectionLabel = Font.system(size: 12, weight: .medium)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let body13 = Font.system(size: 13, weight: .regular)
    static let descriptionText = Font.system(size: 12, weight: .regular)
    static let caption11 = Font.system(size: 11, weight: .regular)
    static let codeInline = Font.system(size: 12, design: .monospaced)
}

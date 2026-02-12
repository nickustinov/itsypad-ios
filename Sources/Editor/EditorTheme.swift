import UIKit

struct EditorTheme {
    let isDark: Bool
    let background: UIColor
    let foreground: UIColor

    var insertionPointColor: UIColor { isDark ? .white : .black }

    // MARK: - Resolve theme for current appearance setting

    static func current(for appearance: String) -> EditorTheme {
        switch appearance {
        case "light": return light
        case "dark": return dark
        default:
            return UITraitCollection.current.userInterfaceStyle == .dark ? dark : light
        }
    }

    // MARK: - Hardcoded fallback (Itsypad)

    static let dark = EditorTheme(
        isDark: true,
        background: hex(0x25252c),
        foreground: hex(0xd4d4d4)
    )

    static let light = EditorTheme(
        isDark: false,
        background: hex(0xffffff),
        foreground: hex(0x403e41)
    )

    // Bullet-dash color (matches punctuation.special from old captures)
    var bulletDashColor: UIColor { isDark ? Self.hex(0xff6188) : Self.hex(0xd3284e) }

    // Checkbox bracket color
    var checkboxColor: UIColor { isDark ? Self.hex(0xab9df2) : Self.hex(0x7c6bb7) }

    // Link color
    var linkColor: UIColor { isDark ? Self.hex(0x78b9f2) : Self.hex(0x0969b2) }

    // MARK: - Hex color helper

    private static func hex(_ value: UInt32) -> UIColor {
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}

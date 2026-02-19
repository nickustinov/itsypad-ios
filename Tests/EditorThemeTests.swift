import XCTest
@testable import ItsypadCore

final class EditorThemeTests: XCTestCase {

    // MARK: - Light preset

    func testLightPresetIsNotDark() {
        XCTAssertFalse(EditorTheme.light.isDark)
    }

    func testLightPresetBackgroundIsWhite() {
        assertColorsEqual(EditorTheme.light.background, UIColor(red: 1, green: 1, blue: 1, alpha: 1))
    }

    func testLightPresetForegroundColor() {
        assertColorsEqual(
            EditorTheme.light.foreground,
            UIColor(red: 0x40 / 255.0, green: 0x3e / 255.0, blue: 0x41 / 255.0, alpha: 1)
        )
    }

    // MARK: - Dark preset

    func testDarkPresetIsDark() {
        XCTAssertTrue(EditorTheme.dark.isDark)
    }

    func testDarkPresetBackgroundColor() {
        assertColorsEqual(
            EditorTheme.dark.background,
            UIColor(red: 0x25 / 255.0, green: 0x25 / 255.0, blue: 0x2c / 255.0, alpha: 1)
        )
    }

    func testDarkPresetForegroundColor() {
        assertColorsEqual(
            EditorTheme.dark.foreground,
            UIColor(red: 0xd4 / 255.0, green: 0xd4 / 255.0, blue: 0xd4 / 255.0, alpha: 1)
        )
    }

    // MARK: - Insertion point color

    func testInsertionPointColorForDarkIsWhite() {
        XCTAssertEqual(EditorTheme.dark.insertionPointColor, .white)
    }

    func testInsertionPointColorForLightIsBlack() {
        XCTAssertEqual(EditorTheme.light.insertionPointColor, .black)
    }

    // MARK: - current(for:)

    func testCurrentForLightReturnsLightTheme() {
        let theme = EditorTheme.current(for: "light")
        XCTAssertFalse(theme.isDark)
        assertColorsEqual(theme.background, EditorTheme.light.background)
    }

    func testCurrentForDarkReturnsDarkTheme() {
        let theme = EditorTheme.current(for: "dark")
        XCTAssertTrue(theme.isDark)
        assertColorsEqual(theme.background, EditorTheme.dark.background)
    }

    // MARK: - Semantic colors differ between light and dark

    func testBulletDashColorDiffersForLightAndDark() {
        XCTAssertNotEqual(EditorTheme.light.bulletDashColor, EditorTheme.dark.bulletDashColor)
    }

    func testCheckboxColorDiffersForLightAndDark() {
        XCTAssertNotEqual(EditorTheme.light.checkboxColor, EditorTheme.dark.checkboxColor)
    }

    func testLinkColorDiffersForLightAndDark() {
        XCTAssertNotEqual(EditorTheme.light.linkColor, EditorTheme.dark.linkColor)
    }

    // MARK: - Specific semantic colors

    func testDarkBulletDashColor() {
        assertColorsEqual(
            EditorTheme.dark.bulletDashColor,
            UIColor(red: 0xff / 255.0, green: 0x61 / 255.0, blue: 0x88 / 255.0, alpha: 1)
        )
    }

    func testLightBulletDashColor() {
        assertColorsEqual(
            EditorTheme.light.bulletDashColor,
            UIColor(red: 0xd3 / 255.0, green: 0x28 / 255.0, blue: 0x4e / 255.0, alpha: 1)
        )
    }

    func testDarkCheckboxColor() {
        assertColorsEqual(
            EditorTheme.dark.checkboxColor,
            UIColor(red: 0xab / 255.0, green: 0x9d / 255.0, blue: 0xf2 / 255.0, alpha: 1)
        )
    }

    func testLightCheckboxColor() {
        assertColorsEqual(
            EditorTheme.light.checkboxColor,
            UIColor(red: 0x7c / 255.0, green: 0x6b / 255.0, blue: 0xb7 / 255.0, alpha: 1)
        )
    }

    func testDarkLinkColor() {
        assertColorsEqual(
            EditorTheme.dark.linkColor,
            UIColor(red: 0x78 / 255.0, green: 0xb9 / 255.0, blue: 0xf2 / 255.0, alpha: 1)
        )
    }

    func testLightLinkColor() {
        assertColorsEqual(
            EditorTheme.light.linkColor,
            UIColor(red: 0x09 / 255.0, green: 0x69 / 255.0, blue: 0xb2 / 255.0, alpha: 1)
        )
    }

    // MARK: - Custom theme

    func testCustomThemePreservesProperties() {
        let theme = EditorTheme(isDark: true, background: .red, foreground: .green)
        XCTAssertTrue(theme.isDark)
        XCTAssertEqual(theme.background, .red)
        XCTAssertEqual(theme.foreground, .green)
    }

    func testCustomLightThemeInsertionPoint() {
        let theme = EditorTheme(isDark: false, background: .white, foreground: .black)
        XCTAssertEqual(theme.insertionPointColor, .black)
    }

    func testCustomDarkThemeInsertionPoint() {
        let theme = EditorTheme(isDark: true, background: .black, foreground: .white)
        XCTAssertEqual(theme.insertionPointColor, .white)
    }

    // MARK: - Helper

    private func assertColorsEqual(
        _ color1: UIColor, _ color2: UIColor,
        accuracy: CGFloat = 0.01,
        file: StaticString = #file, line: UInt = #line
    ) {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertEqual(r1, r2, accuracy: accuracy, "Red mismatch", file: file, line: line)
        XCTAssertEqual(g1, g2, accuracy: accuracy, "Green mismatch", file: file, line: line)
        XCTAssertEqual(b1, b2, accuracy: accuracy, "Blue mismatch", file: file, line: line)
        XCTAssertEqual(a1, a2, accuracy: accuracy, "Alpha mismatch", file: file, line: line)
    }
}

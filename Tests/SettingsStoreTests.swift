import XCTest
@testable import ItsypadCore

final class SettingsStoreTests: XCTestCase {
    private var store: SettingsStore!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.nickustinov.itsypad.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Default values

    func testDefaultEditorFontSize() {
        XCTAssertEqual(store.editorFontSize, 14)
    }

    func testDefaultAppearanceOverride() {
        XCTAssertEqual(store.appearanceOverride, "system")
    }

    func testDefaultSyntaxTheme() {
        XCTAssertEqual(store.syntaxTheme, "itsypad")
    }

    func testDefaultIndentUsingSpaces() {
        XCTAssertTrue(store.indentUsingSpaces)
    }

    func testDefaultTabWidth() {
        XCTAssertEqual(store.tabWidth, 4)
    }

    func testDefaultBulletLists() {
        XCTAssertTrue(store.bulletListsEnabled)
    }

    func testDefaultNumberedLists() {
        XCTAssertTrue(store.numberedListsEnabled)
    }

    func testDefaultChecklists() {
        XCTAssertTrue(store.checklistsEnabled)
    }

    func testDefaultClickableLinks() {
        XCTAssertTrue(store.clickableLinks)
    }

    func testDefaultIcloudSync() {
        XCTAssertFalse(store.icloudSync)
    }

    // MARK: - Setting persistence

    func testEditorFontSizePersistsToDefaults() {
        store.editorFontSize = 16
        XCTAssertEqual(defaults.double(forKey: "editorFontSize"), 16)
    }

    func testAppearancePersistsToDefaults() {
        store.appearanceOverride = "dark"
        XCTAssertEqual(defaults.string(forKey: "appearanceOverride"), "dark")
    }

    func testSyntaxThemePersistsToDefaults() {
        store.syntaxTheme = "github"
        XCTAssertEqual(defaults.string(forKey: "syntaxTheme"), "github")
    }

    func testIcloudSyncPersistsToDefaults() {
        store.setICloudSync(true)
        XCTAssertTrue(defaults.bool(forKey: "icloudSync"))
    }

    func testClickableLinksPersistsToDefaults() {
        store.clickableLinks = false
        XCTAssertFalse(defaults.bool(forKey: "clickableLinks"))
    }

    func testTabWidthPersistsToDefaults() {
        store.tabWidth = 2
        XCTAssertEqual(defaults.integer(forKey: "tabWidth"), 2)
    }

    // MARK: - editorFont computed property

    func testEditorFontIsMonospaced() {
        store.editorFontSize = 14
        let font = store.editorFont
        XCTAssertEqual(font.pointSize, 14)
    }

    // MARK: - Load from pre-populated defaults

    func testLoadFromPrePopulatedDefaults() {
        let preSuiteName = "com.nickustinov.itsypad.test.\(UUID().uuidString)"
        let preDefaults = UserDefaults(suiteName: preSuiteName)!
        preDefaults.set(18.0, forKey: "editorFontSize")
        preDefaults.set("dark", forKey: "appearanceOverride")
        preDefaults.set(2, forKey: "tabWidth")
        preDefaults.set(false, forKey: "clickableLinks")
        preDefaults.set("github", forKey: "syntaxTheme")

        let preStore = SettingsStore(defaults: preDefaults)
        XCTAssertEqual(preStore.editorFontSize, 18)
        XCTAssertEqual(preStore.appearanceOverride, "dark")
        XCTAssertEqual(preStore.tabWidth, 2)
        XCTAssertFalse(preStore.clickableLinks)
        XCTAssertEqual(preStore.syntaxTheme, "github")

        preDefaults.removePersistentDomain(forName: preSuiteName)
    }
}

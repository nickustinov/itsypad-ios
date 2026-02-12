import UIKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private var isLoading = true
    let defaults: UserDefaults

    @Published var editorFontSize: Double = 14 {
        didSet {
            guard !isLoading else { return }
            defaults.set(editorFontSize, forKey: "editorFontSize")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var appearanceOverride: String = "system" {
        didSet {
            guard !isLoading else { return }
            defaults.set(appearanceOverride, forKey: "appearanceOverride")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var syntaxTheme: String = "itsypad" {
        didSet {
            guard !isLoading else { return }
            defaults.set(syntaxTheme, forKey: "syntaxTheme")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var indentUsingSpaces: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(indentUsingSpaces, forKey: "indentUsingSpaces")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var tabWidth: Int = 4 {
        didSet {
            guard !isLoading else { return }
            defaults.set(tabWidth, forKey: "tabWidth")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var bulletListsEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(bulletListsEnabled, forKey: "bulletListsEnabled")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var numberedListsEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(numberedListsEnabled, forKey: "numberedListsEnabled")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var checklistsEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(checklistsEnabled, forKey: "checklistsEnabled")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var clickableLinks: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(clickableLinks, forKey: "clickableLinks")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var icloudSync: Bool = false

    func setICloudSync(_ enabled: Bool) {
        icloudSync = enabled
        defaults.set(enabled, forKey: "icloudSync")
        defaults.synchronize()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    var indentString: String {
        indentUsingSpaces ? String(repeating: " ", count: tabWidth) : "\t"
    }

    var editorFont: UIFont {
        .monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadSettings()
        isLoading = false
    }

    private func loadSettings() {
        let savedSize = defaults.double(forKey: "editorFontSize")
        editorFontSize = savedSize > 0 ? savedSize : 14
        appearanceOverride = defaults.string(forKey: "appearanceOverride") ?? "system"
        syntaxTheme = defaults.string(forKey: "syntaxTheme") ?? "itsypad"
        indentUsingSpaces = defaults.object(forKey: "indentUsingSpaces") as? Bool ?? true
        let savedTabWidth = defaults.integer(forKey: "tabWidth")
        tabWidth = savedTabWidth > 0 ? savedTabWidth : 4
        bulletListsEnabled = defaults.object(forKey: "bulletListsEnabled") as? Bool ?? true
        numberedListsEnabled = defaults.object(forKey: "numberedListsEnabled") as? Bool ?? true
        checklistsEnabled = defaults.object(forKey: "checklistsEnabled") as? Bool ?? true
        clickableLinks = defaults.object(forKey: "clickableLinks") as? Bool ?? true
        icloudSync = defaults.bool(forKey: "icloudSync")
    }
}

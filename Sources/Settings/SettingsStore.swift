import UIKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
}

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private var isLoading = true
    let defaults: UserDefaults

    @Published var editorFontSize: Double = 16 {
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

    @Published var lineSpacing: Double = 1.0 {
        didSet {
            guard !isLoading else { return }
            defaults.set(lineSpacing, forKey: "lineSpacing")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var letterSpacing: Double = 0.0 {
        didSet {
            guard !isLoading else { return }
            defaults.set(letterSpacing, forKey: "letterSpacing")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var wordWrap: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(wordWrap, forKey: "wordWrap")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var showLineNumbers: Bool = false {
        didSet {
            guard !isLoading else { return }
            defaults.set(showLineNumbers, forKey: "showLineNumbers")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    @Published var lockRotation: Bool = true {
        didSet {
            guard !isLoading else { return }
            defaults.set(lockRotation, forKey: "lockRotation")
        }
    }

    @Published var icloudSync: Bool = true

    func setICloudSync(_ enabled: Bool) {
        icloudSync = enabled
        defaults.set(enabled, forKey: "icloudSync")
        defaults.synchronize()
        if enabled {
            CloudSyncEngine.shared.start()
        } else {
            CloudSyncEngine.shared.stop()
        }
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
        editorFontSize = savedSize > 0 ? savedSize : 16
        appearanceOverride = defaults.string(forKey: "appearanceOverride") ?? "system"
        syntaxTheme = defaults.string(forKey: "syntaxTheme") ?? "itsypad"
        indentUsingSpaces = defaults.object(forKey: "indentUsingSpaces") as? Bool ?? true
        let savedTabWidth = defaults.integer(forKey: "tabWidth")
        tabWidth = savedTabWidth > 0 ? savedTabWidth : 4
        bulletListsEnabled = defaults.object(forKey: "bulletListsEnabled") as? Bool ?? true
        numberedListsEnabled = defaults.object(forKey: "numberedListsEnabled") as? Bool ?? true
        checklistsEnabled = defaults.object(forKey: "checklistsEnabled") as? Bool ?? true
        clickableLinks = defaults.object(forKey: "clickableLinks") as? Bool ?? true
        let savedLineSpacing = defaults.double(forKey: "lineSpacing")
        lineSpacing = savedLineSpacing > 0 ? savedLineSpacing : 1.0
        letterSpacing = defaults.double(forKey: "letterSpacing")
        wordWrap = defaults.object(forKey: "wordWrap") as? Bool ?? true
        showLineNumbers = defaults.object(forKey: "showLineNumbers") as? Bool ?? false
        lockRotation = defaults.object(forKey: "lockRotation") as? Bool ?? true
        icloudSync = defaults.object(forKey: "icloudSync") as? Bool ?? true
    }
}

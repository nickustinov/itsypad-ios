import SwiftUI

@main
struct ItsypadApp: App {
    @StateObject private var tabStore = TabStore.shared
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tabStore)
                .environmentObject(settings)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings.appearanceOverride {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

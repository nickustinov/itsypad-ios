import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore
    @State private var showTabGrid = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let tab = tabStore.selectedTab {
                    EditorView(tabID: tab.id)
                        .ignoresSafeArea(.keyboard)
                } else {
                    Color.clear
                }
            }
            .navigationTitle({
                    let name = tabStore.selectedTab?.name ?? ""
                    return name.isEmpty ? "Untitled" : name
                }())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { tabStore.addNewTab() } label: {
                        Image(systemName: "plus")
                    }
                    Button { showTabGrid = true } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showTabGrid) {
            TabGridView()
                .environmentObject(tabStore)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { _ in
            tabStore.saveSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            tabStore.checkICloud()
        }
    }
}

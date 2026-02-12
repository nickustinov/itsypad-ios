import SwiftUI

struct TabGridView: View {
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var renamingTabID: UUID?
    @State private var renameText: String = ""

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    private var themeBackground: Color {
        let theme = EditorTheme.current(for: settings.appearanceOverride)
        return Color(theme.background)
    }

    private var themeForeground: Color {
        let theme = EditorTheme.current(for: settings.appearanceOverride)
        return Color(theme.foreground)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(tabStore.tabs) { tab in
                        TabCardView(
                            tab: tab,
                            isSelected: tab.id == tabStore.selectedTabID,
                            themeBackground: themeBackground,
                            themeForeground: themeForeground
                        )
                        .onTapGesture {
                            tabStore.selectedTabID = tab.id
                            dismiss()
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameText = tab.name
                                renamingTabID = tab.id
                            }
                            Button("Delete", role: .destructive) {
                                tabStore.closeTab(id: tab.id)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        tabStore.addNewTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Rename tab", isPresented: .init(
                get: { renamingTabID != nil },
                set: { if !$0 { renamingTabID = nil } }
            )) {
                TextField("Tab name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingTabID = nil }
                Button("Rename") {
                    if let id = renamingTabID {
                        tabStore.renameTab(id: id, name: renameText)
                    }
                    renamingTabID = nil
                }
            }
        }
    }
}

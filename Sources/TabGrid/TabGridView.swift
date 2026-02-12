import SwiftUI
import UniformTypeIdentifiers

struct TabGridView: View {
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var renamingTabID: UUID?
    @State private var renameText: String = ""
    @State private var pendingCloseTabID: UUID?
    @State private var showCloseConfirmation = false
    @State private var showSaveAsExporter = false
    @State private var closeAfterSaveAs = false

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
                            themeForeground: themeForeground,
                            onClose: { requestClose(tab: tab) }
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
                                requestClose(tab: tab)
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
            .alert(
                "Do you want to save changes to \"\(tabStore.tabs.first { $0.id == pendingCloseTabID }?.name ?? "Untitled")\"?",
                isPresented: $showCloseConfirmation
            ) {
                Button("Save") {
                    if let id = pendingCloseTabID {
                        if let tab = tabStore.tabs.first(where: { $0.id == id }), tab.fileURL != nil {
                            tabStore.saveFile(id: id)
                            tabStore.closeTab(id: id)
                        } else {
                            closeAfterSaveAs = true
                            showSaveAsExporter = true
                        }
                    }
                    if !closeAfterSaveAs {
                        pendingCloseTabID = nil
                    }
                }
                Button("Don't save", role: .destructive) {
                    if let id = pendingCloseTabID {
                        tabStore.closeTab(id: id)
                    }
                    pendingCloseTabID = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingCloseTabID = nil
                }
            } message: {
                Text("Your changes will be lost if you don't save them.")
            }
            .fileExporter(
                isPresented: $showSaveAsExporter,
                document: TextFileDocument(content: tabStore.tabs.first { $0.id == pendingCloseTabID }?.content ?? ""),
                contentType: .plainText,
                defaultFilename: tabStore.tabs.first { $0.id == pendingCloseTabID }?.name ?? "Untitled"
            ) { result in
                if case .success(let url) = result, let id = pendingCloseTabID {
                    tabStore.completeSaveAs(id: id, url: url)
                    if closeAfterSaveAs {
                        tabStore.closeTab(id: id)
                    }
                }
                pendingCloseTabID = nil
                closeAfterSaveAs = false
            }
        }
    }

    private func requestClose(tab: TabData) {
        if tab.hasUnsavedChanges {
            pendingCloseTabID = tab.id
            showCloseConfirmation = true
        } else {
            tabStore.closeTab(id: tab.id)
        }
    }
}

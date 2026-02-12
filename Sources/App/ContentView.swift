import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore
    @State private var showTabGrid = false
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var showCloseConfirmation = false
    @State private var pendingCloseTabID: UUID?

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
                ToolbarItem(placement: .topBarLeading) {
                    Button { showTabGrid = true } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { tabStore.addNewTab() } label: {
                        Image(systemName: "plus")
                    }
                    Menu {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Open...", systemImage: "doc")
                        }
                        Button {
                            if let id = tabStore.selectedTabID {
                                if tabStore.selectedTabNeedsSaveAs {
                                    showFileExporter = true
                                } else {
                                    tabStore.saveFile(id: id)
                                }
                            }
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        Button {
                            showFileExporter = true
                        } label: {
                            Label("Save as...", systemImage: "square.and.arrow.down.on.square")
                        }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        Button {
                            if let id = tabStore.selectedTabID {
                                if tabStore.selectedTab?.hasUnsavedChanges == true {
                                    pendingCloseTabID = id
                                    showCloseConfirmation = true
                                } else {
                                    tabStore.closeTab(id: id)
                                }
                            }
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        Divider()
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings...", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .sourceCode, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    tabStore.openFile(url: url)
                }
            case .failure(let error):
                NSLog("File import failed: \(error)")
            }
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: TextFileDocument(content: tabStore.selectedTab?.content ?? ""),
            contentType: .plainText,
            defaultFilename: tabStore.selectedTab?.name ?? "Untitled"
        ) { result in
            switch result {
            case .success(let url):
                if let id = tabStore.selectedTabID {
                    tabStore.completeSaveAs(id: id, url: url)
                }
            case .failure(let error):
                NSLog("File export failed: \(error)")
            }
        }
        .alert(
            "Do you want to save changes to \"\(tabStore.tabs.first { $0.id == pendingCloseTabID }?.name ?? "Untitled")\"?",
            isPresented: $showCloseConfirmation
        ) {
            Button("Save") {
                if let id = pendingCloseTabID {
                    if tabStore.selectedTabNeedsSaveAs {
                        showFileExporter = true
                    } else {
                        tabStore.saveFile(id: id)
                    }
                    tabStore.closeTab(id: id)
                }
                pendingCloseTabID = nil
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
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification)) { _ in
            tabStore.saveSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            tabStore.checkICloud()
        }
    }
}

struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(content.utf8))
    }
}

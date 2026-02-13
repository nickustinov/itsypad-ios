import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var tabStore: TabStore
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showTabGrid = false
    @State private var showClipboard = false
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var showFileExporter = false
    @State private var showCloseConfirmation = false
    @State private var pendingCloseTabID: UUID?

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .sheet(isPresented: $showTabGrid) {
            TabGridView()
                .environmentObject(tabStore)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showClipboard) {
            ClipboardView()
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

    // MARK: - Regular layout (iPad)

    private var sidebarThemeBackground: Color {
        Color(EditorTheme.current(for: settings.appearanceOverride).background)
    }

    private var sidebarThemeForeground: Color {
        Color(EditorTheme.current(for: settings.appearanceOverride).foreground)
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tabStore.tabs) { tab in
                        sidebarCard(for: tab)
                            .onTapGesture {
                                tabStore.selectedTabID = tab.id
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    if tab.hasUnsavedChanges {
                                        pendingCloseTabID = tab.id
                                        showCloseConfirmation = true
                                    } else {
                                        tabStore.closeTab(id: tab.id)
                                    }
                                } label: {
                                    Label("Close", systemImage: "xmark")
                                }
                            }
                    }
                }
                .padding(12)
            }
            .navigationTitle("Tabs")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { tabStore.addNewTab() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            editorDetail
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { showClipboard = true } label: {
                            Image(systemName: "clipboard")
                                .scaleEffect(0.9)
                                .offset(y: -2)
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        fileMenu
                    }
                }
        }
    }

    private func sidebarCard(for tab: TabData) -> some View {
        let isSelected = tab.id == tabStore.selectedTabID
        let preview = tab.content.components(separatedBy: .newlines).prefix(3).joined(separator: "\n")

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(tab.name.isEmpty ? "Untitled" : tab.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)

                if tab.hasUnsavedChanges {
                    Circle()
                        .fill(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 6, height: 6)
                }

                Spacer(minLength: 0)
            }

            if !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(sidebarThemeForeground.opacity(0.7))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(sidebarThemeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 0.5)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                if tab.hasUnsavedChanges {
                    pendingCloseTabID = tab.id
                    showCloseConfirmation = true
                } else {
                    tabStore.closeTab(id: tab.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(6)
        }
    }

    // MARK: - Compact layout (iPhone)

    private var compactLayout: some View {
        NavigationStack {
            editorDetail
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { showTabGrid = true } label: {
                            Image(systemName: "square.grid.2x2")
                        }
                        Button { showClipboard = true } label: {
                            Image(systemName: "clipboard")
                                .scaleEffect(0.9)
                                .offset(y: -2)
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { tabStore.addNewTab() } label: {
                            Image(systemName: "plus")
                        }
                        fileMenu
                    }
                }
        }
    }

    // MARK: - Shared subviews

    private var editorDetail: some View {
        Group {
            if let tab = tabStore.selectedTab {
                EditorView(tabID: tab.id)
                    .ignoresSafeArea(.container, edges: .vertical)
                    .ignoresSafeArea(.keyboard)
            } else {
                Color.clear
            }
        }
        .background {
            if #available(iOS 26.0, *) {
                sidebarThemeBackground
                    .ignoresSafeArea()
                    .backgroundExtensionEffect()
            } else {
                sidebarThemeBackground
                    .ignoresSafeArea()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fileMenu: some View {
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

import Foundation

protocol KeyValueStoreProtocol: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueStoreProtocol {
    func setData(_ data: Data?, forKey key: String) {
        set(data, forKey: key)
    }
}

struct TabData: Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var language: String
    var languageLocked: Bool
    var cursorPosition: Int
    var lastModified: Date

    init(
        id: UUID = UUID(),
        name: String = "Untitled",
        content: String = "",
        language: String = "plain",
        languageLocked: Bool = false,
        cursorPosition: Int = 0,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.language = language
        self.languageLocked = languageLocked
        self.cursorPosition = cursorPosition
        self.lastModified = lastModified
    }
}

extension TabData: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, content, language, languageLocked, cursorPosition, lastModified
        // Accept macOS fields gracefully
        case fileURL, isDirty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        content = try c.decode(String.self, forKey: .content)
        language = try c.decode(String.self, forKey: .language)
        languageLocked = try c.decode(Bool.self, forKey: .languageLocked)
        cursorPosition = try c.decode(Int.self, forKey: .cursorPosition)
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? .distantPast
        // Silently ignore fileURL and isDirty from macOS
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(content, forKey: .content)
        try c.encode(language, forKey: .language)
        try c.encode(languageLocked, forKey: .languageLocked)
        try c.encode(false, forKey: .isDirty)
        try c.encode(cursorPosition, forKey: .cursorPosition)
        try c.encode(lastModified, forKey: .lastModified)
    }
}

class TabStore: ObservableObject {
    static let shared = TabStore()

    @Published var tabs: [TabData] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var lastICloudSync: Date?

    private var saveDebounceWork: DispatchWorkItem?
    private var languageDetectWork: DispatchWorkItem?
    private let sessionURL: URL
    private let cloudStore: KeyValueStoreProtocol
    private var icloudObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private static let cloudTabsKey = "tabs"
    private static let cloudDeletedKey = "deletedTabIDs"
    private var deletedTabIDs: Set<UUID> = []

    var selectedTab: TabData? {
        tabs.first { $0.id == selectedTabID }
    }

    init(sessionURL: URL? = nil, cloudStore: KeyValueStoreProtocol = NSUbiquitousKeyValueStore.default) {
        self.cloudStore = cloudStore

        if let sessionURL {
            self.sessionURL = sessionURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let itsypadDir = appSupport.appendingPathComponent("Itsypad")
            try? FileManager.default.createDirectory(at: itsypadDir, withIntermediateDirectories: true)
            self.sessionURL = itsypadDir.appendingPathComponent("session.json")
        }

        restoreSession()

        if tabs.isEmpty {
            addNewTab()
        }

        if SettingsStore.shared.icloudSync {
            startICloudSync()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if SettingsStore.shared.icloudSync {
                self.startICloudSync()
            } else {
                self.stopICloudSync()
            }
        }
    }

    // MARK: - Tab operations

    func addNewTab() {
        let tab = TabData()
        tabs.append(tab)
        selectedTabID = tab.id
        scheduleSave()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if SettingsStore.shared.icloudSync {
            deletedTabIDs.insert(id)
            syncDeletedIDs()
        }
        tabs.remove(at: index)

        if selectedTabID == id {
            if tabs.isEmpty {
                addNewTab()
            } else {
                let newIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[newIndex].id
            }
        }
        scheduleSave()
    }

    func updateContent(id: UUID, content: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        guard tabs[index].content != content else { return }

        var tab = tabs[index]
        tab.content = content
        tab.lastModified = Date()

        // Auto-name from first line
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(30))
        tab.name = newName

        tabs[index] = tab

        if !tab.languageLocked {
            scheduleLanguageDetection(id: tab.id, content: content, name: tab.name)
        }

        scheduleSave()
    }

    private func scheduleLanguageDetection(id: UUID, content: String, name: String?) {
        languageDetectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let index = self.tabs.firstIndex(where: { $0.id == id }),
                  !self.tabs[index].languageLocked else { return }
            let result = LanguageDetector.shared.detect(text: content, name: name, fileURL: nil)
            if result.confidence > 5 {
                self.tabs[index].language = result.lang
            } else if self.tabs[index].language != "plain" && result.lang == "plain" {
                self.tabs[index].language = "plain"
            }
        }
        languageDetectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func updateLanguage(id: UUID, language: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].language = language
        tabs[index].languageLocked = true
        tabs[index].lastModified = Date()
        scheduleSave()
    }

    func updateCursorPosition(id: UUID, position: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].cursorPosition = position
    }

    func renameTab(id: UUID, name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].name = name
        tabs[index].lastModified = Date()
        scheduleSave()
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        let insertAt = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        tabs.insert(tab, at: insertAt)
        scheduleSave()
    }

    // MARK: - iCloud sync

    struct CloudMergeResult {
        var newTabIDs: [UUID] = []
        var updatedTabIDs: [UUID] = []
        var removedTabIDs: [UUID] = []
    }

    static let cloudTabsMerged = Notification.Name("cloudTabsMerged")

    private func syncDeletedIDs() {
        let strings = deletedTabIDs.map(\.uuidString)
        cloudStore.setData(try? JSONEncoder().encode(strings), forKey: Self.cloudDeletedKey)
        cloudStore.synchronize()
    }

    private func loadDeletedIDs() {
        guard let data = cloudStore.data(forKey: Self.cloudDeletedKey),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return }
        deletedTabIDs = Set(strings.compactMap(UUID.init))
    }

    func startICloudSync() {
        guard icloudObserver == nil else {
            print("[TabStore] startICloudSync: already observing, skipping")
            return
        }
        print("[TabStore] startICloudSync: starting")
        let synced = cloudStore.synchronize()
        print("[TabStore] startICloudSync: synchronize returned \(synced)")
        if synced { lastICloudSync = Date() }
        loadDeletedIDs()
        mergeCloudTabs()

        icloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore, queue: .main
        ) { [weak self] _ in
            print("[TabStore] iCloud external change notification received")
            self?.mergeCloudTabs()
        }

        // Retry merge – iCloud KVS can take time to pull data after login
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, SettingsStore.shared.icloudSync else { return }
                print("[TabStore] iCloud merge retry after \(delay)s")
                self.cloudStore.synchronize()
                self.mergeCloudTabs()
            }
        }
    }

    func stopICloudSync() {
        if let observer = icloudObserver {
            NotificationCenter.default.removeObserver(observer)
            icloudObserver = nil
        }
        cloudStore.removeObject(forKey: Self.cloudTabsKey)
        cloudStore.removeObject(forKey: Self.cloudDeletedKey)
        deletedTabIDs.removeAll()
        cloudStore.synchronize()
    }

    func checkICloud() {
        guard SettingsStore.shared.icloudSync else { return }
        cloudStore.synchronize()
        loadDeletedIDs()
        mergeCloudTabs()
    }

    private func saveToICloud() {
        guard SettingsStore.shared.icloudSync else { return }
        guard let data = try? JSONEncoder().encode(tabs) else { return }
        cloudStore.setData(data, forKey: Self.cloudTabsKey)
        cloudStore.synchronize()
        lastICloudSync = Date()
    }

    private func mergeCloudTabs() {
        guard SettingsStore.shared.icloudSync else {
            print("[TabStore] mergeCloudTabs: iCloud sync disabled, skipping")
            return
        }
        guard let data = cloudStore.data(forKey: Self.cloudTabsKey) else {
            print("[TabStore] mergeCloudTabs: no cloud data found")
            return
        }
        guard let cloudTabs = try? JSONDecoder().decode([TabData].self, from: data) else {
            print("[TabStore] mergeCloudTabs: failed to decode cloud data (\(data.count) bytes)")
            return
        }
        print("[TabStore] mergeCloudTabs: found \(cloudTabs.count) cloud tabs, \(tabs.count) local tabs")

        var result = CloudMergeResult()
        for cloudTab in cloudTabs {
            if deletedTabIDs.contains(cloudTab.id) { continue }
            if let localIndex = tabs.firstIndex(where: { $0.id == cloudTab.id }) {
                guard cloudTab.lastModified > tabs[localIndex].lastModified else { continue }
                if tabs[localIndex].content != cloudTab.content
                    || tabs[localIndex].name != cloudTab.name
                    || tabs[localIndex].language != cloudTab.language {
                    tabs[localIndex].content = cloudTab.content
                    tabs[localIndex].name = cloudTab.name
                    tabs[localIndex].language = cloudTab.language
                    tabs[localIndex].lastModified = cloudTab.lastModified
                    result.updatedTabIDs.append(cloudTab.id)
                }
            } else {
                tabs.append(cloudTab)
                result.newTabIDs.append(cloudTab.id)
            }
        }

        let toRemove = tabs.filter { deletedTabIDs.contains($0.id) }
        for tab in toRemove {
            result.removedTabIDs.append(tab.id)
        }
        tabs.removeAll { deletedTabIDs.contains($0.id) }

        if tabs.isEmpty {
            addNewTab()
        }

        let changed = !result.newTabIDs.isEmpty || !result.updatedTabIDs.isEmpty || !result.removedTabIDs.isEmpty
        print("[TabStore] mergeCloudTabs: new=\(result.newTabIDs.count) updated=\(result.updatedTabIDs.count) removed=\(result.removedTabIDs.count)")
        lastICloudSync = Date()

        if changed {
            NotificationCenter.default.post(
                name: Self.cloudTabsMerged,
                object: self,
                userInfo: ["result": result]
            )
            scheduleSave()
        }
    }

    // MARK: - Session persistence

    func scheduleSave() {
        saveDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveSession()
        }
        saveDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveSession() {
        do {
            let session = SessionData(tabs: tabs, selectedTabID: selectedTabID)
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionURL, options: .atomic)
        } catch {
            NSLog("Failed to save session: \(error)")
        }
        saveToICloud()
    }

    private func restoreSession() {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data)
        else { return }

        tabs = session.tabs
        selectedTabID = session.selectedTabID ?? tabs.first?.id

        for index in tabs.indices where !tabs[index].languageLocked {
            let tab = tabs[index]
            let result = LanguageDetector.shared.detect(
                text: tab.content,
                name: tab.name,
                fileURL: nil
            )
            if result.confidence > 5 {
                tabs[index].language = result.lang
            } else if result.lang == "plain" && tab.language != "plain" {
                tabs[index].language = "plain"
            }
        }
    }
}

struct SessionData: Codable {
    let tabs: [TabData]
    let selectedTabID: UUID?
}

import UIKit

struct ClipboardCloudEntry: Codable {
    let id: UUID
    let text: String
    let timestamp: Date
}

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
}

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published var entries: [ClipboardEntry] = []

    private let persistenceURL: URL
    internal let cloudStore: KeyValueStoreProtocol
    private var saveDebounceWork: DispatchWorkItem?
    private static let cloudKey = "clipboard"
    private static let cloudDeletedKey = "deletedClipboardIDs"
    private static let maxLocal = 1000
    private static let maxCloud = 200
    private var deletedEntryIDs: Set<UUID> = []

    init(
        persistenceURL: URL? = nil,
        cloudStore: KeyValueStoreProtocol? = nil
    ) {
        self.cloudStore = cloudStore ?? NSUbiquitousKeyValueStore.default

        if let persistenceURL {
            self.persistenceURL = persistenceURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let itsypadDir = appSupport.appendingPathComponent("Itsypad")
            try? FileManager.default.createDirectory(at: itsypadDir, withIntermediateDirectories: true)
            self.persistenceURL = itsypadDir.appendingPathComponent("clipboard.json")
        }
        restore()
    }

    // MARK: - Entry management

    func addEntry(text: String, id: UUID = UUID(), timestamp: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Deduplicate: skip if newest entry has identical text
        if entries.first?.text == trimmed { return }

        let entry = ClipboardEntry(id: id, text: trimmed, timestamp: timestamp)
        entries.insert(entry, at: 0)

        if entries.count > Self.maxLocal {
            entries = Array(entries.prefix(Self.maxLocal))
        }

        scheduleSave()
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        if SettingsStore.shared.icloudSync {
            deletedEntryIDs.insert(id)
            syncDeletedIDs()
        }
        scheduleSave()
        syncToCloud()
    }

    func clearAll() {
        if SettingsStore.shared.icloudSync {
            // Tombstone all local entry IDs
            deletedEntryIDs.formUnion(entries.map(\.id))
            // Also tombstone any cloud entry IDs not already local
            if let data = cloudStore.data(forKey: Self.cloudKey),
               let cloudEntries = try? JSONDecoder().decode([ClipboardCloudEntry].self, from: data) {
                deletedEntryIDs.formUnion(cloudEntries.map(\.id))
            }
            syncDeletedIDs()
        }
        entries.removeAll()
        scheduleSave()
        clearCloud()
    }

    func search(query: String) -> [ClipboardEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - Pasteboard

    func captureFromPasteboard() {
        guard let text = UIPasteboard.general.string else { return }
        addEntry(text: text)
        appendToCloud(text: text)
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        UIPasteboard.general.string = entry.text
    }

    // MARK: - iCloud sync

    func mergeCloudClipboard(from cloudStore: KeyValueStoreProtocol) {
        loadDeletedIDs(from: cloudStore)

        // Remove local entries that were tombstoned on another device
        let removedCount = entries.count
        entries.removeAll { deletedEntryIDs.contains($0.id) }
        let localRemoved = removedCount - entries.count

        guard let data = cloudStore.data(forKey: Self.cloudKey) else {
            if localRemoved > 0 {
                print("[ClipboardStore] mergeCloudClipboard: removed \(localRemoved) tombstoned local entries")
                scheduleSave()
            } else {
                print("[ClipboardStore] mergeCloudClipboard: no cloud data for key '\(Self.cloudKey)'")
            }
            return
        }
        guard let cloudEntries = try? JSONDecoder().decode([ClipboardCloudEntry].self, from: data) else {
            print("[ClipboardStore] mergeCloudClipboard: failed to decode \(data.count) bytes")
            return
        }
        print("[ClipboardStore] mergeCloudClipboard: \(cloudEntries.count) cloud entries, \(entries.count) local, \(localRemoved) tombstoned")

        let existingIDs = Set(entries.map(\.id))
        let existingTexts = Set(entries.map(\.text))
        var newEntries: [ClipboardEntry] = []

        for cloudEntry in cloudEntries {
            guard !deletedEntryIDs.contains(cloudEntry.id) else { continue }
            guard !existingIDs.contains(cloudEntry.id) else { continue }
            // Skip if identical text already exists locally (Universal Clipboard round-trip)
            guard !existingTexts.contains(cloudEntry.text) else { continue }
            newEntries.append(ClipboardEntry(
                id: cloudEntry.id,
                text: cloudEntry.text,
                timestamp: cloudEntry.timestamp
            ))
        }

        guard !newEntries.isEmpty || localRemoved > 0 else { return }
        if !newEntries.isEmpty {
            print("[ClipboardStore] mergeCloudClipboard: inserting \(newEntries.count) new entries")
        }

        entries.append(contentsOf: newEntries)
        entries.sort { $0.timestamp > $1.timestamp }

        if entries.count > Self.maxLocal {
            entries = Array(entries.prefix(Self.maxLocal))
        }

        scheduleSave()
    }

    /// Append a single new entry to the cloud clipboard (preserves existing cloud data).
    private func appendToCloud(text: String) {
        guard SettingsStore.shared.icloudSync else { return }

        var cloudEntries: [ClipboardCloudEntry] = []
        if let data = cloudStore.data(forKey: Self.cloudKey),
           let existing = try? JSONDecoder().decode([ClipboardCloudEntry].self, from: data) {
            cloudEntries = existing
        }

        let newEntry = ClipboardCloudEntry(id: UUID(), text: text, timestamp: Date())
        cloudEntries.insert(newEntry, at: 0)
        cloudEntries = Array(cloudEntries.prefix(Self.maxCloud))

        guard let data = try? JSONEncoder().encode(cloudEntries) else { return }
        cloudStore.setData(data, forKey: Self.cloudKey)
        cloudStore.synchronize()
    }

    private func syncToCloud() {
        guard SettingsStore.shared.icloudSync else { return }
        let cloudEntries = entries.prefix(Self.maxCloud).map {
            ClipboardCloudEntry(id: $0.id, text: $0.text, timestamp: $0.timestamp)
        }
        guard let data = try? JSONEncoder().encode(Array(cloudEntries)) else { return }
        cloudStore.setData(data, forKey: Self.cloudKey)
        cloudStore.synchronize()
    }

    private func clearCloud() {
        guard SettingsStore.shared.icloudSync else { return }
        cloudStore.removeObject(forKey: Self.cloudKey)
        cloudStore.synchronize()
    }

    // MARK: - Tombstone sync

    private func syncDeletedIDs() {
        let strings = deletedEntryIDs.map(\.uuidString)
        cloudStore.setData(try? JSONEncoder().encode(strings), forKey: Self.cloudDeletedKey)
        cloudStore.synchronize()
    }

    private func loadDeletedIDs(from store: KeyValueStoreProtocol) {
        guard let data = store.data(forKey: Self.cloudDeletedKey),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return }
        deletedEntryIDs.formUnion(strings.compactMap(UUID.init))
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            NSLog("Failed to save clipboard: \(error)")
        }
    }

    private func scheduleSave() {
        saveDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded
    }
}

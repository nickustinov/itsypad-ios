import UIKit

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date
}

class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published var entries: [ClipboardEntry] = []

    private let persistenceURL: URL
    private var saveDebounceWork: DispatchWorkItem?
    private static let maxLocal = 1000

    init(persistenceURL: URL? = nil) {
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
        CloudSyncEngine.shared.recordChanged(entry.id)
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        CloudSyncEngine.shared.recordDeleted(id)
        scheduleSave()
    }

    func clearAll() {
        for entry in entries {
            CloudSyncEngine.shared.recordDeleted(entry.id)
        }
        entries.removeAll()
        scheduleSave()
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
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        UIPasteboard.general.string = entry.text
    }

    // MARK: - Cloud sync

    func applyCloudClipboardEntry(_ data: CloudClipboardRecord) {
        if entries.contains(where: { $0.id == data.id }) { return }
        if entries.contains(where: { $0.text == data.text }) { return }

        let entry = ClipboardEntry(id: data.id, text: data.text, timestamp: data.timestamp)
        // Insert in chronological position (entries are sorted newest-first)
        let insertIndex = entries.firstIndex(where: { $0.timestamp < entry.timestamp }) ?? entries.endIndex
        entries.insert(entry, at: insertIndex)

        if entries.count > Self.maxLocal {
            entries = Array(entries.prefix(Self.maxLocal))
        }

        scheduleSave()
    }

    func removeCloudClipboardEntry(id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        scheduleSave()
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

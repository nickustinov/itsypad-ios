import XCTest
@testable import ItsypadCore

final class ClipboardStoreTests: XCTestCase {
    private var store: ClipboardStore!
    private var tempURL: URL!
    private var cloud: MockKeyValueStore!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        cloud = MockKeyValueStore()
        store = ClipboardStore(persistenceURL: tempURL, cloudStore: cloud)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        store = nil
        cloud = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInitStartsEmpty() {
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - ClipboardEntry Codable

    func testClipboardEntryCodableRoundtrip() throws {
        let entry = ClipboardEntry(id: UUID(), text: "hello", timestamp: Date())
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    // MARK: - Search

    func testSearchEmptyQueryReturnsAll() {
        store.addEntry(text: "alpha")
        store.addEntry(text: "beta")
        let results = store.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchFiltersByQuery() {
        store.addEntry(text: "hello world")
        store.addEntry(text: "goodbye world")
        store.addEntry(text: "hello there")
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.text.contains("hello") })
    }

    func testSearchIsCaseInsensitive() {
        store.addEntry(text: "Hello World")
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchNoMatch() {
        store.addEntry(text: "hello")
        let results = store.search(query: "xyz")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Delete

    func testDeleteEntry() {
        store.addEntry(text: "to delete")
        let id = store.entries.first!.id
        store.deleteEntry(id: id)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testDeleteNonexistentIDNoOp() {
        store.addEntry(text: "keep")
        store.deleteEntry(id: UUID())
        XCTAssertEqual(store.entries.count, 1)
    }

    // MARK: - Clear all

    func testClearAll() {
        store.addEntry(text: "one")
        store.addEntry(text: "two")
        store.clearAll()
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - Persistence

    func testPersistenceRoundtrip() {
        store.addEntry(text: "persisted")
        store.save()

        let restored = ClipboardStore(persistenceURL: tempURL, cloudStore: cloud)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.text, "persisted")
    }

    func testMissingFileStartsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let emptyStore = ClipboardStore(persistenceURL: missingURL, cloudStore: cloud)
        XCTAssertTrue(emptyStore.entries.isEmpty)
    }

    // MARK: - Cloud sync

    func testMergeCloudInsertsNewEntries() {
        let cloudEntry = ClipboardCloudEntry(id: UUID(), text: "from mac", timestamp: Date())
        let data = try! JSONEncoder().encode([cloudEntry])
        cloud.storage["clipboard"] = data

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "from mac")
        XCTAssertEqual(store.entries.first?.id, cloudEntry.id)
    }

    func testMergeCloudSkipsDuplicateUUIDs() {
        let id = UUID()
        store.addEntry(text: "local", id: id, timestamp: Date(timeIntervalSinceNow: -10))

        let cloudEntry = ClipboardCloudEntry(id: id, text: "from mac", timestamp: Date())
        let data = try! JSONEncoder().encode([cloudEntry])
        cloud.storage["clipboard"] = data

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 1)
        // Existing entry kept (no overwrite)
        XCTAssertEqual(store.entries.first?.text, "local")
    }

    func testMergeCloudChronologicalOrder() {
        let now = Date()
        let older = ClipboardCloudEntry(id: UUID(), text: "older", timestamp: now.addingTimeInterval(-60))
        let newer = ClipboardCloudEntry(id: UUID(), text: "newer", timestamp: now)
        let data = try! JSONEncoder().encode([older, newer])
        cloud.storage["clipboard"] = data

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 2)
        // Newest first
        XCTAssertEqual(store.entries.first?.text, "newer")
        XCTAssertEqual(store.entries.last?.text, "older")
    }

    // MARK: - Deduplication

    func testAddEntryDeduplicatesConsecutiveIdenticalText() {
        store.addEntry(text: "same")
        store.addEntry(text: "same")
        XCTAssertEqual(store.entries.count, 1)
    }

    func testAddEntryAllowsNonConsecutiveDuplicates() {
        store.addEntry(text: "a")
        store.addEntry(text: "b")
        store.addEntry(text: "a")
        XCTAssertEqual(store.entries.count, 3)
    }

    // MARK: - Entry ordering

    func testEntriesNewestFirst() {
        store.addEntry(text: "first")
        store.addEntry(text: "second")
        XCTAssertEqual(store.entries.first?.text, "second")
        XCTAssertEqual(store.entries.last?.text, "first")
    }

    // MARK: - Max entries

    func testMaxEntriesCapped() {
        for i in 0..<1010 {
            store.addEntry(text: "entry \(i)")
        }
        XCTAssertLessThanOrEqual(store.entries.count, 1000)
    }

    // MARK: - Tombstones

    func testDeleteEntrySyncsTombstone() {
        SettingsStore.shared.icloudSync = true
        defer { SettingsStore.shared.icloudSync = false }

        store.addEntry(text: "to delete")
        let id = store.entries.first!.id
        store.deleteEntry(id: id)

        let data = cloud.storage["deletedClipboardIDs"]!
        let ids = try! JSONDecoder().decode([String].self, from: data)
        XCTAssertTrue(ids.contains(id.uuidString))
    }

    func testClearAllSyncsTombstones() {
        SettingsStore.shared.icloudSync = true
        defer { SettingsStore.shared.icloudSync = false }

        store.addEntry(text: "one")
        store.addEntry(text: "two")
        let localIDs = Set(store.entries.map(\.id.uuidString))

        // Also put a cloud-only entry
        let cloudOnly = ClipboardCloudEntry(id: UUID(), text: "cloud only", timestamp: Date())
        let cloudData = try! JSONEncoder().encode([cloudOnly])
        cloud.storage["clipboard"] = cloudData

        store.clearAll()

        let data = cloud.storage["deletedClipboardIDs"]!
        let tombstoned = Set(try! JSONDecoder().decode([String].self, from: data))
        // Local IDs tombstoned
        XCTAssertTrue(localIDs.isSubset(of: tombstoned))
        // Cloud-only ID tombstoned
        XCTAssertTrue(tombstoned.contains(cloudOnly.id.uuidString))
    }

    func testMergeSkipsTombstonedCloudEntries() {
        let tombstonedID = UUID()
        let normalID = UUID()

        // Write tombstone to cloud
        let tombstoneData = try! JSONEncoder().encode([tombstonedID.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        // Write cloud entries including the tombstoned one
        let cloudEntries = [
            ClipboardCloudEntry(id: tombstonedID, text: "deleted", timestamp: Date()),
            ClipboardCloudEntry(id: normalID, text: "kept", timestamp: Date()),
        ]
        cloud.storage["clipboard"] = try! JSONEncoder().encode(cloudEntries)

        store.mergeCloudClipboard(from: cloud)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, normalID)
        XCTAssertEqual(store.entries.first?.text, "kept")
    }

    func testMergeRemovesTombstonedLocalEntries() {
        let id = UUID()
        store.addEntry(text: "will be removed", id: id, timestamp: Date())
        XCTAssertEqual(store.entries.count, 1)

        // Write tombstone to cloud for the local entry
        let tombstoneData = try! JSONEncoder().encode([id.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        store.mergeCloudClipboard(from: cloud)

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testMergeTriggersUIUpdate() {
        let id1 = UUID()
        let id2 = UUID()
        store.addEntry(text: "entry 1", id: id1, timestamp: Date())
        store.addEntry(text: "entry 2", id: id2, timestamp: Date())
        XCTAssertEqual(store.entries.count, 2)

        // Tombstone one entry via cloud
        let tombstoneData = try! JSONEncoder().encode([id1.uuidString])
        cloud.storage["deletedClipboardIDs"] = tombstoneData

        store.mergeCloudClipboard(from: cloud)

        // entries count changed – @Published triggers UI update
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, id2)
    }
}

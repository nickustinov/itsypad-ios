import XCTest
@testable import ItsypadCore

final class ClipboardStoreTests: XCTestCase {
    private var store: ClipboardStore!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        store = ClipboardStore(persistenceURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        store = nil
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

        let restored = ClipboardStore(persistenceURL: tempURL)
        XCTAssertEqual(restored.entries.count, 1)
        XCTAssertEqual(restored.entries.first?.text, "persisted")
    }

    func testMissingFileStartsEmpty() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let emptyStore = ClipboardStore(persistenceURL: missingURL)
        XCTAssertTrue(emptyStore.entries.isEmpty)
    }

    // MARK: - Cloud sync (applyCloudClipboardEntry / removeCloudClipboardEntry)

    func testApplyCloudEntryInsertsNew() {
        let record = CloudClipboardRecord(id: UUID(), text: "from mac", timestamp: Date())
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "from mac")
        XCTAssertEqual(store.entries.first?.id, record.id)
    }

    func testApplyCloudEntrySkipsDuplicateUUID() {
        let id = UUID()
        store.addEntry(text: "local", id: id, timestamp: Date(timeIntervalSinceNow: -10))

        let record = CloudClipboardRecord(id: id, text: "from mac", timestamp: Date())
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.text, "local")
    }

    func testApplyCloudEntrySkipsDuplicateText() {
        store.addEntry(text: "same text")

        let record = CloudClipboardRecord(id: UUID(), text: "same text", timestamp: Date())
        store.applyCloudClipboardEntry(record)

        XCTAssertEqual(store.entries.count, 1)
    }

    func testApplyCloudEntryChronologicalOrder() {
        let now = Date()
        let older = CloudClipboardRecord(id: UUID(), text: "older", timestamp: now.addingTimeInterval(-60))
        let newer = CloudClipboardRecord(id: UUID(), text: "newer", timestamp: now)

        store.applyCloudClipboardEntry(older)
        store.applyCloudClipboardEntry(newer)

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.text, "newer")
        XCTAssertEqual(store.entries.last?.text, "older")
    }

    func testRemoveCloudEntryRemovesExisting() {
        store.addEntry(text: "to remove")
        let id = store.entries.first!.id

        store.removeCloudClipboardEntry(id: id)

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRemoveCloudEntryNoOpForUnknownID() {
        store.addEntry(text: "keep")
        store.removeCloudClipboardEntry(id: UUID())
        XCTAssertEqual(store.entries.count, 1)
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
}

import XCTest
@testable import ItsypadCore

final class CloudSyncEngineTests: XCTestCase {

    // MARK: - CloudTabRecord

    func testCloudTabRecordStoresAllFields() {
        let id = UUID()
        let date = Date()
        let record = CloudTabRecord(
            id: id,
            name: "Test tab",
            content: "hello world",
            language: "swift",
            languageLocked: true,
            lastModified: date
        )
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.name, "Test tab")
        XCTAssertEqual(record.content, "hello world")
        XCTAssertEqual(record.language, "swift")
        XCTAssertTrue(record.languageLocked)
        XCTAssertEqual(record.lastModified, date)
    }

    func testCloudTabRecordMutability() {
        var record = CloudTabRecord(
            id: UUID(),
            name: "Original",
            content: "original",
            language: "plain",
            languageLocked: false,
            lastModified: Date()
        )
        record.name = "Updated"
        record.content = "updated"
        record.language = "swift"
        record.languageLocked = true
        XCTAssertEqual(record.name, "Updated")
        XCTAssertEqual(record.content, "updated")
        XCTAssertEqual(record.language, "swift")
        XCTAssertTrue(record.languageLocked)
    }

    // MARK: - CloudClipboardRecord

    func testCloudClipboardRecordStoresAllFields() {
        let id = UUID()
        let date = Date()
        let record = CloudClipboardRecord(id: id, text: "clipboard text", timestamp: date)
        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.text, "clipboard text")
        XCTAssertEqual(record.timestamp, date)
    }

    func testCloudClipboardRecordMutability() {
        var record = CloudClipboardRecord(id: UUID(), text: "original", timestamp: Date())
        record.text = "updated"
        XCTAssertEqual(record.text, "updated")
    }

    // MARK: - RecordType

    func testRecordTypeRawValues() {
        XCTAssertEqual(CloudSyncEngine.RecordType.scratchTab.rawValue, "ScratchTab")
        XCTAssertEqual(CloudSyncEngine.RecordType.clipboardEntry.rawValue, "ClipboardEntry")
    }
}

import CloudKit
import Foundation
import os.log

struct CloudTabRecord {
    let id: UUID
    var name: String
    var content: String
    var language: String
    var languageLocked: Bool
    var lastModified: Date
}

struct CloudClipboardRecord {
    let id: UUID
    var text: String
    var timestamp: Date
}

/// All mutable state (recordMetadata, syncEngine, container) is confined to
/// the main thread: the public API asserts main, and CKSyncEngine delegate
/// callbacks hop to the main actor before touching anything. That confinement
/// is what justifies `@unchecked Sendable` (required by CKSyncEngineDelegate).
final class CloudSyncEngine: @unchecked Sendable {
    static let shared = CloudSyncEngine()

    enum RecordType: String {
        case scratchTab = "ScratchTab"
        case clipboardEntry = "ClipboardEntry"
    }

    private static let containerID = "iCloud.com.nickustinov.itsypad"
    private static let zoneName = "ItsypadData"

    /// Bump this to force a full re-sync (clears stale metadata and change tokens).
    private static let syncVersion = 2

    // Lazy CloudKit objects – only created when start() is called
    private var container: CKContainer?
    private var database: CKDatabase?
    private let zoneID = CKRecordZone.ID(zoneName: CloudSyncEngine.zoneName)

    private var syncEngine: CKSyncEngine?
    private let stateURL: URL
    private let metadataURL: URL

    // Cache of last-known server record data (system fields) per record ID, for conflict detection
    private var recordMetadata: [String: Data] = [:]

    private let logger = Logger(subsystem: "com.nickustinov.itsypad", category: "CloudSync")

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let itsypadDir = appSupport.appendingPathComponent("Itsypad")
        try? FileManager.default.createDirectory(at: itsypadDir, withIntermediateDirectories: true)
        stateURL = itsypadDir.appendingPathComponent("cloud-sync-state.data")
        metadataURL = itsypadDir.appendingPathComponent("cloud-record-metadata.json")

        loadRecordMetadata()
    }

    /// Call after app launch to start sync if the user has it enabled.
    func startIfEnabled() {
        logger.info("startIfEnabled: icloudSync=\(SettingsStore.shared.icloudSync)")
        if SettingsStore.shared.icloudSync {
            start()
        }
    }

    // MARK: - Public API

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard syncEngine == nil else {
            logger.info("start: already running")
            return
        }

        // CKContainer traps if CloudKit entitlement is missing (e.g. in unit tests)
        guard Self.hasCloudKitEntitlement else {
            logger.info("start: no CloudKit entitlement")
            return
        }

        if container == nil {
            let ckContainer = CKContainer(identifier: Self.containerID)
            container = ckContainer
            database = ckContainer.privateCloudDatabase
        }

        guard let database else { return }

        // Detect first sync: either no metadata, or sync version bumped (e.g. dev→prod migration).
        let storedVersion = UserDefaults.standard.integer(forKey: "cloudSyncVersion")
        let versionMismatch = storedVersion < Self.syncVersion
        let isFirstSync = recordMetadata.isEmpty || versionMismatch
        if isFirstSync {
            if versionMismatch {
                logger.info("Sync version bumped (\(storedVersion) → \(Self.syncVersion)) – clearing state for full re-sync")
                recordMetadata.removeAll()
                saveRecordMetadata()
                UserDefaults.standard.set(Self.syncVersion, forKey: "cloudSyncVersion")
            }
            try? FileManager.default.removeItem(at: stateURL)
        }

        let stateSerialization = isFirstSync ? nil : loadStateSerialization()
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        syncEngine = CKSyncEngine(configuration)
        logger.info("Started (firstSync=\(isFirstSync), metadataCount=\(self.recordMetadata.count))")

        if isFirstSync {
            syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            reuploadAllRecords()
        }
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        syncEngine = nil
        recordMetadata.removeAll()
        flushRecordMetadata()
        logger.info("CloudSyncEngine stopped")
    }

    func recordChanged(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let engine = syncEngine else { return }
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    func fetchChanges() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let engine = syncEngine else {
            logger.info("fetchChanges: no syncEngine")
            return
        }
        logger.debug("fetchChanges: starting manual fetch")
        Task {
            do {
                try await engine.fetchChanges()
                self.logger.debug("fetchChanges: completed")
            } catch {
                self.logger.error("fetchChanges: \(error)")
            }
        }
    }

    func recordDeleted(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let engine = syncEngine else { return }
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    // MARK: - State persistence

    private func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveStateSerialization(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            let data = try JSONEncoder().encode(serialization)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("Failed to save sync state: \(error)")
        }
    }

    // MARK: - Record metadata cache

    private func loadRecordMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: Data].self, from: data) else { return }
        recordMetadata = decoded
    }

    /// Debounced: the metadata dictionary can hold thousands of entries and is
    /// touched once per record during a sync batch – encoding and writing the
    /// whole file per record would dominate sync time. A crash inside the
    /// debounce window only loses change tags, which the conflict handler
    /// recovers on the next save.
    private var metadataSaveWork: DispatchWorkItem?

    private func saveRecordMetadata() {
        metadataSaveWork?.cancel()
        let snapshot = recordMetadata
        let url = metadataURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        metadataSaveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Write pending metadata immediately. The debounced save is lost if the
    /// process is killed inside the window – a stale/empty metadata file makes
    /// the next launch look like a first sync and re-uploads everything.
    func flushRecordMetadata() {
        dispatchPrecondition(condition: .onQueue(.main))
        metadataSaveWork?.cancel()
        metadataSaveWork = nil
        guard let data = try? JSONEncoder().encode(recordMetadata) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func cacheRecordSystemFields(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        recordMetadata[record.recordID.recordName] = coder.encodedData
        saveRecordMetadata()
    }

    private func cachedRecord(for recordID: CKRecord.ID, recordType: String) -> CKRecord {
        if let data = recordMetadata[recordID.recordName],
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            if let record = CKRecord(coder: coder) {
                return record
            }
        }
        return CKRecord(recordType: recordType, recordID: recordID)
    }

    private func removeRecordMetadata(for recordID: CKRecord.ID) {
        recordMetadata.removeValue(forKey: recordID.recordName)
        saveRecordMetadata()
    }

    // MARK: - Record building

    private func buildScratchTabRecord(id: UUID, recordID: CKRecord.ID) -> CKRecord? {
        guard let tab = TabStore.shared.tabs.first(where: { $0.id == id && $0.fileURL == nil }) else { return nil }
        let record = cachedRecord(for: recordID, recordType: RecordType.scratchTab.rawValue)
        record["name"] = tab.name as CKRecordValue
        record["content"] = tab.content as CKRecordValue
        record["language"] = tab.language as CKRecordValue
        record["languageLocked"] = (tab.languageLocked ? 1 : 0) as CKRecordValue
        record["lastModified"] = tab.lastModified as CKRecordValue
        return record
    }

    private func buildClipboardEntryRecord(id: UUID, recordID: CKRecord.ID) -> CKRecord? {
        guard let entry = ClipboardStore.shared.entries.first(where: { $0.id == id }) else { return nil }
        let record = cachedRecord(for: recordID, recordType: RecordType.clipboardEntry.rawValue)
        record["text"] = entry.text as CKRecordValue
        record["timestamp"] = entry.timestamp as CKRecordValue
        return record
    }

    // MARK: - Incoming changes

    private func applyFetchedChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        logger.debug("applyFetchedChanges: \(event.modifications.count) modifications, \(event.deletions.count) deletions")
        for modification in event.modifications {
            let record = modification.record
                        cacheRecordSystemFields(record)

            switch record.recordType {
            case RecordType.scratchTab.rawValue:
                applyScratchTabRecord(record)
            case RecordType.clipboardEntry.rawValue:
                applyClipboardEntryRecord(record)
            default:
                logger.warning("Unknown record type: \(record.recordType)")
            }
        }

        for deletion in event.deletions {
            let id = deletion.recordID.recordName
            removeRecordMetadata(for: deletion.recordID)

            guard let uuid = UUID(uuidString: id) else { continue }

            switch deletion.recordType {
            case RecordType.scratchTab.rawValue:
                TabStore.shared.removeCloudTab(id: uuid)
            case RecordType.clipboardEntry.rawValue:
                ClipboardStore.shared.removeCloudClipboardEntry(id: uuid)
            default:
                break
            }
        }
    }

    private func applyScratchTabRecord(_ record: CKRecord) {
        guard let name = record["name"] as? String,
              let content = record["content"] as? String,
              let language = record["language"] as? String,
              let lastModified = record["lastModified"] as? Date else {
            logger.error("Malformed ScratchTab record: \(record.recordID)")
            return
        }
        let languageLocked = (record["languageLocked"] as? Int64 ?? 0) != 0
        guard let uuid = UUID(uuidString: record.recordID.recordName) else { return }

        let tabRecord = CloudTabRecord(
            id: uuid,
            name: name,
            content: content,
            language: language,
            languageLocked: languageLocked,
            lastModified: lastModified
        )
        logger.debug("applyTab: id=\(uuid.uuidString.prefix(8))")
        TabStore.shared.applyCloudTab(tabRecord)
    }

    private func applyClipboardEntryRecord(_ record: CKRecord) {
        guard let text = record["text"] as? String,
              let timestamp = record["timestamp"] as? Date else {
            logger.error("Malformed ClipboardEntry record: \(record.recordID)")
            return
        }
        guard let uuid = UUID(uuidString: record.recordID.recordName) else { return }

        logger.debug("applyClipboardEntry: id=\(uuid.uuidString.prefix(8))")
        let clipboardRecord = CloudClipboardRecord(id: uuid, text: text, timestamp: timestamp)
        ClipboardStore.shared.applyCloudClipboardEntry(clipboardRecord)
    }

    // MARK: - Conflict resolution

    /// Returns true when the local version won and must be re-uploaded.
    /// When the server wins, the record must NOT be re-queued: the server
    /// content is applied locally, and re-saving would push the stale local
    /// copy back up with a fresh change tag, reverting the newer server edit.
    private func resolveTabConflict(local record: CKRecord, server serverRecord: CKRecord) -> Bool {
        let localModified = record["lastModified"] as? Date ?? .distantPast
        let serverModified = serverRecord["lastModified"] as? Date ?? .distantPast

        if localModified > serverModified {
            // Local wins: adopt the server's change tag and re-push local fields
            serverRecord["name"] = record["name"]
            serverRecord["content"] = record["content"]
            serverRecord["language"] = record["language"]
            serverRecord["languageLocked"] = record["languageLocked"]
            serverRecord["lastModified"] = record["lastModified"]
            cacheRecordSystemFields(serverRecord)
            return true
        } else {
            // Server wins: accept server version
            cacheRecordSystemFields(serverRecord)
            applyScratchTabRecord(serverRecord)
            return false
        }
    }

    private func resolveClipboardConflict(local record: CKRecord, server serverRecord: CKRecord) {
        // Clipboard entries are append-only; server wins
        cacheRecordSystemFields(serverRecord)
        applyClipboardEntryRecord(serverRecord)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncEngine: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run {
            processEvent(event, syncEngine: syncEngine)
        }
    }

    @MainActor
    private func processEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let stateUpdate):
            saveStateSerialization(stateUpdate.stateSerialization)

        case .accountChange(let accountChange):
            handleAccountChange(accountChange)

        case .fetchedDatabaseChanges(let event):
            handleFetchedDatabaseChanges(event)

        case .fetchedRecordZoneChanges(let event):
            applyFetchedChanges(event)

        case .sentRecordZoneChanges(let event):
            handleSentRecordZoneChanges(event)

        case .sentDatabaseChanges(let event):
            for failedZone in event.failedZoneSaves {
                logger.error("Failed zone save: code=\(failedZone.error.code.rawValue) \(failedZone.error.localizedDescription)")
            }

        case .didFetchChanges:
            TabStore.shared.lastICloudSync = Date()

        case .didSendChanges:
            TabStore.shared.lastICloudSync = Date()

        case .willFetchChanges, .willSendChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }

        // Snapshot record content on the main actor – TabStore/ClipboardStore
        // and recordMetadata are main-thread state
        let records: [CKRecord.ID: CKRecord] = await MainActor.run {
            var map = [CKRecord.ID: CKRecord]()
            for change in changes {
                guard case .saveRecord(let recordID) = change,
                      let uuid = UUID(uuidString: recordID.recordName) else { continue }
                if let record = buildScratchTabRecord(id: uuid, recordID: recordID)
                    ?? buildClipboardEntryRecord(id: uuid, recordID: recordID) {
                    map[recordID] = record
                }
            }
            return map
        }

        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            if let record = records[recordID] {
                return record
            }
            // Record no longer exists locally; remove from pending
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        return batch
    }

    // MARK: - Event handlers

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signIn:
            syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            reuploadAllRecords()

        case .switchAccounts:
            clearLocalCloudState()

        case .signOut:
            clearLocalCloudState()

        @unknown default:
            break
        }
    }

    private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in event.deletions {
            if deletion.zoneID == zoneID {
                clearLocalCloudState()
            }
        }
    }

    private func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        var newPendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
        var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()

        for savedRecord in event.savedRecords {
            cacheRecordSystemFields(savedRecord)
        }

        for failedSave in event.failedRecordSaves {
            let failedRecord = failedSave.record
            logger.error("Failed to save \(failedRecord.recordType) \(failedRecord.recordID.recordName): code=\(failedSave.error.code.rawValue)")

            switch failedSave.error.code {
            case .serverRecordChanged:
                guard let serverRecord = failedSave.error.serverRecord else { continue }

                switch failedRecord.recordType {
                case RecordType.scratchTab.rawValue:
                    if resolveTabConflict(local: failedRecord, server: serverRecord) {
                        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                    }
                case RecordType.clipboardEntry.rawValue:
                    // Server wins, entries are immutable – nothing to re-push
                    resolveClipboardConflict(local: failedRecord, server: serverRecord)
                default:
                    break
                }

            case .zoneNotFound:
                let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                newPendingDatabaseChanges.append(.saveZone(zone))
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                removeRecordMetadata(for: failedRecord.recordID)

            case .unknownItem:
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                removeRecordMetadata(for: failedRecord.recordID)

            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled:
                break

            default:
                logger.error("Unhandled save error: \(failedSave.error)")
            }
        }

        if !newPendingDatabaseChanges.isEmpty {
            syncEngine?.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
        }
        if !newPendingRecordZoneChanges.isEmpty {
            syncEngine?.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
        }
    }

    // MARK: - Helpers

    private func reuploadAllRecords() {
        let tabChanges: [CKSyncEngine.PendingRecordZoneChange] = TabStore.shared.tabs
            .filter { $0.fileURL == nil }
            .map { .saveRecord(CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID)) }

        let clipboardChanges: [CKSyncEngine.PendingRecordZoneChange] = ClipboardStore.shared.entries
            .map { .saveRecord(CKRecord.ID(recordName: $0.id.uuidString, zoneID: zoneID)) }

        logger.info("Re-uploading \(tabChanges.count) tabs, \(clipboardChanges.count) clipboard entries")
        syncEngine?.state.add(pendingRecordZoneChanges: tabChanges + clipboardChanges)
    }

    private func clearLocalCloudState() {
        recordMetadata.removeAll()
        saveRecordMetadata()
        try? FileManager.default.removeItem(at: stateURL)
    }

    private static let hasCloudKitEntitlement: Bool = {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }()
}

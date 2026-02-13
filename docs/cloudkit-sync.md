# CloudKit sync

Both the macOS and iOS itsypad apps sync data via CloudKit using `CKSyncEngine` (macOS 14+ / iOS 17+). This replaces the previous `NSUbiquitousKeyValueStore` approach, which had a 1MB total limit and required full-data rewrites on every change.

- **Container:** `iCloud.com.nickustinov.itsypad` (private database)
- **Zone:** `ItsypadData` (single custom zone for both record types)
- **Toggle:** `SettingsStore.icloudSync` (persisted in `UserDefaults`)


## Record types

| Record type | Fields | Notes |
|---|---|---|
| `ScratchTab` | `name` (String), `content` (String), `language` (String), `languageLocked` (Int64, 0/1), `lastModified` (Date) | recordName = tab UUID |
| `ClipboardEntry` | `text` (String), `timestamp` (Date) | recordName = entry UUID |

Only scratch tabs (no `fileURL`) are synced. Only text clipboard entries are synced (not images).


## Architecture

### CKSyncEngine

`CKSyncEngine` (introduced at WWDC23) handles:
- Change token management and persistence
- Automatic subscription creation for push notifications
- Batching, retries, and throttling
- Scheduling sync operations

We implement two delegate methods:
- `handleEvent(_:syncEngine:)` – react to fetched changes, push results, state updates, account changes
- `nextRecordZoneChangeBatch(_:syncEngine:)` – provide dirty records to push

### CloudSyncEngine (app-level coordinator)

`CloudSyncEngine` is a singleton that wraps `CKSyncEngine` and coordinates between the stores and CloudKit.

```swift
final class CloudSyncEngine {
    static let shared = CloudSyncEngine()
    func start()               // Creates CKSyncEngine, begins syncing
    func stop()                // Tears down CKSyncEngine, clears metadata
    func startIfEnabled()      // Calls start() if SettingsStore.icloudSync is true
    func recordChanged(_ id: UUID, type: RecordType)  // Queue record for push
    func recordDeleted(_ id: UUID, type: RecordType)   // Queue deletion for push
    enum RecordType { case scratchTab, clipboardEntry }
}
```

### Data models for incoming changes

```swift
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
```


## Sync flow

### Local change → cloud (push)

1. `TabStore`/`ClipboardStore` modifies data locally
2. Store calls `CloudSyncEngine.shared.recordChanged(id, type:)` or `.recordDeleted(id, type:)`
3. `CloudSyncEngine` adds to `pendingRecordZoneChanges`
4. `CKSyncEngine` schedules push automatically
5. Engine calls `nextRecordZoneChangeBatch` – we build a `CKRecord` from current local data
6. On success: cache server record system fields for future conflict detection

### Cloud change → local (pull)

1. `CKSyncEngine` receives push notification or fetches changes
2. `handleEvent(.fetchedRecordZoneChanges)` fires with modified/deleted records
3. For modifications: call `TabStore.applyCloudTab()` or `ClipboardStore.applyCloudClipboardEntry()`
4. For deletions: call `TabStore.removeCloudTab()` or `ClipboardStore.removeCloudClipboardEntry()`
5. UI updates via `@Published` properties

### Conflict resolution

**Tabs (last-write-wins):**
1. Push fails with `serverRecordChanged` error
2. Compare `lastModified` dates between local and server records
3. If local is newer: copy local fields onto server record, re-queue push
4. If server is newer: accept server version, update local store

**Clipboard (server-wins):**
- Clipboard entries are append-only – conflicts are rare
- If same UUID conflicts: server wins


## State persistence

`CKSyncEngine` emits `.stateUpdate` events with serialized state (change tokens, pending changes). Persisted at:
- `~/Library/Application Support/Itsypad/cloud-sync-state.data`

Local cache of `CKRecord` system fields (for conflict detection):
- `~/Library/Application Support/Itsypad/cloud-record-metadata.json`


## Integration points in stores

### TabStore

| Action | Method called |
|---|---|
| New scratch tab | `CloudSyncEngine.shared.recordChanged(id, type: .scratchTab)` |
| Content update (scratch tab) | `CloudSyncEngine.shared.recordChanged(id, type: .scratchTab)` |
| Language update (scratch tab) | `CloudSyncEngine.shared.recordChanged(id, type: .scratchTab)` |
| Close scratch tab | `CloudSyncEngine.shared.recordDeleted(id, type: .scratchTab)` |
| Incoming cloud tab | `TabStore.applyCloudTab(_ data: CloudTabRecord)` |
| Incoming cloud deletion | `TabStore.removeCloudTab(id: UUID)` |

### ClipboardStore

| Action | Method called |
|---|---|
| New text entry | `CloudSyncEngine.shared.recordChanged(id, type: .clipboardEntry)` |
| Delete entry | `CloudSyncEngine.shared.recordDeleted(id, type: .clipboardEntry)` |
| Clear all | `CloudSyncEngine.shared.recordDeleted` for each entry |
| Prune expired | `CloudSyncEngine.shared.recordDeleted` for each pruned entry |
| Incoming cloud entry | `ClipboardStore.applyCloudClipboardEntry(_ data: CloudClipboardRecord)` |
| Incoming cloud deletion | `ClipboardStore.removeCloudClipboardEntry(id: UUID)` |


## Entitlements

Both entitlements files need:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.nickustinov.itsypad</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

The old `com.apple.developer.ubiquity-kvstore-identifier` key can be removed.


## What to remove from iOS (migrating from KVS)

- All `NSUbiquitousKeyValueStore` references
- `ClipboardCloudEntry` struct
- Tombstone sets (`deletedTabIDs`, `deletedClipboardIDs`)
- `saveTabsToCloud()`, `mergeCloudTabs()`, `clearCloudData()`
- `saveClipboardToCloud()`, `mergeCloudClipboard()`, `clearCloudClipboardData()`
- `syncDeletedIDs()`, `loadDeletedIDs()`
- `maxCloudEntries` cap (no longer needed – CloudKit has no practical size limit)
- `KeyValueStoreProtocol` and its `NSUbiquitousKeyValueStore` extension
- `didChangeExternallyNotification` observer for KVS

## What to add for iOS

- `CloudSyncEngine` singleton (can share the macOS implementation directly)
- `CloudTabRecord` and `CloudClipboardRecord` data types
- `applyCloudTab()` / `removeCloudTab()` on TabStore
- `applyCloudClipboardEntry()` / `removeCloudClipboardEntry()` on ClipboardStore
- `recordChanged()` / `recordDeleted()` calls at each store mutation point
- CloudKit entitlements (container identifiers + services)
- Call `CloudSyncEngine.shared.startIfEnabled()` at app launch


## Key improvements over KVS

| | KVS (old) | CloudKit (new) |
|---|---|---|
| **Size limit** | 1MB total | No practical limit |
| **Sync granularity** | Full rewrite of all data | Per-record incremental |
| **Deletions** | Manual tombstones (grow forever) | Native CloudKit deletions |
| **Clipboard cap** | 200 entries (to fit in 1MB) | 1000 entries (app limit) |
| **Conflict resolution** | Manual merge on full data | Per-record with server metadata |
| **Push notifications** | `didChangeExternallyNotification` | Automatic CKSyncEngine subscriptions |

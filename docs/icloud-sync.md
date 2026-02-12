# iCloud sync

Both the macOS and iOS itsypad apps sync data via `NSUbiquitousKeyValueStore` (iCloud key-value storage). They share the same KVS container via matching entitlements:

- **KVS identifier:** `R892A93W42.com.nickustinov.itsypad`
- **Toggle:** `SettingsStore.icloudSync` (persisted in `UserDefaults`)


## Keys

| Key | Format | Max entries | Used by |
|---|---|---|---|
| `tabs` | `[TabData]` | unbounded | macOS, iOS |
| `deletedTabIDs` | `[String]` (UUID strings) | grows with deletes | macOS, iOS |
| `clipboard` | `[ClipboardCloudEntry]` | 200 | macOS, iOS |
| `deletedClipboardIDs` | `[String]` (UUID strings) | grows with deletes | macOS, iOS |


## Data models

### Tabs (`TabData`)

Full tab state: id, name, content, language, fileURL, languageLocked, isDirty, cursorPosition, lastModified. Only scratch tabs (no `fileURL`) are synced.

### Clipboard (`ClipboardCloudEntry`)

Text-only subset of clipboard data:

```swift
struct ClipboardCloudEntry: Codable {
    let id: UUID
    let text: String
    let timestamp: Date  // default JSONEncoder Date encoding (Double)
}
```

The macOS `ClipboardEntry` also supports images, but only text entries are synced to iCloud.


## Sync architecture

### macOS

The macOS app has a dedicated `ICloudSyncManager` singleton that owns the `NSUbiquitousKeyValueStore` reference and coordinates all sync.

**Clipboard write flow:**
1. Pasteboard monitor detects change (polled every 0.5s)
2. `ClipboardStore.insertEntry()` adds entry, calls `scheduleSave()` (1s debounce)
3. `saveEntries()` writes local JSON, then calls `ICloudSyncManager.shared.saveClipboard()`
4. `saveClipboard()` calls `ClipboardStore.saveClipboardToCloud(cloudStore)` which encodes all text entries (prefix 200) to the `"clipboard"` key
5. `cloudStore.synchronize()`

**Key detail:** macOS rewrites the *entire* clipboard cloud data on every save. This means delete and clear naturally sync – the cloud always reflects the current macOS local state.

**Tab write flow:**
1. Tab content changes → `scheduleSave()` (1s debounce)
2. `saveSession()` writes local JSON, then calls `ICloudSyncManager.shared.saveTabs()`
3. `saveTabs()` calls `TabStore.saveTabsToCloud(cloudStore)` which encodes scratch tabs, preserving unknown cloud tabs, to the `"tabs"` key

**Read flow (both tabs and clipboard):**
- On `start()`: `synchronize()`, then `mergeCloudTabs` + `mergeCloudClipboard`
- On `didChangeExternallyNotification`: `mergeCloudTabs` + `mergeCloudClipboard`
- On `check()` (app foreground): same as start

**Merge logic (clipboard):** Loads tombstones from `"deletedClipboardIDs"`, removes tombstoned local entries (including image files), then inserts new cloud entries by UUID (skipping tombstoned ones). Posts `didChangeNotification` so the UI redraws.

### iOS

The iOS app piggybacks clipboard sync onto `TabStore`'s existing iCloud observer, since it already handles `didChangeExternallyNotification`. There is no separate sync manager.

**Clipboard read flow:**
- On `startICloudSync()`: calls `ClipboardStore.shared.mergeCloudClipboard(from: cloudStore)`
- On `didChangeExternallyNotification`: same
- On `checkICloud()` (app foreground): same
- On retry delays (2s, 5s, 10s after start): same

**Merge logic:** Loads tombstones from `"deletedClipboardIDs"`, removes tombstoned local entries, then inserts new cloud entries by UUID (skipping tombstoned ones). Updates `@Published entries` so the UI redraws in real time.

**Clipboard write flow:**
- `captureFromPasteboard()` (Paste button): appends new entry to cloud, preserving existing cloud data
- `deleteEntry()`: adds ID to `deletedClipboardIDs` tombstones, rewrites cloud with current local entries (up to 200)
- `clearAll()`: tombstones all local + cloud entry IDs into `deletedClipboardIDs`, removes the `"clipboard"` cloud key


## Action comparison

| Action | macOS | iOS |
|---|---|---|
| **New clipboard entry** | Rewrite all 200 to cloud | Append single entry to cloud |
| **Delete single entry** | Tombstone ID + rewrite cloud without deleted | Tombstone ID + rewrite cloud without deleted |
| **Clear all** | Tombstone all IDs + rewrite cloud without deleted | Tombstone all IDs + remove cloud key |
| **Merge from cloud** | Load tombstones, remove tombstoned locals, insert non-tombstoned cloud entries | Load tombstones, remove tombstoned locals, insert non-tombstoned cloud entries |
| **Tab save** | Also saves clipboard to cloud | Does NOT save clipboard to cloud |


## Known limitations

### No conflict resolution for clipboard

Unlike tabs (which use `lastModified` timestamps for conflict resolution), clipboard entries are append-only by UUID. If the same UUID exists locally, it's skipped – no content comparison or update.

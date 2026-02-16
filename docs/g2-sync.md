# G2 sync

Notes sync between the Itsypad macOS/iOS app and the G2 glasses app, via a Vercel-hosted API with Redis Cloud as the data store.


## Why not CloudKit directly?

The G2 app is a web page running inside Even's WebView (Flutter `InAppWebView` on iPhone). CloudKit JS requires Apple ID sign-in in the browser, which is impractical inside a third-party WebView. CloudKit remains the sync mechanism for native apps (macOS ↔ iOS). The G2 path is a separate, simpler sync layer.


## How Even Hub apps work

Even Hub apps are web apps loaded inside the Even App's WebView on the user's iPhone. There is no standalone server – the web page communicates with the G2 glasses over BLE through a JS bridge injected by the Even App.

```
[G2 web app]  <--JS bridge-->  [Even App (Flutter/iPhone)]  <--BLE-->  [G2 Glasses]
```

- The web app is a static site hosted on Vercel
- It imports `@evenrealities/even_hub_sdk` for bridge communication
- All rendering happens on the glasses via container-based UI (text, list, image containers)
- Audio (microphone PCM) streams from the glasses through the bridge to the web app
- The web app has access to `localStorage`, `fetch`, and standard web APIs
- No access to native iOS APIs, no iCloud, no Keychain

For development, the Even Hub simulator loads the app from localhost. For production, the Even App loads the hosted URL.


## Architecture overview

```
Itsypad macOS/iOS              Vercel (API + Redis)           G2 web app
─────────────────              ────────────────────           ──────────
                                                              Hosted on Vercel as
                                                              static site (Even Hub
                                                              loads this URL)

Enable "Even G2 sync"
Generate pairing code
POST /api/pair ──────────►  Store in Redis (5 min TTL)
Display code to user
                                                        User enters code
                                              POST /api/link ◄────────
                                              Validate, return token ────────►
                                                        Store token in localStorage

On note change:
PUT /api/notes ──────────►  Store in Redis
                                              GET /api/notes ◄────────
                                              Return notes ────────────────►
                                                        Render on glasses

                                                        Voice note recorded:
                                              POST /api/notes ◄────────
                            Store in Redis ◄──
GET /api/notes ◄──────────  Return notes
Update local store
```


## Pairing flow

### 1. macOS/iOS app generates a code

When the user enables "Even G2 sync" in Itsypad settings:

1. Generate a 6-character alphanumeric code (uppercase, e.g. `AX73NA`)
2. Generate a random session secret
3. Call `POST /api/pair`:
   ```json
   {
     "code": "AX73NA",
     "deviceId": "<stable device identifier>",
     "secret": "<random secret>"
   }
   ```
4. Server stores the device secret and pairing code in Redis with a 5-minute TTL:
   ```
   device:<deviceId>:secret → <secret>
   pair:AX73NA → { deviceId, createdAt }   (TTL 300s)
   ```
5. Display the code to the user

### 2. G2 web app links with the code

User enters the code in the settings panel on the web page:

1. Call `POST /api/link`:
   ```json
   { "code": "AX73NA" }
   ```
2. Server validates the code exists in Redis and hasn't expired
3. Generate a session token (64-char hex string from 32 random bytes)
4. Store session in Redis (no TTL – persistent until revoked):
   ```
   session:<token> → { deviceId, createdAt }
   device:<deviceId>:session → <token>
   ```
5. Delete the pairing code from Redis
6. Return the session token to the G2 web app
7. G2 web app stores the token in `localStorage` key `itsypad:session-token`

### 3. macOS/iOS app confirms the link

After calling `POST /api/pair`, the native app polls `GET /api/pair/status` with `Authorization: Bearer <deviceId>:<secret>` until the link is confirmed (session exists for that device) or the code expires.


## Data model

### Note record

```json
{
  "id": "<UUID>",
  "name": "Shopping list",
  "content": "- Milk\n- Eggs\n- Bread",
  "lastModified": "2026-02-15T10:30:00Z"
}
```

Only scratch tabs (no file-backed tabs) are synced. No clipboard entries – G2 has no clipboard UI.

### Redis key layout

| Key | Value | TTL |
|---|---|---|
| `pair:<code>` | `{ deviceId, createdAt }` | 5 min |
| `device:<deviceId>:secret` | `<secret string>` | None |
| `device:<deviceId>:session` | `<session token>` | None |
| `session:<token>` | `{ deviceId, createdAt }` | None |
| `notes:<deviceId>` | `{ notes: Note[], version: number }` | None |

All values are stored as JSON strings.


## Sync protocol

### Push from macOS/iOS

When a note is created, edited, or deleted in Itsypad:

```
PUT /api/notes
Authorization: Bearer <deviceId>:<secret>
Content-Type: application/json

{
  "notes": [ ...all scratch tabs... ],
  "version": 42
}
```

The native app pushes the full set of scratch tabs on every change. This is simpler than incremental sync – the note count is small (typically under 100), and the total payload is well within Vercel's limits.

Version is a monotonically increasing counter. The server rejects pushes with a version lower than or equal to what's stored (409 Conflict with `currentVersion` in body).

### Pull from G2

The G2 web app fetches notes on connect and periodically:

```
GET /api/notes
Authorization: Bearer <session_token>
```

Response:
```json
{
  "notes": [ ...notes... ],
  "version": 42
}
```

The G2 app replaces its in-memory store with the fetched notes and re-renders the list if the version changed.

### Push from G2 (voice notes)

When the user records a voice note on G2:

1. Audio streams from G2 glasses → web app via bridge
2. Web app sends PCM to Soniox for transcription
3. When recording stops, the transcribed text becomes a new note
4. Web app calls:
   ```
   POST /api/notes
   Authorization: Bearer <session_token>
   Content-Type: application/json

   {
     "note": {
       "id": "<generated UUID>",
       "name": "Note 3:45 PM",
       "content": "Transcribed text here",
       "lastModified": "2026-02-15T15:45:00Z"
     }
   }
   ```
5. Server appends the note to the stored notes array, increments version
6. macOS/iOS app picks it up on next poll

### Polling

- G2 web app: polls `GET /api/notes` every 30 seconds while connected
- macOS/iOS app: polls `GET /api/notes` every 30 seconds while G2 sync is enabled

Polling is simple and sufficient for this use case. The note count is small and changes are infrequent. WebSocket or SSE can be added later if needed.


## Live refresh on G2

When the G2 app fetches updated notes and the user is currently viewing a note that changed:

1. Compare fetched version with local version
2. If version changed, update in-memory store
3. If the currently viewed note was modified, re-render the content screen with updated text
4. If the currently viewed note was deleted, return to the list screen
5. If on the list screen, re-render the list with updated names


## Security

- **Pairing codes** expire after 5 minutes – cannot be brute-forced in time
- **Session tokens** are 256-bit random (64 hex chars) – computationally infeasible to guess
- **All traffic** over HTTPS (Vercel enforces this)
- **No API keys in the browser** – the session token is the only credential, scoped to one device's notes
- **Revocation** – the macOS/iOS app can call `DELETE /api/session` to revoke the G2 link
- **Device secret** – the native app authenticates with `Authorization: Bearer <deviceId>:<secret>`. The G2 web app uses a separate session token. G2 can only read notes and append voice notes – it cannot overwrite or delete existing notes.


## API routes

All routes are in `itsypad-app` (the itsypad.app Next.js project), under `src/app/api/`.

| Method | Route | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/pair` | None (registers device secret) | Register pairing code |
| `GET` | `/api/pair/status` | `Bearer <deviceId>:<secret>` | Check if G2 has linked |
| `POST` | `/api/link` | None (validates pairing code) | Exchange code for session token |
| `PUT` | `/api/notes` | `Bearer <deviceId>:<secret>` | Push full note set from native app |
| `GET` | `/api/notes` | `Bearer <session_token>` | Fetch notes for G2 |
| `POST` | `/api/notes` | `Bearer <session_token>` | Append voice note from G2 |
| `DELETE` | `/api/session` | `Bearer <deviceId>:<secret>` | Revoke G2 link |


## Implementation

### itsypad-app (Next.js on Vercel)

The API is implemented in the existing `itsypad-app` repo (itsypad.app landing page + API).

```
src/
├── lib/
│   ├── redis.ts       # ioredis client, reads REDIS_URL from env
│   ├── auth.ts        # Bearer parsing, session/device validation helpers
│   └── crypto.ts      # Token generation (crypto.getRandomValues)
└── app/api/
    ├── pair/
    │   ├── route.ts       # POST – register pairing code
    │   └── status/
    │       └── route.ts   # GET – check link status
    ├── link/
    │   └── route.ts       # POST – exchange code for session token
    ├── notes/
    │   └── route.ts       # GET/PUT/POST – note sync
    └── session/
        └── route.ts       # DELETE – revoke session
```

**Dependencies:** `ioredis` for Redis access.

**Environment variables:**
- `REDIS_URL` – Redis Cloud connection string (set in `.env.local` for dev, Vercel env vars for production)

### Redis Cloud

Using Redis Cloud (redislabs.com) as the data store. Standard Redis protocol over TCP. The `ioredis` client connects using the `REDIS_URL` connection string.


### G2 web app (itsypad-even-g2)

- Replace mock `store.ts` with a sync client that fetches from `/api/notes`
- Add polling loop (30s interval) in `app.ts`
- On voice note save, `POST /api/notes` instead of adding to local array
- Handle live refresh when notes change while viewing
- Session token management in `localStorage`

### Itsypad macOS

- Add "Even G2 sync" toggle in settings (General tab)
- Pairing code generation and display UI
- Push notes to `/api/notes` on every scratch tab change (if G2 sync enabled)
- Poll for voice notes from G2
- Unpair action (revoke session)

### Itsypad iOS (future)

- Same as macOS – toggle, pairing code, push/poll, unpair


## Limitations

- Notes are stored unencrypted in Redis – acceptable for a scratch pad, but worth revisiting if sensitive data is expected
- Polling introduces up to 30s delay – adequate for note sync, not for real-time collaboration
- No offline queue on G2 – if the phone has no network when a voice note is saved, it's lost. Could add localStorage buffering later
- Full note set push means the native app must send all scratch tabs on every change – fine for <100 notes, would need incremental sync if note count grows significantly

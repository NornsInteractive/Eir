# MVP API contract (business owner)

Public import for UI: `package:eir/core/room_session.dart`.

This file describes the REAL implemented API. Names and constructor shapes
previously consumed by the UI are preserved; new members are additive.

## Exports through `package:eir/core/room_session.dart`

- `RoomSession`, `RoomRole`, `RoomConnectionState`, `PlaybackMode`
- `DeviceIdentityInfo`, `RoomMember`, `MemberTelemetry`, `PlaylistItem`, `PlaybackState`
- `SignalingClient`
- `DeviceIdentity`, `DeviceIdentityStore`, `SecureKeyValueStore`,
  `InMemorySecureKeyValueStore`, `FlutterSecureStorageStore`, `IdentityStoreCorrupted`
- `XFile` (re-exported from `package:cross_file/cross_file.dart`)

`package:eir/models.dart` re-exports the same model names for UI convenience.

## RoomSession (ChangeNotifier)

```dart
class RoomSession extends ChangeNotifier {
  RoomSession({
    DeviceIdentityStore? identityStore,   // default: FlutterSecureStorage-backed
    SignalingClient? signaling,           // default: WebSocket client
    Player? player,                       // optional injected media_kit Player (tests)
    String? Function(String url)? urlProbe, // optional probe override (tests); returns null on success or a stable error code
  });

  DeviceIdentityInfo get identity;
  RoomConnectionState get connectionState;   // disconnected | connecting | connected | reconnecting
  String? get roomId;
  String? get inviteText;                    // signed, single-use invite (opaque, copy/share)
  RoomRole get role;                         // owner | admin | member
  List<RoomMember> get members;              // RoomMember{deviceId, displayName, role, online}
  List<PlaylistItem> get playlist;           // PlaylistItem{itemId, title, sourceType, url, localMediaId, duration, sizeBytes}
  String? get currentItemId;
  PlaybackState get playback;                // see below
  String? get lastErrorCode;                 // stable codes below, null when healthy
  Map<String, MemberTelemetry> get memberTelemetry;   // live position/buffering/seq per deviceId
  bool get peerVerified;                     // DTLS-fingerprint-bound handshake completed
  Player get player;                         // owned by this session; UI must NOT dispose

  // Local-media cache occupancy + safe clear (settings UI).
  MediaCacheTelemetrySnapshot? get cacheTelemetry;
  int get cacheUsedBytes;                    // cachedBytes, 0 if no media service
  int get cacheMaxBytes;                     // maxBytes, fallback kMediaMaxCacheBytes
  Future<int> clearUnprotectedCache();      // bytes freed; safe while playing

  // Manual retry: reuse reconnect, keep room/identity/playback, de-dupe, no-op
  // when connected. Auto-retry exhaustion is terminal (disconnected); a failed
  // retry also returns to disconnected with 'signaling_unavailable'.
  Future<void> retry();

  Future<void> init();                       // MediaKit.ensureInitialized + device identity load
  Future<void> setSignalingUrl(String url);  // ws:// or wss:// only; throws ArgumentError otherwise

  Future<void> createRoom();
  Future<void> joinRoom(String inviteText);
  Future<void> leaveRoom();
  Future<void> closeRoom();                  // owner only; disbands the room for everyone

  Future<void> admitMember(String memberId);  // owner only
  Future<void> grantAdmin(String memberId);   // owner only
  Future<void> revokeAdmin(String memberId);  // owner only

  Future<void> addUrl(String url, {String? title});
  Future<void> pickAndAddLocalFile();         // file_selector MP4/M4V/MOV picker
  Future<void> addLocalFile(XFile file, {String? title});  // P2P media plane lands in the local slice
  Future<void> removeItem(String itemId);
  Future<void> reorderItem(String itemId, int newIndex);
  Future<void> replaceItem(String itemId, {String? url, XFile? file});
  Future<void> switchItem(String itemId);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);

  @override
  void dispose();
}
```

## Semantics

- Call `setSignalingUrl` (ws/wss), then `createRoom()` or `joinRoom(inviteText)`.
- Room creation makes the caller the owner. The invite is a signed opaque
  string: `eir:v1:<base64url(payload)>.<base64url(signature)>`; it pins the
  signaling URL, roomId, sessionId, invite epoch, token, owner public key,
  genesis hash and expiry. Token is high-entropy (256 bits); invites expire
  after 72 hours by default.
- `inviteText` may be null until `createRoom()` completes.
- Playback/list/ACL changes flow: control request -> owner commit (signed,
  sequenced, prevHash-chained) -> both sides apply. Members cannot act unless
  their ACL role is admin. There is NO local authoritative mutation before
  the commit is applied.
- `peerVerified` becomes true only after both sides signed each other's
  challenge AND the actual DTLS certificate fingerprints (from `getStats()`)
  matched. Business data flows only after that.
- `connectionState == reconnecting` keeps an open data channel alive when the
  signaling socket drops; signaling re-join uses the same device identity.
  On a signaling restart (room lost) the owner re-registers on the **same URL**,
  rotates the invite epoch (old invites → `invalid_invite`), and keeps a
  surviving data channel. `retry()` triggers the same path manually.
- `addUrl` accepts HTTPS (and loopback HTTP). HTML pages are rejected. HLS is
  classified (`url_probe_io.dart`): VOD (`EXT-X-ENDLIST`, unencrypted) allowed;
  live, encrypted/DRM, and unresolvable master playlists rejected with
  `unsupported_media`; master variants followed at most one level, http(s) only.
  Web cannot pre-probe cross-origin media (CORS) — it validates scheme only and
  surfaces real player errors via `media_probe_failed`.
- `closeRoom()` (owner) publishes a signed `room_close` commit and disbands the
  room on the signaling server; all peers reset to `disconnected`.
- `memberTelemetry` carries `{itemId, itemSeq, positionMs, buffering, sharedMs}`
  per device — refreshes every 2s, verified as signed messages.
- Seek while paused updates position; play/pause/seek wait for the commit to be
  applied (owner: immediately; member: up to 8s, then `commit_rejected`).

## Reconnect and manual retry

- Automatic reconnect is bounded: 1.1 s / 2.1 s / 4.2 s, three attempts.
  `connectionState` is `reconnecting` while a surviving data channel is kept
  open.
- When the three attempts are exhausted the session enters a real terminal
  state: `connectionState == disconnected` and
  `lastErrorCode == 'signaling_unavailable'`. No further automatic attempts
  are made — a restarted server does **not** silently revive the session, and
  late socket callbacks cannot restart the loop. Room id, identity, playlist,
  playback state and a surviving data channel are retained.
- `retry()` is the manual equivalent and is the only way out of that state.
  It is a no-op when already `connected` and de-duplicates concurrent calls
  (`_retryInFlight`). It requires a room, a signaling URL and a loaded
  identity; otherwise it sets `lastErrorCode = 'signaling_unavailable'`
  without changing the room.
- On success `retry()` returns to `connected` and clears the stale
  `signaling_unavailable` (other error codes are untouched). On failure it
  returns to `disconnected` with `signaling_unavailable`, so the retry entry
  stays reachable instead of being stuck in `reconnecting`.
- It keeps the room, identity, playlist and playback state — it never
  recreates the room and never repoints `signalingUrl`. The UI only needs to
  offer a button while `connectionState != connected`.
- Owner after a signaling restart: re-registers on the **same URL**, rotates
  the invite epoch (previously shared invites now fail with `invalid_invite`),
  and mints a new `inviteText`. A surviving data channel is kept.
- Member after the room is gone: retry ends in a bounded, explicit failure
  (`room_not_found` / `signaling_unavailable` / `invalid_invite`), keeps
  `peerVerified == false`, and does not fabricate commits or playlist state.
  A new invite from the owner is required.

## Source availability (mid-session)

- A DataChannel close only clears `peerVerified` and stops room timers; it
  does **not** reset the room. `roomId`, `playlist` and `currentItemId`
  survive, so already-cached local media keeps playing from the local cache.
- If a chunk the peer does not have is required after the source left, the
  session either surfaces `source_offline` (or `media_probe_failed` when the
  player fails) or waits — it never relays or fake-plays the missing bytes.
- While the owner/control channel is down, a member (even an admin) cannot
  produce a new shared commit: control calls fail explicitly
  (`signaling_unavailable` / `commit_rejected`), `playback.seq` does not
  advance, and natural end is **not** advanced by the member. Playback
  authority returns only when the owner is reachable again.

## Models

```dart
class DeviceIdentityInfo { final String deviceId; final String publicKeyBase64; }
class RoomMember { final String deviceId; final String displayName; final RoomRole role; final bool online; }
class MemberTelemetry { final String deviceId; final String? itemId; final int itemSeq; final int positionMs; final bool buffering; final int sharedMs; }
class PlaylistItem { final String itemId; final String title; final String sourceType; final String? url; final String? localMediaId; final Duration? duration; final int? sizeBytes; }
class PlaybackState {
  final String? itemId;
  final PlaybackMode mode;           // playing | paused
  final Duration position;           // position at anchorSharedMs
  final double rate;                 // rateMilli / 1000
  final DateTime effectiveAt;        // display only; do NOT use for sync
  final int seq;                     // commit sequence of this playback state
  final int anchorSharedMs;          // leader-monotonic ms anchor
  final int rateMilli;               // 1000 == 1.0x
  Duration expectedPositionAt(int sharedNowMs);
}
enum RoomRole { owner, admin, member }
enum RoomConnectionState { disconnected, connecting, connected, reconnecting }
enum PlaybackMode { playing, paused }
```

## Errors

`lastErrorCode` stable strings:

- `signaling_unavailable` — WS connect/rejoin failed or timed out
- `invalid_invite` — malformed, bad signature, stale epoch, committing mismatch
- `invite_expired` — invite past expiry
- `invite_consumed` — token already bound to a different device identity
- `room_full` — room at capacity (2 peers)
- `room_not_found` — room unknown (e.g. after disband or server restart)
- `unsupported_media` — URL scheme/type not allowed, file type rejected
- `media_probe_failed` — URL probe failed (ranged GET, 8s timeout), OR an async
  player/decode error surfaced after open (via `player.stream.error`; F1)
- `media_unavailable` — MediaKit failed to initialize
- `storage_full` — native cache write failed for lack of disk space (F5); the
  media service latches further disk writes and keeps serving cached bytes.
  `clearUnprotectedCache()` clears the latch and this code on success
- `identity_unavailable` — device identity could not be loaded/created at `init()`
- `stale_state` — (request denial reason) control request carried a `baseSeq` older than a view the peer already demonstrated (genuine regression / replay of a superseded request), OR a list-modifying action referenced an item no longer in the playlist. Requester resyncs via snapshot. Concurrent requests sent from the SAME fresh view share one `baseSeq` and are NOT stale-rejected.
- `permission_denied` — member without admin rights tried to control; owner-only action by non-owner
- `commit_rejected` — params invalid, commit timed out, or chain gap that could not be resynced
- `handshake_failed` — DTLS fingerprint/signature/challenge verification failed
- `protocol_violation` — unsigned/forged/malformed control traffic
- `chunk_hash_mismatch` — (local media slice) chunk SHA-256 mismatch
- `source_offline` — media source unreachable from this device

## Player ownership

`RoomSession.player` is owned and disposed by the session. UI may attach
`Video(controller: VideoController(session.player))` but must NOT dispose it.
Create the session, call `init()` before touching `.player`.

## URL rules

HTTPS is accepted anywhere; plain HTTP is accepted only for loopback hosts
(`localhost`, `127.0.0.1`, `::1`, `[::1]`). No `file://`, `data:` etc. Text/HTML
content types are rejected as `unsupported_media`. Web cannot read cross-origin
media responses (no CORS), so the Web build validates scheme only and relies on
media element errors — documented Web platform limitation.

## Local media (XFile)

`pickAndAddLocalFile()` uses `file_selector` (MP4/M4V/MOV filter).
`addLocalFile(XFile)` is implemented end-to-end through the local-media slice
(signed SHA-256 chunk manifests, bounded 16 KiB WebRTC frames with
backpressure, receive-side verify+cache). A non-source peer receives the
playlist entry immediately and streams the file over P2P on demand — it does
**not** need the full file before playback begins. This is proven by
`integration_test/room_session_streaming_proof_test.dart` with a ~65 MiB MP4:
the guest decodes and advances past 1 s of playback while fewer than the full
file bytes have crossed the DataChannel, and the large manifest travels via
the bounded `media_manifest_chunk` protocol (not inlined).

### Manifest transfer

- `add_local` commit carries a **compact source-signed root**:
  `manifestSource` + `manifestSignature` (domain `media_manifest`). The full
  manifest body is inlined only when `jsonEncode(manifestJson).length <=
  kMaxInlineManifestBytes` (8 KiB, `RoomSession.kMaxInlineManifestBytes`).
- When the manifest exceeds the inline bound (large files → many chunk hashes),
  the body is omitted from the commit. The receiver detects the missing
  manifest and sends a room-scoped `media_manifest_request`; the source answers
  with `media_manifest_chunk` frames (each bounded by `kMediaManifestChunkBytes`)
  reassembled and SHA-256-verified on arrival, then authorized against the
  signed commit's `manifestSource`.
- All media control frames (`media_manifest_request`, `media_range_request`,
  `media_manifest_chunk`, `media_error`, …) are room-scoped
  (`protocolVersion`/`roomId`/`sessionId`/`senderId`); an unscoped or
  wrong-room frame is dropped.

### V1 list/control constraints enforced

- **Playlist cap:** `kMaxPlaylistItems = 200`. An `add_url`/`add_local` beyond
  the cap is rejected as `commit_rejected`.
- **Remove current item (V1-PRD §6):** deleting the current item selects its
  former NEXT, pauses it, and keeps it loaded; only an empty list stops
  playback and clears the current item. Non-current deletes never interrupt
  playback.
- **Stale state rejection (V1-PRD §6):** `stale_state` is diagnosed two ways:
  (1) a control request whose `baseSeq` is *older than a view the peer has
  already demonstrated it holds* — a genuine regression or a replay of a
  superseded request (a per-peer high-water-mark `_peerBaseSeqHigh` tracks this,
  so two concurrent requests stamped with the same fresh `baseSeq` are NOT
  rejected); (2) a list-modifying action (`remove`/`reorder`/`replace`/
  `switch_item`) that references an item no longer in the current playlist.
  Playback controls (`play`/`pause`/`seek`/`rate`/`switch_item`) execute on the
  latest confirmed state and are never stale-rejected (V1-PRD §6: "play/pause/
  seek requests execute on the latest confirmed state").
- **Bounded control envelope:** incoming DataChannel text over
  `kMaxEnvelopeBytes` (64 KiB) is rejected as a protocol violation before any
  `jsonDecode`.
- **Identity init ordering:** `init()` loads/creates the device identity BEFORE
  constructing the media player, so a failed identity load is reported as
  `identity_unavailable` instead of leaking an uninitialized player.

## Local media cache API (occupancy + safe clear)

Intended for the settings UI (cache usage display + "clear" button). Reuses
the existing media-service cache; core introduces no separate management layer.

```dart
// null when the media service is not yet started; otherwise live snapshot.
MediaCacheTelemetrySnapshot? get cacheTelemetry;
int get cacheUsedBytes;        // == cacheTelemetry?.cachedBytes ?? 0
int get cacheMaxBytes;         // == cacheTelemetry?.maxBytes ?? kMediaMaxCacheBytes
// Evicts only unprotected (not actively played/sourced) chunks;
// returns bytes freed; safe to call while playing.
Future<int> clearUnprotectedCache();
```

`MediaCacheTelemetrySnapshot` fields: `cachedBytes`, `cachedChunks`, `hits`,
`misses`, `evictedBytes`, `maxBytes`.

## Invite / token handling

Room tokens are secret-ish. The UI should offer copy-to-clipboard for
`inviteText` but never log it. Invites bind one device identity on first use;
re-joining with the same identity is idempotent.

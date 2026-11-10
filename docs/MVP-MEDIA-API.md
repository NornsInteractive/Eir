# MVP Media API — Local-file P2P streaming subsystem

Owner: business/platform media worker (`lib/media/**`).
Public import for core/UI integration:

```dart
import 'package:eir/media/local_media_service.dart';
```

## 1. Model

Local files stream as **original container bytes** — no remux, no transcoding,
no server media and no container parser. Accepted containers are MP4, M4V, MOV,
MKV, WebM, AVI, TS, 3GP, OGV and FLV (`media_format.dart`; MIME resolved with
the `mime` package from the picker-declared type or the file extension). The
receiver can start before the whole
file transfers and can random-seek (including into a `moov` at the end)
because it fetches only the fixed-size chunks the player requests over the
room's existing WebRTC DataChannel, verifies each chunk against the signed
manifest, and serves them via a per-session loopback HTTP Range daemon (native)
or the same-origin ServiceWorker Range bridge (web).

Codec/container support is decided by core/player capability checks.
This subsystem transports original bytes; it rejects only manifest-level
violations.

## 2. Manifest (source-bound, hash-bound)

| field | rule |
|---|---|
| `v` | must be `1` |
| `mediaId` | lowercase hex sha256 computed from all binding fields (§2.1) |
| `sourceDeviceId` | **must** be the exact lowercase hex device id core signs in the playlist item; supplied at construction, never randomly assigned |
| `fileSha256` | sha256 of the whole original file |
| `mime` | one of the supported video MIMEs in `media_format.dart` (legacy `video/mp4` unchanged); must be canonical lowercase without parameters, otherwise `unsupported_media` |
| `size` | `0 < size <= kMediaMaxFileBytes` |
| `chunkSize` | must be `262144` bytes (256 KiB) |
| `chunkCount` | `ceil(size / chunkSize)`, `<= kMediaMaxManifestChunks` |
| `chunkHashes` | per-chunk sha256 list |
| `title` | display only, excluded from the mediaId binding |

### 2.1 mediaId binding
`mediaId = sha256hex("eir-media-manifest/v1|" +
[v, mime, size, chunkSize, sourceDeviceId, fileSha256, chunkHashes.join(",")].join("|"))`

`registerRemoteManifest` and `registerRemoteManifestChunk` **always**
recompute and check this; a playlist URL or commit from another room
cannot authorize bytes for this sender.

### 2.2 Limits (`media_limits.dart`)

| constant | value |
|---|---|
| `kMediaChunkSize` | 256 KiB |
| `kMediaMaxMessageBytes` | 16 KiB |
| `kMediaMaxFileBytes` | 8 GiB (memory ceiling, not a single-message cap; enforced by the manifest parser) |
| `kMediaMaxManifestChunks` | 32 768 |
| `kMediaMaxCacheBytes` | 512 MiB, process-global shared budget |
| `kMediaHighWatermark` | 256 KiB pause-while-above |
| `kMediaFetchTimeout` | 30 s per chunk |
| `kMediaMaxPendingRequests` | 16 |
| `kMediaManifestChunkBytes` | 12 000 (per manifest transfer chunk) |
| `kMediaMaxManifestBytes` | 4 MiB (whole-reassembled-manifest cap) |
| `kMediaMaxRangeBytes` | 8 MiB per `readRangeBytes` call (streaming bridge uses per-chunk) |

## 3. Split trust model (core signs, media verifies)

- **Manifest signature, authorisation, room membership and media-item
  binding are owned by core** (`SignEnvelope`/playlist commit). Core
  validates the source and publishes/propagates only manifest metadata.
- **This subsystem never trusts bytes before sha256-verification against
  the active manifest.** `.chunk` files read back from disk are verified
  before use; a tampered cache cell is dropped and refetched.
- An untrusted source manifest cannot start serving:
  - `registerRemoteManifest`: pass `trustedByCore: true` only after core's
    own signature check, or supply `manifestAuthorizer`.
  - `registerRemoteManifestChunk`: requires `manifestAuthorizer`; the
    `trustedByCore` escape hatch does **not** apply to chunk reassembly.
  - `MediaRequestAuthorizer` (optional) can deny per-request serving.
- Unapproved/unsigned manifests throw `MediaException('untrusted_manifest')`.

## 4. Core integration hooks (exact)

### 4.1 Construct one service per session

```dart
final service = LocalMediaService(
  sendControl: (msg) => dc.send(rtcMessageText(jsonEncode(msg))),
  sendBinary:  (frame) async => dc.send(rtcMessageBinary(frame)),
  bufferedAmount: () async => await dc.getBufferedAmount(),
  localDeviceId: identity.deviceId,      // source identity, lowercase hex sha256
  manifestAuthorizer: (m) async =>       // core: check room invite + playlist commit
      await isRoomAuthorizedFor(m.sourceDeviceId, MediaId: m.mediaId),
  requestAuthorizer: (mediaId) async =>  // optional: revoke room membership
      await isRoomMemberActive(),
  // native: cacheDir: await getApplicationCacheDirectory()/eir-media,
  // web: omit cacheDir; MemoryChunkCache is used
);
await service.start();
```

- `localDeviceId` is **required**; any other shape is rejected.
- `bufferedAmount` may return `FutureOr<int>`: awaited native bindings are
  supported.
- `maxMessageBytes` may similarly return `FutureOr<int>` and is clamped to
  the negotiated limit / `kMediaMaxMessageBytes`.

### 4.2 Manifest distribution — bounded, not in a single commit

A full signed 8 GiB manifest is ~2 MiB JSON; **core must not embed it in a
single signed playlist commit.** Use one of:

- Small manifest: core signs `manifestSha256` + embeds the manifest or the
  room passes it directly; both sides use `registerRemoteManifest`.
- Bounded transfer (works for arbitrary size):

```dart
// source side (media file owner):
await service.writeManifestChunksFor(mediaId);        // emits media_manifest_chunk …
// receiver side:
final m = await service.handleManifestChunk(msg);      // returns manifest only when complete
```

Wire shape (JSON control):

```json
{"type":"media_manifest_chunk","transferId":"…","mediaId":"…","index":i,"total":n,
 "totalBytes":nnn,"manifestSha256":"hex","bytesB64":"…"}
```

Both sides enforce `kMediaMaxManifestBytes`; the reassembler verifies
`sha256(manifestBytes) == manifestSha256` and the `mediaId` binding, then
invokes `manifestAuthorizer`. Signature verification stays in core; the
media subsystem verifies integrity and binding only.

### 4.3 Route DataChannel messages

```dart
if (msg.isBinary) service.onBinary(msg.bytes);
else {
  final decoded = jsonDecode(msg.text) as Map<String,dynamic>;
  if (decoded['type'] == 'media_manifest_chunk')
    unawaited(service.handleManifestChunk(decoded));
  else service.onControl(decoded);
}
```

No second `RTCPeerConnection` is created. `RoomSession` handles delivery
and this subsystem handles bytes. Cancel stale fetches on item switch via
`service.cancelRequest(requestId)`.

### 4.4 Opening the player URL

```dart
final uri = await service.openMediaUri(mediaId);   // opens real bridge
player.open(Media(uri));                           // media_kit
```

`uriFor` is valid only after `start()`; on web it is a real
same-origin `https://<origin>/eir-media/<token>/<id>.<ext>`; on native it is
`http://127.0.0.1:<port>/m/<token>/<id>.<ext>`. `<ext>` comes from the manifest
MIME (`mp4`, `m4v`, `mov`, `mkv`, `webm`, `avi`, `ts`, `3gp`, `ogv`, `flv`);
MP4 keeps the historical `.mp4` form.

### 4.5 Diagnostics
```dart
service.cacheTelemetry;  // cachedBytes/chunks/hits/misses/evictedBytes, maxBytes
service.transferTelemetry; // sentBytes/receivedBytes/frames and manifestBytes counters
```

## 5. Public API (exact signatures)

```dart
class LocalMediaService {
  LocalMediaService({
    required MediaControlSender sendControl,
    required MediaBinarySender sendBinary,
    required MediaBufferedAmount bufferedAmount,          // FutureOr<int> Function()
    required String localDeviceId,                        // sha256 hex
    MediaMaxMessageBytes? maxMessageBytes,               // FutureOr<int> Function()
    MediaManifestAuthorizer? manifestAuthorizer,
    MediaRequestAuthorizer? requestAuthorizer,
    Directory? cacheDir,    // native only; web: omit
    int? maxCacheBytes,     // shared-process budget; see §6
    Duration fetchTimeout,
    String? sessionToken,
    void Function(String code)? onStorageError,  // 'storage_full'; see §7.2
  });

  Future<void> start();
  String get loopbackBaseUrl, sessionToken;
  String uriFor(String mediaId);
  Future<String> openMediaUri(String mediaId);

  Future<MediaManifest> registerFile(XFile file, {String? title});
  Future<MediaManifest> registerRemoteManifest(Map<String, dynamic> json, {bool trustedByCore = false});
  Future<void> writeManifestChunksFor(String mediaId, {int maxChunkBytes = kMediaManifestChunkBytes});
  void beginManifestTransfer(Map<String, dynamic> head);
  Future<MediaManifest?> handleManifestChunk(Map<String, dynamic> chunk);

  void onControl(Map<String, dynamic> message);
  void onBinary(Uint8List frame);

  Future<Uint8List> readRangeBytes(String mediaId, int start, int end);  // ≤ kMediaMaxRangeBytes
  Future<void> writeRange(String mediaId, int start, int end, Future<void> Function(Uint8List slice) write);
  Future<Uint8List> ensureChunk(String mediaId, int chunkIndex, {bool urgent = true});
  void cancelRequest(int requestId);
  Future<void> releaseMedia(String mediaId);
  MediaCacheTelemetrySnapshot get cacheTelemetry;
  MediaTransferTelemetry get transferTelemetry;

  /// `'storage_full'` after a native disk write failed for lack of space;
  /// `null` otherwise. Cleared by [clearUnprotectedCache]. See §7.2.
  String? get lastStorageErrorCode;

  /// Safely drop only idle (unprotected) cached chunks across every media
  /// in this service. Returns the number of bytes freed. The signed manifest,
  /// the original source file and any chunk currently inside an active
  /// playback/read window (protected via `ensureChunk`/`writeRange` or
  /// `protect`) are kept; this is NOT a full wipe. Safe to call from a V1
  /// "clear cache" settings entry.
  Future<int> clearUnprotectedCache();
  Future<void> dispose();
}
```

## 6. Global cache bound

All registered chunk caches share one `MediaCacheBudget` accounting.
`MediaCacheBudget.maxBytes` defaults to `kMediaMaxCacheBytes` (512 MiB).
Unprotected bytes across **all** movies are evicted before a new put is
accepted; only bytes remaining protected by `protect()` are never
disposed. Caches which decline storage simply do not cache the new
chunk; playback still receives the verified bytes. Setting
`maxCacheBytes` in the constructor raises/lowers the shared budget.

## 7. Disk cache integrity

On readback, `.chunk` files are verified with the expected manifest
sha256 hash before being served; a corrupt cell is removed and refetched.
This closes the "stale/trusted disk chunks" gap; you may safely point
`cacheDir` at a restart-persistent directory.

## 7.1 Safe cache clearing (V1 settings hook)

`clearUnprotectedCache()` is the minimal, safe "clear cached media" entry
for core/UI. It evicts **only** idle (unprotected) chunks across every
media registered with the service and returns the freed byte count.

- **Kept:** the signed manifest, the original source file, and any chunk
  currently inside an active playback/read window (protected by
  `ensureChunk`/`writeRange` or `protect()`).
- **Not a wipe:** chunks under active playback survive; a subsequent
  `ensureChunk`/`readRangeBytes` refetches dropped chunks from the peer and
  re-charges transfer telemetry.
- No new wrapper or architecture is introduced; it reuses the existing
  `MediaChunkCache.evictOldest(protectedIndices:)` path.

## 7.2 Insufficient disk space (A17)

On native, if a chunk write fails with a real disk-full / quota error
(POSIX `ENOSPC`/`EDQUOT`; Windows `ERROR_HANDLE_DISK_FULL`/`ERROR_DISK_FULL`,
plus an OS-message fallback), the service:

- **stops adding new cache entries** — a process-wide latch blocks further
  disk writes so it does not hammer a full disk;
- **keeps playing** — the already-fetched, SHA-256-verified chunk is served
  from memory, so the current range is not silently stalled;
- **preserves** valid cached chunks and the original source file, and
  **deletes** the temp `.tmp<index>` file (stale temp files are also cleared
  on cache `init()`);
- **surfaces** the recognizable code `storage_full` via
  `lastStorageErrorCode`, `cacheTelemetry.lastStorageErrorCode`, and the
  optional `onStorageError` callback.

Recovery: `clearUnprotectedCache()` frees space, then resets the latch and
clears the code; new writes are retried (re-latching if still full).

Web (`MemoryChunkCache`) has no disk, never emits `storage_full`, and keeps
its byte-budget semantics unchanged.

Core wiring (owned by core, not media): pass `onStorageError` to set
`RoomSession._lastErrorCode`, map `'storage_full'` in `_mapMediaCode`, and
add a localized "insufficient storage, please free space" message.

## 8. Errors (`MediaException.code`)

`unsupported_media` | `invalid_manifest` | `untrusted_manifest` |
`invalid_range` | `chunk_hash_mismatch` | `source_offline` |
`cache_budget_exceeded` | `storage_full`

## 9. Web path

Requires a direct dependency on `package:web` (currently transitive via
`file_selector`/`cross_file`; request a direct dependency line from the
root before invoking it). The conditional `media_server_web.dart` uses
`dart:js_interop` and a pure-`package:web` API path.
`web/eir_media_sw.js` serves `/eir-media/<token>/<id>.<ext>` for the same
extension set; all
others fall through. Byte supply is per-Range via `MessageChannel`→Dart.
`web/eir_media_bridge.js` registers the SW, awaits a controlled page
context (`clients.claim()`/`skipWaiting()`, ≤5 s timeout), and revokes the
session token on dispose.

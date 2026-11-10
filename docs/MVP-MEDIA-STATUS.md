# MVP Media Status — Local-file P2P streaming

## Implemented (and tested on Linux)

- Original-bytes MP4 streaming over the room DataChannel; no remux,
  no transcoding, no full-file download before playback.
- Multi-chunk fixture generated at `/tmp/eir-media-fixture.mp4`
  (20 s, H.264/AAC, 3,098,261 B, 12 chunks) using ffmpeg testsrc2/sine.
- Native loopback HTTP Range bridge (`127.0.0.1:<random port>`, per-session
  token): `200/206/416`, suffix/open-ended ranges, `Accept-Ranges`,
  `Content-Range`, `Content-Length`, HEAD/GET, no arbitrary file access.
- Native tests (`test/media/range_test.dart`) verify 206 exact prefix,
  suffix tail (`bytes=-128`), open-ended range, 416 out-of-bounds, and
  multi-range rejection. Only needed chunks are transferred; a tail seek
  asserted byte position `18 s` in the real multi-chunk fixture.
- Real MP4 headless playback via `probeMediaPlayback` before full download
  (native, media_kit, under xvfb): `success=true`, duration 20.000 s,
  `finalPosition` advanced, `sent=2,055,936 B` (of 3,098,261 B) before
  first position advance; `cachedBytes=2,049,685`.
- Tail-seek integration (native): `tail-position=0:00:18`, `errors=[]`,
  `sent=2,318,879 B (of 3,098,261 B)` before reaching the end, so
  `moov`-at-end did not force a full-file fetch. Verified by
  `flutter test integration_test/media_transfer_test.dart -d linux`.
- Chunk/frame integrity: per-chunk SHA-256 vs manifest, SHA-256 verified
  disk cache cells rejected when tampered; corrupt frames never cached.
- Manifest splitting: bounded `media_manifest_chunk` reassembly with
  `manifestSha256` verification (`kMediaMaxManifestBytes=4 MiB`,
  `kMediaManifestChunkBytes=12000`, max 4 MiB reassembled regardless of the
  8 GiB ceiling / single DataChannel message).
- Global cache budget: one shared `MediaCacheBudget` across every registered
  chunk cache (`kMediaMaxCacheBytes=512 MiB`, configurable).
  Unprotected bytes are evicted globally; new bytes are not cached when
  everything is protected rather than breaking the bound.
- Conditional platform dispatch: `local_media_service.dart` selects
  `local_media_native.dart` or `local_media_web.dart`; no `dart:io` or
  `Directory` in the web branch. Web cache is `MemoryChunkCache`,
  no disk persistence today.
- **64-bit frame offset accessor (web-safe):** `setUint64BigEndian` /
  `getUint64BigEndian` in `media_frames.dart` encode the chunk offset as
  two big-endian `Uint32` words — no `ByteData.setUint64`, which is not
  reliable on dart2js. `frames_test.dart` covers `offset > 4 GiB`
  (`4294967449`) and the high-bit `requestId`. The frame codec is shared
  between native and web (DataChannel path), so the >4 GiB regression is
  covered for both.
- **Real 9 MiB browser Range (Chromium):** `flutter build web --target
  test/media/browser_probe.dart` + Playwright/Chromium against
  `web/eir_media_sw.js` + `web/eir_media_bridge.js`. Verified:
  `size=9,437,201 B` (9 MiB+17), `206`/`416`/`Accept-Ranges: bytes`,
  `Content-Range` correctness, bounded `MAX_STREAM_CHUNK=65536` enqueue,
  dual-window isolation (a different browser context fetching the same token
  URI returns `404`), token revoke returns `404`, and abort-after-partial
  backpressure (`abortDeltaBytes=262,943` < 512 KiB). See the explicit
  honesty note below — this is a **dummy-byte synthetic fixture over the SW
  Range bridge**, not browser video decoding and not WebRTC/RTC interop.
- **Safe cache-clear API (`clearUnprotectedCache`):** documented stable hook
  in `docs/MVP-MEDIA-API.md` §5/§7.1. It drops only idle (unprotected)
  chunks across all media and returns freed bytes; the manifest, the source
  file, and chunks inside an active playback/read window survive. Covered by
  `test/media/cache_clear_test.dart`. No new wrapper architecture.
- **Insufficient-storage handling (F5 / A17):** a real native disk-full /
  quota write error (`ENOSPC`/`EDQUOT`/Windows disk-full, detected in
  `isStorageFullError`) no longer aborts playback or fails silently. The
  service stops adding new cache entries (process-wide latch), serves the
  already-verified chunk from memory so the range still completes, preserves
  valid chunks and the source file, deletes the temp `.tmp<index>` file
  (stale temps also cleaned on `init()`), and surfaces a recognizable
  `storage_full` code via `lastStorageErrorCode`, `cacheTelemetry.
  lastStorageErrorCode`, and an optional `onStorageError` callback. Recovery
  is `clearUnprotectedCache()` (frees space, clears the latch/code). Web
  memory cache is unchanged (no disk, never emits `storage_full`). See
  `docs/MVP-MEDIA-API.md` §7.2 and `/tmp/eir-media-storage-error-api.txt`.
  Covered by `test/media/storage_full_test.dart` (fault-injected ENOSPC).

## Honest limits

- **The 9 MiB Chromium probe is NOT browser video decoding and NOT
  WebRTC/RTC interop.** `test/media/browser_probe.dart` serves a synthetic
  `XFile.fromData` of deterministic dummy bytes (mime `video/mp4`) through
  the ServiceWorker Range bridge and asserts byte-for-byte Range correctness,
  isolation, revoke and cancel/backpressure. It proves the SW Range adapter
  and token/isolation model, nothing about codec playback or peer links.
- Web/ServiceWorker bridge compiles with `dart:js_interop` (SDK), **not** a
  direct `package:web` dependency; the earlier "needs package:web" note was
  stale. `flutter build web --target test/media/browser_probe.dart` succeeds
  and `web_compile_test.dart` passes on chrome.
- **Web playback end-to-end (`Media(<same-origin /eir-media URL>)` in
  media_kit) is not exercised.** Only the SW Range fetch path is verified,
  via the dummy-byte probe above. NO production config gap for the bridge:
  the production `LocalMediaService.start()` → `_WebHost.start()`
  (media_server_web.dart) already injects `eir_media_bridge.js` dynamically
  via `createScriptElement` + `appendToBody`, so the shipping `web/index.html`
  needs no manual `<script>` tag and the build worker needs no platform
  change for it.
- Native end-to-end PLAYBACK **is** verified: the integration test drives
  real media_kit on Linux under xvfb with a real H.264/AAC MP4 and confirms
  no full-file download + moov-at-end tail seek. Its data transport is an
  in-process Dart callback loopback (source↔recv wired directly), **not** a
  real WebRTC DataChannel — it proves the media pipeline + decode, not the
  peer link. Real DataChannel P2P is covered by core RoomSession integration
  tests, outside media scope.
- **Storage-full is verified by an injected write failure, not real
  low-disk hardware.** `storage_full_test.dart` throws a real
  `FileSystemException`/`OSError(ENOSPC)` from the injected chunk writer,
  exercising the exact detection + handling path. No physical full-disk
  device run was performed; that is an evidence gap, not a behavior claim.
- Windows/macOS/iOS builds and actual devices are not verified here.
- Core RoomSession integration hooks, `RoomSession.addLocalFile`, signage of
  the manifest in the playlist commit path, and UI (Agy) are not implemented
  here; only the service-side callbacks and docs are provided.
- 8 GiB cap is a manifest parser ceiling; rendering an 8 GiB manifest via
  the DataChannel is possible only with the bounded chunk transfer;
  neither has been run to exhaustion.
- Web cache is memory-only (no persistence across SW restarts); native cache
  persists with hash verification but has no size floor notification to the
  user.
- Seek of a `moov` fragment requires the player's probe requests to line up
  with chunk boundaries; for large GOP MP4s without faststart this can be
  slow but byte-bounded and verified (native integration test).

## Expected core integration steps

1. Construct `LocalMediaService` with `localDeviceId: identity.deviceId`
   and authorizers (see `docs/MVP-MEDIA-API.md` §4).
2. Add one `media_manifest_chunk` route and pass every envelope through
   `service.onControl` / `service.onBinary`.
3. Sign the manifest in the playlist commit (embed `manifestSha256` only);
   transfer full manifest via `writeManifestChunksFor` on the source side
   and `handleManifestChunk` on the receiver.
4. `RoomSession.addLocalFile(file, title)` → `await _media.registerFile(...)`
   and broadcast the manifest through the signed commit; open
   `Media(await _media.openMediaUri(manifest.mediaId))`.
5. Route 1) signed authorization 2) controlled room membership; revoke on
   leave / kick-out with `service.releaseMedia(...)` before dispose.

## Verification evidence

- `dart analyze lib/media test/media` — no issues.
- `flutter test test/media` — **35 tests passed** (range/bridge assertions,
  cache/hash-tamper, cache-bound eviction, `clearUnprotectedCache`,
  manifest bounded reassembly + binding, frames >4 GiB, web compile,
  and 4 storage-full tests: ENOSPC stop/preserve/cleanup, stale-temp init
  cleanup, `isStorageFullError` code/message detection, service serve-from-
  memory + report + recover).
- `flutter test --platform chrome test/media/web_compile_test.dart` — passes
  with `CHROME_EXECUTABLE=<playwright chromium>` (web branch compiles with
  the new `onStorageError` param).
- `xvfb-run -a flutter test integration_test/media_transfer_test.dart -d linux`
  — **2 tests passed**: real media_kit playback over the real
  LocalMediaService pipeline with no full-file download, and moov-at-end
  tail seek (`errors=[]`). Transport is an in-process callback loopback,
  not a real WebRTC DataChannel (real DataChannel is a core RoomSession test).
- `flutter build web --target test/media/browser_probe.dart --release` —
  succeeds (js_interop path, no `package:web`).
- Real Chromium probe (`node test/media/browser_probe.js`): PASS —
  `size=9437201`, `boundedChunk=65536`, `abortDeltaBytes=262943`,
  dual-context 404 isolation, revoke 404. (Dummy-byte fixture — see limits.)
- `/tmp/eir-media-fixture.mp4` ready and referenced by the integration test.
- Norns MCP connection check (this round): `initialize` 2024-11-05 OK,
  41 tools listed; no publish performed.

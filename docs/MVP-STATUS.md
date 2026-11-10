# MVP Status — core/platform/server/tests scope

> Core worker handoff snapshot, not the current whole-app acceptance matrix. See
> [current build/platform results](MVP-BUILD-STATUS.md), [product Web validation](MVP-WEB-VALIDATION.md)
> and [core acceptance map](MVP-ACCEPTANCE-MAP.md). Compilation, installation, testing,
> and environment/packaging fixes are owned by free OpenCode/CodeBuddy workers, not the coordinator.

**Snapshot:** 2026-11-07 (Asia/Shanghai), refreshed by the free
`deepseek-v4.1-flash` handoff session (F1–F5 core fixes, W3 retry exhaustion).
This document records
what actually passes against the current tree. Nothing here claims six-platform
completion.
Scope of this file: `lib/core/**`, `lib/platform/**`, `server/**`,
`test/core/**`, `integration_test/room_session_url_test.dart`,
`integration_test/room_session_local_media_test.dart`,
`integration_test/room_session_streaming_proof_test.dart`,
`integration_test/room_session_core_fixes_test.dart`,
`integration_test/room_session_reconnect_exhaustion_test.dart`, and
nonvisual Web bridge assets. UI files are read-only for us; the media
subsystem (`lib/media/**`) is the partner's source scope, but its service is
integrated through `lib/core/room_session.dart` and exercised by the
integration tests below.

## Result summary

| Slice | State |
|---|---|
| Secure room + URL synchronization slice (protocol, identity, signaling, ACL, commits, snapshot, clock) | **Implemented, unit + real two-client integration tests pass on Linux** |
| Local media slice (XFile, signed SHA-256 manifests, bounded 16 KiB P2P chunks, chunked manifest transfer, loopback Range bridge) | **Integrated through `RoomSession`; real two-client integration tests pass on Linux, including a 65 MiB stream-before-full-transfer proof.** Web SW bridge is media partner's scope (per-platform validation still pending). |
| Ordered commit/concurrency + ACL revocation | **Implemented + tested** (serialized control requests, receiver-enforced revocation). |
| Large-manifest via compact source-signed root + bounded chunked transfer | **Implemented + proven** (`kMaxInlineManifestBytes`=8 KiB; `media_manifest_chunk` path). |
| Real local RTC streaming playback & seek | **Implemented + proven** (`room_session_streaming_proof_test.dart`). |
| Windows build | **Not run by me.** Coordinator has an isolated remote Windows workspace (approved pinned SSH); macOS explicitly paused by user; iOS has no host. |
| Six-platform validation | **Not done.** Linux verified; everything else untested. |

## Verified passing (commands and outputs)

- `flutter analyze lib/core lib/platform server` — **No issues found**.
- `flutter test test/core` — **85/85 pass** (74 + 11 new `url_probe_test` HLS/URL
  boundary cases): canonical encoding golden vectors
  + rejections, Ed25519 identity (incl. the `DeviceIdentityStore.verify()`
  regression test for forged signatures), corrupt-store controlled failure,
  invite sign/verify/tamper/expiry, domain separation (invite vs room_commit),
  commit chain sequencing/parking/drain/request-id dedup, ACL admit/grant/
  revoke (receiver-enforced), clock offset estimation/outlier rejection/EMA,
  bounded control-envelope rejection, playlist cap (200), stale-state
  rejection, and a real WebSocket signaling-server suite: room creation, takeover
  rejection/idempotent rejoin, invite consumption single-use, epoch staleness,
  room full, cross-room isolation, oversized frames, rate limiting, malformed
  JSON, disband permissions, member_left broadcast.
- `ulimit -c 0; timeout 540 xvfb-run -a flutter test integration_test/room_session_url_test.dart -d linux` — **pass (2 tests).** Real two-client room, DTLS + DataChannel, verified handshake, URL playback sync, ACL, seek, disband.
- `ulimit -c 0; timeout 540 xvfb-run -a flutter test integration_test/room_session_local_media_test.dart -d linux` — **pass (2 tests).** Local file manifest + P2P chunk transfer; fixture streams before full transfer and seek follows.
- `ulimit -c 0; timeout 540 xvfb-run -a flutter test integration_test/room_session_streaming_proof_test.dart -d linux` — **pass (1 test).** 65 MiB faststart MP4 (`/tmp/eir-streaming-large.mp4`, 68,128,265 bytes): guest receives a chunked manifest (`manifestBytesSent > 0` over `media_manifest_chunk`), then decodes past 1 s of playback while fewer than the full file bytes have crossed the DataChannel (real pre-transfer proof), then seeks to ~12 s; cache telemetry + safe clear reachable.
- `xvfb-run -a flutter test -d linux integration_test/room_session_core_fixes_test.dart` — **pass (4 tests):**
  - **F1** corrupt media reaches the real player → `player.stream.error` → `lastErrorCode='media_probe_failed'`; switching back to a valid item clears it (no stale-media pollution).
  - **F3** the **same signaling URL** is stopped (abruptly, no `disbanded`) and restarted on the same port; the existing sessions keep URL/room/identity and recover within the 3 bounded auto attempts; the owner rotates the invite epoch (old invite rejected, new invite accepted); the data channel survives.
  - **F4** `retry()` on the same URL recovers connectivity, preserves the data channel, and leaves no spurious error; a retry while connected is a no-op.
  - **W3 / A16 exhaustion (this round):** after 3 failed auto attempts (1.1/2.1/4.2 s) the session now enters `connectionState == disconnected` with `lastErrorCode == 'signaling_unavailable'` and stops the loop; socket callbacks and a restarted server no longer revive it automatically. Room/identity/playlist/playback and a surviving DataChannel are retained. `retry()` is the only way out, re-registers on the same URL, clears the stale connectivity error and rotates the invite epoch. Proven by `integration_test/room_session_reconnect_exhaustion_test.dart` (1 test): cut → exhausted terminal state → same-URL endpoint restored but no auto-recovery for 8 s → `retry()` → connected with the same room/identity/DC and a new invite.
  - **A11/A12/A10** natural-end auto-advance (owner → next item, member follows), late join (member joining after the playlist exists receives it via snapshot), and replace-current (both peers' item URL updates).
- `xvfb-run -a flutter test -d linux integration_test/room_session_reconnect_exhaustion_test.dart` — **pass (1 test).** Real two-client room, URL playback running, signaling killed abruptly on the same URL: bounded auto-retry exhausts into `disconnected`/`signaling_unavailable`; the same-URL endpoint is then restored and the session stays disconnected for 8 s (no infinite loop, no auto-revival); explicit `retry()` reconnects on the same URL with the same room/identity/playlist/DataChannel, clears the error and rotates the invite epoch.
- **Concurrency / `stale_state` regression fixed this session (core domain).** The
  previous blanket `baseSeq < _chain.lastSeq` check in `_handleControlRequest`
  wrongly rejected a member's SECOND concurrent control request (both carry the
  same fresh `baseSeq`) as `stale_state`, dropping commits on slow platforms
  (Android emulator failed: only 1 of 4 burst commits landed). Replaced with a
  per-peer high-water-mark regression check + a targeted list-staleness check
  (item no longer present). Concurrent same-view requests now all commit and
  converge. The `room_session_url_test.dart` "concurrent control requests and
  ACL revocation are serialized" test was redesigned to assert exact end-state
  (playlist length 2, mode playing, rate 1.5, deterministic post-burst seek
  propagates, chain settles) instead of a fragile seq lower bound. Re-verified
  on Linux (2/2). **Android re-run is owned by the build wheel** for final
  confirmation — not re-run here to avoid sharing `build/` with that wheel.
- **F1–F5 core fixes (this session, with real Linux evidence where noted):**
  - **F1 async player errors:** `RoomSession` subscribes to `player.stream.error`
    and maps failures to the existing `media_probe_failed` code; `_errorItemId`
    guards against errors from a previously-unloaded item; a successful load
    clears the stale error. Proven by `room_session_core_fixes_test` F1.
  - **F2 URL/HLS boundary:** `url_probe_io.dart` now classifies HLS
    (`classifyHlsPlaylist`): VOD (`EXT-X-ENDLIST`, no key) allowed; live,
    AES-128/SAMPLE-AES/DRM, and unresolvable master variants rejected; master
    variants followed at most one level, http(s)-only (no SSRF/arbitrary scheme).
    Web stays scheme-only (CORS) and surfaces real player errors. 11 unit tests.
  - **F3 signaling restart:** `SignalingServer.stop(graceful:false)` drops peer
    sockets **without** a `disbanded` frame (simulated crash). On reconnect the
    owner re-registers via `create_room` on the **same URL**, rotates
    `_inviteEpoch`, regenerates the signed invite (old invites → `invite_stale`),
    and keeps a surviving DataChannel. Proven by `core_fixes_test` F3.
  - **F4 manual retry:** public `retry()` reuses the reconnect path, preserves
    room/identity/playback state, de-dupes concurrent calls (`_retryInFlight`).
    UI contract: `/tmp/eir-core-retry-ui-api.txt`. Proven by `core_fixes_test` F4.
  - **F5 storage-full:** `LocalMediaService(onStorageError:)` wired in
    `_ensureMediaService`; `_mapMediaCode('storage_full')→'storage_full'`;
    `clearUnprotectedCache()` clears a lingering `storage_full`. Media owner
    unit-tested real ENOSPC; core wiring is analyze-clean (no core runtime ENOSPC
    injection).
- `ulimit -c 0; timeout 150 xvfb-run -a flutter test integration_test/room_session_url_test.dart -d linux` — **pass.** Two real `RoomSession`s in one process, real in-process signaling server (loopback), real DTLS + DataChannel with getStats-mapped remote fingerprint verification, real HTTP range-capable loopback media server serving `assets/sample.mp4`. Covers: create/join/invite, verified handshake on both sides, URL add → commit applied on the guest, switch_item propagation, member control denial (`permission_denied`, no commit), owner play → guest follows, grant_admin → member pauses owner, revoke_admin → member denied again, seek propagation through the commit chain, `closeRoom()` disband (both peers reset).
- `flutter test integration_test/native_webrtc_loopback_test.dart -d linux` — **previously validated in this environment** (DataChannel loopback, both directions, remote DTLS fingerprint from getStats); still present and passing as of this session's runs.
- `flutter build web --debug` — **built.** Web build compiles; Wasm dry-run warning only.
- `flutter build linux --debug` — **built** (`build/linux/x64/debug/bundle/eir`).

## UI compatibility (report to coordinator, not fixed by us)

- UI consumes `session.closeRoom()`, `init()`, `isInitialized`/`initError`
  (its own local state), `player`, `members`, `playlist`, `playback`,
  `grantAdmin/revokeAdmin/removeItem/reorderItem/replaceItem/switchItem`,
  `setSignalingUrl`, `createRoom/joinRoom/leaveRoom`. All exist with the
  expected names/ownership semantics. `room_session.dart` re-exports
  `DeviceIdentityStore`, `SignalingClient`, `XFile`, `DeviceIdentity`,
  `InMemorySecureKeyValueStore`, `SecureKeyValueStore`,
  `FlutterSecureStorageStore`, `IdentityStoreCorrupted`, `RoomMember`,
  `MemberTelemetry`, `PlaylistItem`, `PlaybackState`, enums, `RoomSession`.
- `lib/models.dart` re-exports the same names (with `DeviceIdentityInfo`).
- **UI tests fail as-is** (`flutter test test/ui` — 4 failing): every failure
  is a `pumpAndSettle()` timeout against the indeterminate
  `CircularProgressIndicator` loading banners in `LobbyView` (fake session
  tests). Not caused by core API changes; fix belongs to UI scope
  (use `pump()`/`pump(Duration)` windows instead of `pumpAndSettle`, or make
  initialization banners settle). Please route to the UI session.
- UI status doc (`docs/MVP-UI-STATUS.md`) lists those same tests as passing —
  that claim is not reproducible in this tree; flagging, not editing the doc.

## Known remaining / not done (honest list)

1. **Local-file playback IS implemented end-to-end on Linux** (proven by
   `room_session_streaming_proof_test.dart` and `room_session_local_media_test.dart`).
   Remaining gaps that are NOT yet proven here: per-platform (Windows/macOS/
   Android/iOS/Web) media transfer validation, the Web ServiceWorker Range
   bridge (media partner scope), and TURN fallback for hostile NAT.
2. **STUN only, no TURN.** Public STUN (`stun.l.google.com:19302`,
   `stun.cloudflare.com:3478`). Rooms do not work behind symmetric NAT
   without a relay. Out of agreed v1 scope.
3. **Snapshots replace state wholesale and are taken only when requested/needed**
   (join, resync, parked-gap timeout). No incremental snapshot for partial
   state loss beyond commit parking + `RESYNC_REQUEST`.
4. **Guest never initiates WebRTC; owner-driven renegotiation only.** On
   signaling loss with a surviving DataChannel the room keeps working; if the
   DataChannel itself dies, the owner restarts the offer/answer cycle with
   1/2/4 s backoff up to 3 attempts, then the guest shows
   `signaling_unavailable`.
5. **Clock sync is for position/rate alignment, not frame accuracy.** Leader
   monotonic anchor + NTP-style TIME_PING/PONG over the verified channel,
   min-RTT selection with EMA smoothing; expected-position clamp is 2 s
   (seek correction). Sub-100 ms render alignment not claimed.
6. **Playback rate is integer milli-units on the wire** (1000 = 1.0×) — no
   floats are allowed by the restricted canonical encoding. UI doubles
   map losslessly through rounding.
7. **Invite token is single-use per device identity.** Re-join with the same
   identity is idempotent; different identity gets `invite_consumed`. Room
   is at most 2 peers; third connection gets `room_full`.
8. **Web probe limitation:** browsers cannot read cross-origin media
   responses (no CORS headers on typical CDNs), so on Web the add-time probe
   validates scheme/shape only; per-device playback availability is reported
   from the media element error events, not a preflight probe.
9. **Android background behavior** untested; Gradle validation uses isolated
   `GRADLE_USER_HOME=/tmp/eir-gradle-home` with symlinked caches (no global
   init scripts); license acceptance was NOT performed (needs user/coordinator).
10. **Windows/macOS/iOS builds unverified**; Windows is to be run by the
    coordinator in the isolated pinned-SSH workspace.
11. **Norns MCP**: this session had no MCP tool access (only the local
    filesystem and shell). Coordinator previously performed the Norns
    tool-list check. No publishing/release actions were taken by this worker.
12. **Shared-monotonic-clock API note:** `PlaybackState.effectiveAt` is
    display-only wall clock. Sync uses `anchorSharedMs`/`rateMilli`/`expectedPositionAt`.
    `DateTime` is never compared across machines.
13. **Error surface:** `RoomSession.lastErrorCode` exposes stable codes:
    `signaling_unavailable, invalid_invite, invite_expired, invite_consumed,
    room_full, room_not_found, unsupported_media, media_probe_failed,
    media_unavailable, identity_unavailable, permission_denied,
    commit_rejected, handshake_failed, protocol_violation,
    chunk_hash_mismatch, source_offline, storage_full`. `media_probe_failed`
    now also covers **async** player/decode errors (F1). `stale_state` is
    emitted as a `request_denied` *reason*: a genuine `baseSeq` regression, or a
    list modification referencing an item no longer in the playlist (targeted
    list-staleness). It is not itself a `lastErrorCode`.
14. **Manual retry & invite epoch:** `retry()` (public) and auto-reconnect share
    `_registerWithSignaling`; on a same-URL restart the owner rotates the invite
    epoch and old invites are invalidated. A member whose old invite is stale
    must be re-invited to re-register signalling; its existing DataChannel (if
    still open) keeps media flowing. Auto-retry is bounded to 3 attempts and
    then becomes a terminal `disconnected` state (`signaling_unavailable`);
    only `retry()` clears it. A failed `retry()` returns to `disconnected`, so
    the manual retry entry stays reachable instead of hanging in `reconnecting`.

## Security properties verified vs not

Verified by tests: forged Ed25519 envelope rejection; domain separation;
commit chain prevHash binding to genesis; unauthenticated commit rejection;
receiver-side ACL revocation enforcement (admin loses control immediately
after revoke); invite signature/pinning/expiry/epoch; single-use token;
cross-room signal isolation; oversized/rate-limited/malformed input rejection;
DTLS-fingerprint binding from `getStats()` on real Linux runs (handshake
fails closed when fingerprint is absent — `handshake_failed`).

Not verified: compromised-owner behavior (out of scope — fixed leader is
trusted), TURN-less reachability across hostile NATs, post-disband cache
erasure on peers (explicitly out of v1), multi-room federation (out of v1),
resumption across owner device restart (room must be recreated; invites die
with the memory-only server by design).

## What "done" still requires (owner: coordinator + UI session)

1. Per-platform validation of the local-media P2P plane (Windows/macOS/Android/
   iOS/Web) and the Web ServiceWorker Range bridge (media partner scope); the
   Linux real-two-client proof already passes.
2. UI tests fixed by UI session (pump/settle); repo `flutter test` fully green.
3. Norns MCP: a **read-only** `initialize` + `tools/list` check was performed
   this session against `https://norns.cc.cd/api/mcp` using the coordinator's
   configured bearer token (HTTP 200; server `norns-interactive` v1.0.0; 41
   tools listed). No write/publish/release actions were taken and none are
   authorized by this worker.
4. Android debug build/test with `GRADLE_USER_HOME=/tmp/eir-gradle-home`
   (licenses accepted by coordinator/user only).
5. Windows build by coordinator in the isolated remote workspace; macOS/iOS
   remain unverified (no hosts) — must be recorded as such, never as tested.
6. Web media/loopback validation in Chromium (`CHROME_EXECUTABLE`).
7. `docs/MVP-API.md` semantics notes updated for local-media integration (done
   this session); keep in sync if the media partner changes transfer bounds.

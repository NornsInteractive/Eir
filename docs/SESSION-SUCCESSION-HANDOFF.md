# Session Handoff — Owner Succession & Media Source Offline (2026-11-18)

## Role & scope

- Worker: external **free** CodeBuddy fallback (`hy3`), product.json reverified `x0.00 credits`; no paid fallback. Root reported Norns already checked (no reconnection, no publish).
- Bound to `lib/core/room_session.dart` + its business tests, `lib/core/call_session.dart` + call tests (only if needed), and this handoff.
- **Untouched:** updater/config/native/UI files, both signaling servers, all integration tests, other agents' work. No app build/install/package/publish/UI. Only `flutter test` unit harnesses were run.

## Result summary

- **No source or test edits.** Nothing was independently reproduced as a defect in the ownership/source scope, so no patch was made.
- **COMPILE: CLEAN.** `flutter analyze` on the 2 owned source files + 2 focused test files → `No issues found!` (exit 0).
- **TESTS: ALL EXECUTED GREEN.** Succession/source-offline bundle 14/14; call bundle 12/12 (includes callId isolation test). Details below.

## Task 1 — Owner succession & source offline (verified flow)

### Current implemented rule (V1 fixed-owner is superseded — do NOT remove)

Latest behavior is **authority succession**, implemented consistently in 3 places with the same deterministic comparator (online/remaining candidates, **admin first, then earliest `joinedAt`**):
- `server/signaling_server.dart:655-675` `_handleLeave`: on owner departure with remaining peers, broadcasts `member_left`, then `owner_changed{newOwnerDeviceId, previousOwnerDeviceId}`.
- `cloudflare/_worker.js:239-259`: identical rule/messages.
- `lib/core/room_session.dart:1702-1736` `_handleMemberLeft` computes the same successor locally (marks leaver offline first, filters `online && != deviceId`); `room_session.dart:1667-1700` `_handleOwnerChanged` applies the authoritative server value. `joinedAt` originates at the server (`signaling_server.dart:342,503`) and is propagated via `join_accepted`/`member_joined`/snapshot (`room_session.dart:1597-1661`), so candidates are ordered from one clock — succession is deterministic across clients.

### Owner leaves vs room dissolved

- **Owner leaves (single departure):** room persists; `member_left` → local succession → `owner_changed` overrides with the server's authoritative successor. New owner starts room timers / P2P re-offer (`room_session.dart:1672-1676,1729-1734`).
- **Room dissolved:** owner-only `closeRoom()` publishes signed `room_close` + sends `disband` (`room_session.dart:1262-1279`); server broadcasts `disbanded` → client `_handleDisband` tears down peer, full-resets state, and **stops the player** (`room_session.dart:1776-1783`). Distinct from a plain leave.
- **No eligible successor** (owner was last peer / all others offline): server does not emit `owner_changed` and reaps the room (`signaling_server.dart:676`, `cloudflare/_worker.js:260-262`).

### Media source offline → replacement vs unavailable/pause, no stale playback

- `isItemSourceOffline` (`room_session.dart:752-769`): only `local` items with a known remote source are ever "offline"; self-sourced items are never offline; offline = source member `online == false`.
- `_findNextPlayableItem` (`room_session.dart:878-893`): wraps the playlist, skips the current item and any offline-sourced item; returns `null` when nothing is playable.
- On source/owner departure, the new owner auto-switches to the next playable item at position 0 / mode playing; **if none is playable it publishes `pause`, not a skip** (`room_session.dart:1746-1769`). `_handleOwnerChanged` performs the same switch for the newly promoted owner (`room_session.dart:1683-1696`).
- `onSourceOffline`/`onSourceAvailable` callbacks (`room_session.dart:2208-2227`) set/clear `_offlineMediaId` + `lastErrorCode='source_offline'` only for the **current** item and current room generation; stale-media and stale-generation events are ignored. Switch commits cancel pending fetches except the new item's media (`room_session.dart:3591-3593`). `switch_item` keeps `_currentItemId` and `_playback.itemId` in sync (`room_session.dart:3581-3589`), so the offline check reads the right item. No stale-source playback path found in the ownership scope.

### Behavioral tests executed (these run real code paths, not source-string checks)

`flutter test test/core/room_succession_and_playlist_test.dart test/media/source_offline_test.dart -r expanded` → **14/14 pass**, exit 0:
- `room_succession_and_playlist_test.dart` — 5 tests: `transferOwnership updates owner and increments version` (real `RoomAcl`); plus 4 **logic-simulation** tests (admin-first / earliest-joinedAt / offline-excluded sort, and playlist next-playable) that inline the comparator rather than driving `RoomSession`. Treat these as rule documentation, **not** RoomSession E2E proof.
- `source_offline_test.dart` — 9 real `LocalMediaService` behavioral tests (timeout, retry/cache, stale-media id attribution, HTTP 206, peer `media_error`, peer cancel, `invalid_range` no-offline, hash-corrupt no-offline, backpressure): all pass. These pin the service-side contract that feeds the RoomSession `onSourceOffline` filter above.

## Task 2 — callId compatibility boundary (no change, explicitly reported)

- Code (`call_session.dart:376-388`): outgoing signals are tagged with a per-call `callId` (`Uuid().v4()`); an incoming **tagged** signal whose `callId` differs from the current call is dropped; `call_invite` and all **untagged (legacy)** signals are still accepted. `_cleanup()` clears the id.
- **No safe backwards-compatible narrowing exists with current protocol/session capabilities.** Call identity exists only as an application field on tagged signals; untagged signals carry no wire-level call identity, and the legacy `sendSignal` relay forwards the map verbatim (`room_session.dart` passes signals through untouched). Rejecting untagged signals would silently reject every old peer, which is explicitly disallowed. Existing state gating (idle/connected checks, duplicate-invite guard) already bounds damage for tagged traffic; it cannot distinguish a *stale untagged* signal from a *current untagged* one.
- **Decision:** keep compatibility. **Boundary:** the late-SDP/ICE/hangup isolation guarantee covers **tagged** signals only; a legacy peer's late untagged signal can still land on a new call — this is unverified/unfixed by design and is **not** claimed as proven. Test `late SDP, ICE and hangup from a previous call cannot mutate a new call` passes (12/12 call bundle). No concrete safe fix was reproduced; no protocol redesign attempted.

## Task 3 — Read-only environment info for later dual-end acceptance

No browser was installed/downloaded; no app was built/installed. All data is read-only observation on 2026-11-18:
- **ADB:** one device `172.17.0.1:14251` (`sdk_gphone64_x86_64`, `emu64xa`, transport_id 1) — an **emulator**, not a physical Z Flip7. adb server daemon running on tcp:5037.
- **Browsers / CDP:** no `chromium`/`chrome`/`brave`/`firefox` executable on PATH or standard locations; no CDP endpoint on 9222/9223/9333. No reusable browser/CDP session exists in this environment.
- **Web / signaling listeners:** no listening web or signaling server currently running (no 8080/8081/3000 listener; `ss -ltnp` showed none). No live WS/signaling URL to attach to.
- **Served build artifact (on disk, not currently served):** `build/web/main.dart.js` + `index.html` + `flutter_service_worker.js` timestamped **2026-11-16 18:43**; `build/web/version.json` = `1.0.40+41`, `package_name=eir`. This is a stale on-disk artifact — **it does not validate current source** and must not be used as current-build evidence.
- **Media fixtures present** for a future Linux harness: `/tmp/eir-short1.mp4`, `short2`, `mid`, `tiny`, `long`, `eir-media-fixture.mp4`, `eir-streaming-large.mp4` (65 MiB), etc.
- Coordination note: Agy owns the current build/install/package; root can coordinate the 60-min dual-end acceptance once a matching-current-source Web+Android build is served. Emulator graphics (EGL black screen) remains a known exemption, not proof of rendering.

## Verification commands & actual results (executed, not inferred)

| Command | Result | Exit |
| --- | --- | --- |
| `flutter analyze lib/core/room_session.dart lib/core/call_session.dart test/core/room_succession_and_playlist_test.dart test/core/chat_and_call_test.dart` | `No issues found! (ran in 1.8s)` | 0 |
| `flutter test test/core/room_succession_and_playlist_test.dart test/media/source_offline_test.dart -r expanded` | `14/14 All tests passed!` | 0 |
| `flutter test test/core/chat_and_call_test.dart -r expanded` | `12/12 All tests passed!` | 0 |

Expected `MissingPluginException(FlutterWebRTC.Method)` lines in call tests are mocked-channel paths; suite exit 0. No source or test file modified.

## Fixes / no fixes

- **Fixes: none.** No ownership/source defect was independently reproduced in the runnable unit scope; per instruction, no speculative patch and no broad exploration/new abstraction.
- Pre-existing callId tagging (prior worker) is preserved and now behaviorally re-confirmed (12/12).

## Gaps — do NOT record as proven

- **No real two-/three-client E2E succession test was run here.** The 4 succession unit tests are comparator simulations, not `RoomSession` state transitions. `deterministic successor` is established by static code trace across the 3 implementations + shared `joinedAt` source, and by the rule-simulation tests — **not** by a live owner-leave → `owner_changed` → role/player E2E assertion in this session.
- **`integration_test/room_session_edge_test.dart` A13/A14** cover real fault injection (source dispose; control-channel down) but need a real integration/display/plugin harness, which is out of this unit-test scope; they were **not** executed. Note a semantic tension to resolve at acceptance: V1-era A14 asserts a member (even admin) gains **no** authority after the owner leaves, whereas current core + both servers implement authority **succession** (admin → earliest join). This was not changed; do not let either side silently override the other without a runtime check.
- **Full replacement-source vs pause E2E** (auto-`switch_item`/`pause` commit actually applied and player observed on both peers after a real source drop) remains unverified here; only the decision logic and the service-level offline feedback are test-proven.
- **callId untagged legacy stale-signal risk** (Task 2 boundary) remains by design; two-peer E2E through both signaling transports untested.
- No real device rendering, no Android foreground service, no six-end plugin `getStats`, no app build/package/publish — all owned by other agents / later acceptance.

## Completion signal to coordinator

Narrow scope complete within budget. Source/tests unchanged; analyze clean; 26 targeted tests pass (14 + 12). Succession/source-offline flow traced and documented with explicit unverified gaps; callId compatibility boundary reported with no breaking change; read-only environment info handed off for the later 60-min dual-end acceptance. This note is the completion marker (no live progress was expected).

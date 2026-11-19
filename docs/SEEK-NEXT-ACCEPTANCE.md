# Eir Seek / Next Business Acceptance — 2026-11-18

- Worker: verified free CodeBuddy `deepseek-v4.1-flash` (`product.json` x0.00 credits, no paid fallback)
- Target: currently serving Web `http://127.0.0.1:8080/` (`version.json` 1.0.40+41; served `main.dart.js` SHA-256 `cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928`)
- Method: two isolated Playwright Chromium contexts, distinct throwaway identities, new private rooms; `**/api/config` intercepted; authoritative local network record (`eir_setting_network_config`) + `ws://127.0.0.1:8080/ws` frozen. Real browser UI + real `<video>` element state. No product source/UI edits, no build/install/publish, no app-data clear, no graphics change.
- Evidence dir: `/tmp/eir-acceptance-seek-next/` (`shots/`, JSON, scripts)

## Verdict

| Scenario | Verdict | Basis |
|---|---|---|
| Seek direction (+10s via ArrowRight) on local static server | **ENV-CAUSED FAIL** (not product) | Both players restarted at 0; local Python server has no HTTP Range |
| Seek direction on Range-capable media host | **PASS** (sync), **FAIL** (magnitude/anchor) | +10s advanced both clients and stayed in sync, but target was anchor+10 = 10.0s, not live+10 = 12.42s |
| Seek business defect: relative target uses stale commit anchor | **REAL BUG** | Live 2.42s → target 10.0s; would seek backward once live position > 10s |
| Natural end → next | **PASS** | short1 (1.6s) ended → both auto-switched to short2; default loopAll wrapped last→first |
| Manual next (playlist "Switch to this item") | **PASS** | Owner switched playing 60s clip → 20s clip; both clients followed, kept playing |
| Member permissions for next/switch | **PASS** | Member B had 0 switch controls; only owner A could switch |

## 1. Seek — what actually happened

### 1a. First reproduction (local `8080` static server) — env-caused restart

Room `277841`, media `http://127.0.0.1:8080/assets/assets/eir_long.mp4` (60s).

- BEFORE (stable, playing): A `ct=2.249` rate `1.0216`; B `ct=2.240` rate `1.0167`; both `dur=60`, `rs=4`.
- One `ArrowRight`:
  - `+214ms`: A `ct=0.106`, B `ct=0.097` — both restarted from 0, not +10s.
  - Then both advanced together from 0; B restarted again at `+2041ms` (`ct=0.04`); A restarted again at `+4162ms` (`ct=0.102`).
  - AFTER snapshot: A `ct=0.138`, B `ct=2.232`.
- The keypress was delivered (playback restarted); this is not control auto-hide or a bad locator.
- Root cause of this reproduction: `serve_eir.py` (Python `SimpleHTTPRequestHandler`) returns `200` with full `content-length` for `Range:` requests and sends no `Accept-Ranges`; seeking forces a re-fetch/restart at 0. Not a product business defect.

### 1b. Decisive re-test (same UI/keypress, Range-capable media host)

Room `894120`, same `eir_long.mp4` served from an in-process Node server on `127.0.0.1:8099` with `206` + `Content-Range`.

- BEFORE: A `ct=2.421` (rate 1.014), B `ct=2.460` (rate 1.011), both `dur=60`, `rs=4`, playing.
- One `ArrowRight`:
  - `+200ms`: A `ct=10.190`, B `ct=10.201`
  - `+3200ms`: A `ct=13.574`, B `ct=13.591`
- Both clients seeked forward together and remained in sync (Δ < 0.02s, stable for 3.2s). **Seek sync PASS**.
- But the jump target was **10.0s**, not live+10 (**12.42s**). This matches `session.playback.position` (commit anchor at play start ≈ 0) + 10s.

### 1c. Real business defect found

`lib/views/cinema_view.dart:361-374` `_seekRelative(int seconds)`:

```dart
final cur = widget.session.playback.position;      // commit anchor, not live position
final dur = widget.session.player.state.duration;
final target = cur + Duration(seconds: seconds);
final targetMs = target.inMilliseconds.clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 0);
```

- `playback.position` is the position at the last commit (`PlaybackState.position` is explicitly "Position at anchorSharedMs", `room_session.dart:169-170`), not the current playback position.
- Consequence: `ArrowRight` seeks to `anchor + 10s`. Once live playback exceeds 10s, the shortcut jumps **backward**; observed target 10.0s from live 2.42s (only +7.58s).
- If `player.state.duration` is 0/unset, the clamp also collapses the target to 0 (the no-Range run could not distinguish this, but the code path is unsafe).
- Suggested fix (owner to implement, not done here): use the live player position (`widget.session.player.state.position`, already used by `play()/pause()` at `room_session.dart:4992` and `play()`), and if duration is zero fall back to the media/live duration rather than clamping to 0. Keep the same sync commit path.
- Owner: business/player logic owner (not UI styling); UI wiring is already correct (key event reaches `_seekRelative`).

## 2. Natural-end → next — PASS

Room `393085`; playlist `[short1 (1.6s), short2 (1.6s)]`, both real playable distinct MP4s from `/assets/assets/`.

- Start: both on `short1`, playing; A `ct=1.134`, B `ct=1.145`, `rs=4`.
- Trajectory: `short1@1.581/1.596` → (A element transiently remounts) → B `short2@0.096` at `+250ms`; both then play `short2` together to `1.6`.
- At last-item end, default `loopAll` (`room_session.dart:771`) wrapped back to `short1` (`t9: short1@0.025/0.066`), then advanced to `short2` again at `t16`.
- AFTER: A `short2 ct=0.762`, B `short2 ct=0.838`, both playing, `rs=4`, same media.
- Evidence: `verify-next.json`, `shots/next-short1-playing-{A,B}.png`, `shots/next-natural-after-{A,B}.png`.

## 3. Manual next — PASS

Room `597848`; playlist `[eir_long (60s), eir_media_fixture (20s)]`.

- BEFORE: A `eir_long ct=1.319` playing (`rs=4`), B `ct=1.261` playing.
- Owner opened Playlist (after revealing auto-hidden controls) and clicked **Switch to this item: eir_media_fixture** (exactly 1 such control, because the other item was current).
- AFTER: A `eir_media_fixture ct=1.640` playing (`rs=4`, rate 1.036); B `ct=1.655` playing (rate 1.033). Switch preserved playing mode and both clients followed the same media.
- Evidence: `verify-manual-next.json`, `shots/manual-before-{A,B}.png`, `shots/manual-after-{A,B}.png`.

## 4. Permissions

- Member B (`MEMBER`) exposed **0** "Switch to this item" controls in the Playlist; only owner A could switch/advance (`verify-next.json`, `verify-manual-next.json`).
- This matches the intended owner/admin control policy. No permission regression observed in these scenarios.

## 5. Script changes / new files

All new files are under `/tmp/eir-acceptance-seek-next/` only; no repository files changed.

- `diag-seek.js` — first seek reproduction with per-150ms sampling of all `<video>` elements, UI state, screenshots.
- `diag-seek2.js` — attempted anchor-vs-duration discrimination; run did not start playback (no Space fallback), retained as an aborted probe.
- `verify-next.js` — natural-end → next with two short distinct media, loop wrap, member control count.
- `verify-manual-next.js` — focused manual switch; first runs used 1.6s clips and were overtaken by natural end, final run uses two long clips.
- `diag-seek-range.js` — in-process Range-capable static server + same one-key seek; decisive run.
- `range-server.js` — standalone Range server (not used as a background process; print mode cannot keep it alive).
- `diag-seek.json`, `diag-seek-range.json`, `verify-next.json`, `verify-manual-next.json` — raw evidence.

Harness adaptations (not product fixes): reveal controls before clicking Playlist (4s auto-hide), wait for the transient `<video>` remount after item switch, use `Space` fallback when the first surface click does not start playback.

## 6. Limitations / not tested

- Only browser contexts were used; native Android/iOS/desktop seek/next were not exercised in this 20-minute slice.
- `**/api/config` was intercepted and signaling frozen to local `ws://127.0.0.1:8080/ws`; production migration behavior was intentionally not tested.
- The local `8080` static server has no HTTP Range support. Any future seek acceptance must host media on a Range-capable origin (as done on 8099) or the result is invalid (restart at 0).
- The slider seek path was not exercised: no `[role=slider]` semantics were exposed while controls were visible, and canvas-coordinate dragging was out of time budget.
- The exact `player.state.duration == 0` branch was not isolated; the anchor defect is proven, the zero-duration clamp is a code-risk observation.
- No product source, UI, build, install, publish, app data, or graphics settings were modified.

## 7. Recommended handoff

- Business owner: fix `_seekRelative` to use live position + safe duration fallback (`lib/views/cinema_view.dart:361-374`), then rebuild Web and re-run the Range-capable seek probe (`diag-seek-range.js`) plus a backward-jump case (play > 15s, ArrowRight must increase, not decrease).
- Acceptance owner: keep media seek tests on a Range-capable origin; the existing `serve_eir.py` cannot validate seek.
- UI owner: no UI defect found for seek/next; only the 4s auto-hide needs a reveal step in automation.

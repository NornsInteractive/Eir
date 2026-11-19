# Dual-Client Acceptance — Preparation Report (READ-ONLY DISCOVERY, NOT AN ACCEPTANCE RUN)

- Prepared: 2026-11-18 by verified-free CodeBuddy `hy3` worker (`product.json` reported `x0.00 credits`, no paid fallback). Root reported Norns already checked; not reconnected, nothing published.
- Nature: **preparation only**. No app build/install/uninstall, no `pm clear`, no graphics-setting change, no download/framework build, no server started, no app or browser launched, no ADB forward/reverse modified, no Agy state/log read, no secret read. No formal 60-min acceptance was executed. Only this file was added.
- Goal: hand Root an **executable** recipe that reuses mature existing scripts/fixtures. Root must confirm current artifacts (§1) before any run; do not run this against the stale `1.0.40+41` product and call it a current-source pass.

---

## 1. BLOCKER — current artifact identity must be confirmed by Agy/Root first

Everything observed below is **not** evidence of current source:

- Device app: `com.norns.eir`, `versionName=1.0.40`, `versionCode=41`, `lastUpdateTime=2026-11-18 14:18:59` (read via `dumpsys package`, **not launched**). Same version number as the old `1.0.40+41` baseline → cannot establish current source.
- On-disk `build/web/version.json` = `{"version":"1.0.40","build_number":"41",...}`; `main.dart.js` mtime 2026-11-18 14:19 — rebuilt recently but **same version string**, so unconfirmed.
- No listener on 8080/8799/8830/8930/8765 at inspection time; nothing currently served to attach to.

Before acceptance, record in the run log (Agy supplies these; do not infer from version number):
1. Android APK path + **SHA-256** + build time + current source commit/head.
2. Web build dir + hashes of `main.dart.js`, `eir_media_bridge.js`, `eir_media_sw.js` (all three must match the same build) + HTTP serve URL(s).
3. Current signaling server build/URL and whether it includes the roomCode-admission change (`server/signaling_server.dart` / `cloudflare/_worker.js`).
4. An explicit statement that these artifacts were built from the current source. Old `1.0.40+41` alone fails this gate.

---

## 2. Read-only discovered environment (inspected; nothing launched or changed)

| Fact | Observation | Method / status |
| --- | --- | --- |
| ADB device | `172.17.0.1:14251`, `sdk_gphone64_x86_64`, `emu64xa`, transport_id 1; emulator, **not** a real Z Flip7 | `adb devices -l` — inspected |
| ADB binary | 1.0.41 / 37.0.0-14910828; server daemon running | `adb version` — inspected |
| Eir app on device | `com.norns.eir`, 1.0.40+41; launchable activity `com.norns.eir/.MainActivityAliasClassic` | `dumpsys package` / `cmd package resolve-activity` — inspected, **not launched** |
| Browsers on device | `com.android.chrome` 113.0.5672.136; `com.brave.browser_nightly` 1.101.34; `com.google.android.webview` | `pm list packages` + `dumpsys` — inspected |
| Other device packages | `com.rom1v.sndcpy` (audio), `com.norns.*`, etc. | `pm list packages -3` — inspected |
| Host browsers on PATH | none (`chromium`, `chrome`, `brave`, `firefox`, drivers all absent) | `command -v` — inspected |
| Playwright browser | `/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome` exists (309 MB); module `/tmp/eir-browser-tools/node_modules/playwright` | file/module check — inspected, **not launched this session** (earlier handoff "no browser on PATH" meant no system/CDP browser; a Playwright-managed Chromium exists) |
| CDP endpoints | none on 9222/9223/9333/9229; no relevant listeners | `ss -ltnp` — inspected |
| ADB forwarding | `adb forward --list` empty; `adb reverse --list` has **pre-existing** `tcp:8080` and `tcp:22023` | inspected, **not modified** |
| Host tooling | Node v24.16.0, Python 3.11.2, `/usr/bin/xvfb-run`, `/opt/flutter/bin/{flutter,dart}`, `ffprobe` at `/home/dev/.local/bin/ffprobe` | `command -v` — inspected |
| Media fixtures | see §4.5 | `ls -lh` — inspected |

**Device graphics waiver (authorized, recorded not fixed):** emulator EGL/`eglCreateContext` black-screen and replay-stall issues are a known exemption (`CURRENT-REPAIR-PLAN.md`, `DUAL-PLATFORM-ACCEPTANCE-ENV.md`). Record it as a waiver; it is **not** a rendering fix and **not** real-phone evidence. Do not claim Z Flip7 / six-end completeness.

---

## 3. Reusable mature tooling — exact paths and commands (for later, not run now)

### 3.1 Signaling + Web (single port, secure-context headers)
`server/signaling_server.dart` serves the compiled Web build **and** WebSocket signaling on one port, with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: credentialless`. These headers do not create a secure context: use loopback HTTP for this development run; public HTTP remains untrusted for APIs requiring a secure context. CLI: `[port] [host] [webRoot]`; host `::`/`anyIPv6` default (dual-stack), webRoot defaults to `build/web`.

```bash
cd /workspace/projects/Eir
# Serve the CURRENT Agy-provided Web build (replace webRoot with the confirmed dir):
dart run server/signaling_server.dart 8080 :: /workspace/projects/Eir/build/web &
# App URL: http://127.0.0.1:8080/   Signaling: ws://127.0.0.1:8080/ws
```

### 3.2 Split static+media server (alternative, used by repo E2E)
`test/web/static_media_server.js` serves Web + same-origin Range media (206/416) but **does not set COOP/COEP** — use only with the secure-context caveat noted; prefer §3.1 for acceptance.

```bash
EIR_WEB_BUILD_DIR=/tmp/eir-web-final-build EIR_WEB_PORT=8730 \
  node test/web/static_media_server.js &
dart run server/signaling_server.dart 8799 127.0.0.1 &
```

### 3.3 Browser harnesses (Playwright + headed Chromium; activate CanvasKit semantics)
Repo harnesses (read `test/web/README.md`):

```bash
# create/invite/join, URL play/pause/seek, local file from owner, admin, settings-no-rebuild, cache:
xvfb-run -a node test/web/e2e_web_validation.js
# A16 real Retry click on SAME URL after SIGKILL of signaling server (WARNING: kills server on given port):
xvfb-run -a node test/web/retry_connection_check.js
```
Env defaults: Playwright `/tmp/eir-browser-tools/node_modules/playwright`, Chromium `/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome`, app `http://127.0.0.1:8730/`, signaling `ws://127.0.0.1:8799`, URL video `http://127.0.0.1:8730/sample.mp4`, local file `/tmp/eir-media-fixture.mp4`. Override with `EIR_PLAYWRIGHT_PATH`, `EIR_CHROME`, `EIR_WEB_APP`, `EIR_SIGNALING`, `EIR_URL_VIDEO`, `EIR_LOCAL_FILE`, `EIR_SHOTS`, `EIR_BUILD_ID`.

Additional existing harnesses in `/tmp` (inspect before use; **hardcoded ports must be re-pointed to the confirmed current serve URLs**):
- `/tmp/eir-join-reject/e2e.js` — create / invite / join / **exit to lobby / rejoin same invite same identity** / third-identity consumed-invite rejection / recovery with a fresh room; hardcoded `APP=8827`, `SIG=8927`. (PASS/FAIL labels: `B-leave-to-lobby`, `B-rejoin-snapshot`, `B-rejoin-playback-recovery`, `C-third-identity-rejected-snackbar`, `C-third-identity-stays-lobby`, `C-failed-then-valid-joins`.)
- `/tmp/eir-open-retest/dual.js` — natural next, EOF replay, mid-play seek, quick switch, URL↔local roundtrip, member join; hardcoded `8830`/`8930`.
- `/tmp/eir-android-join.js` — host browser joins an invite read from `/tmp/eir-android-invite-8765.txt` while an Android client holds the room; hardcoded `8080`/`8765`.
- `/tmp/eir-clock-start-duplex/`, `/tmp/eir-transfer-clock-trace/` — cross-end Web↔App/App↔Web trace harnesses (host member/clock scripts + `web-common.mjs`).

### 3.4 App ↔ browser on the same emulator (two real endpoints)
The device already has both a browser and `com.norns.eir`; two real endpoints can be App + host browser (or App + device browser) connected to the **same** signaling URL. Pre-existing `adb reverse tcp:8080 tcp:8080` lets the App reach `ws://127.0.0.1:8080/ws` on the host server; browser on host uses `http://127.0.0.1:8080/`.

- App signaling URL key: `eir_setting_signaling_url` (`lib/app_settings.dart:22`), default `wss://eir.norns.cc.cd/ws` (`:65`). Web harnesses preset the test URL via `addInitScript` writing `localStorage['flutter.eir_setting_signaling_url']` — this is the only preset state; invites are generated at runtime.
- For the native App, set the URL in **Settings → signaling address** to `ws://127.0.0.1:8080/ws` (record original first, restore after, §6). Do **not** change `session.signalingUrl` at runtime to dodge a reconnect failure.

CDP via ADB forward — **commands only, do not run/modify now** (no CDP endpoint exists at inspection time):
```bash
# Later, choose one device browser and forward its devtools socket:
adb -s 172.17.0.1:14251 forward tcp:9223 localabstract:chrome_devtools_remote      # Chrome
# Brave may use a different localabstract socket; discover with:
adb -s 172.17.0.1:14251 shell 'cat /proc/net/unix | grep -i devtools'
curl http://127.0.0.1:9223/json/version   # verify endpoint; record, then remove what you added in §6
```
Secure-context / fixture caveat: loopback `http://127.0.0.1` is a trustworthy origin, but `file://` fixtures are **not** cross-origin reachable. Serve every fixture from the **same HTTP origin as the app** (signaling server web root or `static_media_server.js` `/sample.mp4`, `/sample-large.mp4`) so App, host browser, and device browser can all fetch/decode it. Host Chromium previously needed `--use-gl=swiftshader --enable-unsafe-swiftshader` and headed Xvfb for a11y semantics — test-environment flags, not a product claim.

### 3.5 Media fixtures (inspected, read-only)
`/tmp/eir-media-fixture.mp4` (3.0M H.264/AAC, ~20 s), `/tmp/eir-business/short-{a,b,c}.mp4` (~175–183K), `/tmp/eir-long.mp4` (463K), `/tmp/eir-streaming-large.mp4` (65M, for chunked/manifest), `/tmp/eir-short1.mp4`, `/tmp/eir-short2.mp4` (22K). Verify with `ffprobe -v error -show_entries format=duration,size -of default=nw=1 <file>`; do not delete or overwrite existing fixtures.

---

## 4. Scenario-by-scenario executable recipe (steps → required evidence → PASS/FAIL)

Convention: a claim is PASS only from **real dual-endpoint evidence** (both clients' real `<video>` state: `currentTime` advances, `readyState>=3`, `paused`, `duration`; real a11y semantics; real wire messages observed via CDP/WS). Control-only traffic, build success, unit/comparator assertions, WARN, or an observation are never a substitute.

**S1 — create / invite / join / exit / rejoin.** Re-point and run `/tmp/eir-join-reject/e2e.js` or the `A-create/A-invite/B-join` part of `test/web/e2e_web_validation.js`. Evidence: invite `eir:*` captured; two independent device ids; playlist snapshot equal on both; exit → B in lobby with no `Playlist(`; rejoin **same invite + same identity** → snapshot restored (not empty `Playlist(0)`), current item and playback recover; third identity with consumed invite gets snackbar rejection and stays lobby with no P2P; recovery via fresh valid invite succeeds. FAIL on empty playlist after rejoin, or third identity silently admitted.

**S2 — raw roomId without token rejects; valid roomCode joins under CURRENT server.** Two layers, both required:
- Server admission (unit, real WS clients): `flutter test test/core/signaling_server_test.dart` (room-code resolves credential; roomId-only no token never authorized; explicit token validated even with valid code; conflicting code+id rejected; stale epoch rejected) and `node --test test/cloudflare/signaling_worker_test.mjs` (6 cases). These are **unit-level**, not product UI.
- Product E2E against the confirmed-current server: create a room; read the 6-digit `roomCode` and the raw `roomId`/device id via Session Info (`/tmp/eir-android-join.js` extracts UUID room + 64-hex device); join with **roomCode only (no token)** → success and media sync on both endpoints; attempt join with **raw roomId and no token** → visible rejection, client stays in lobby, no P2P/playlist. FAIL if raw roomId auto-authorizes. Run this only on the server whose admission code was confirmed in §1.

**S3 — local file offered from both roles.** Owner offers a local MP4 → guest decodes (repo harness `local-filechooser`, `local-add-sync`, `local-decode-A/B`, `local-src-container`); then the **other role** (admin/member or device App) offers a local MP4 → first endpoint decodes (`/tmp/eir-clock-start-duplex/` / `/tmp/eir-transfer-clock-trace/` for Web↔App direction). Evidence on both ends: `src` blob/expected ext, `readyState>=3`, `currentTime` advances, no error. Control-only transfer or one-side-only decode is **not** a pass. Then exercise S6 source-offline on a member-owned item.

**S4 — URL-synced play / pause / seek / speed / next.** URL added by owner → both decode (`url-add-sync`, `url-decode-A/B`, `live-progress-semantics`); play, pause holds position (`pause-holds`), seek to ~30% jumps both within tolerance (`seek`), speed change reflected on both, natural next advances on EOF (`/tmp/eir-open-retest/dual.js` `NATURAL-A-to-B-autoplay`, `QUICK-switch-final-B`). **Coverage gap:** repo harness has no speed assertion — verify speed with a dedicated script/manual observation and record it as inspected-only if no real dual-end assertion exists. Do not count position-only or byte-count-only evidence as playback.

**S5 — settings visible and do not destroy the room.** `test/web/e2e_web_validation.js` `settings-open`, `lang-switch-zh`, `theme-independent-colors`, `theme-no-session-rebuild`; mirror on device App (language/theme, light/dark accent independent). Evidence: `roomBefore==roomAfter`, membership unchanged, connection still up. Also check the previously-fixed plain-HTTP-settings-blank case against the current Web artifact. FAIL if room/connection/membership change or settings crash.

**S6 — REAL RoomSession owner-departure succession + local-source offline fallback/pause.** The 4 succession tests in `SESSION-SUCCESSION-HANDOFF.md` are **comparator simulations**, not RoomSession E2E — do not count them. Required real run: split two independent scenarios: (a) owner + member in one room, owner leaves → remaining member observes real `owner_changed{newOwnerDeviceId,previousOwnerDeviceId}` (successor = admin first, then earliest `joinedAt`, online candidates only), new owner starts room timers/P2P re-offer, ; (b) member owns a local file currently playing, member leaves/disposes while owner remains → no owner change is expected, and the offline-sourced current item switches to the next playable item at position 0 / playing, **or publishes pause if none playable** — with no stale/offline playback (`room_session.dart:1667-1736`, `:1746-1769`). Evidence: both endpoints' real state + player `currentTime`/`paused` + wire capture. **Rule conflict — Root must decide, not silently override:** V1 A14 (`V1-ACCEPTANCE.md`, `integration_test/room_session_edge_test.dart`) asserts a member gains no authority after owner leaves, while current core + both servers implement authority succession. Assert whichever Root rules authoritative; record the other as a known deviation.

**S7 — current-call tagged stale-event boundary + projection start/stop/stats (where possible).**
- Call: `flutter test test/core/chat_and_call_test.dart` includes `late SDP, ICE and hangup from a previous call cannot mutate a new call`. Boundary: isolation is guaranteed for **tagged** signals only; untagged legacy signals are accepted for compatibility and a stale untagged late signal can still land on a new call — report as **by-design unverified**, not a pass. Two-peer E2E through both signaling transports is still a gap.
- Projection: `flutter test test/core/screen_share_service_test.dart` covers stop-during-pending-capture, stop/restart isolating stale tracks/ICE/SDP/callbacks, dispose stopping tracks/PC/Android projection service, real `getStats` sampling with explicit unavailable, missing metrics staying null (no fake zero), and slow old-PC stats not overwriting new state. On-device (if Agy's stats UI is ready): real screen-share start/stop with no leaked track/foreground service, and stats UI showing `rttMs`/`bitrateMbps`/`packetLoss` as **nullable** (missing = blank, never 0). If UI/device not ready, mark not-tested; do not fabricate zeros.

**S8 — A15/A16 reconnection (per standing acceptance rule).** A15/A16 require the **original** signaling endpoint to be stopped and restarted on the **exact same URL/port**, with existing sessions recovering without an address change. Never change `session.signalingUrl` to a new endpoint (that tests migration, not original-service restart), never relax an assertion to get green. For A16 the manual-retry case must use a **real click on the product Retry entry** (`test/web/retry_connection_check.js`): if the button never appears → FAIL; after server recovery, first assert the app **still shows disconnected with the Retry button present**, then click and verify original room/identity/playlist plus dual-end decode/control. Auto-recovery is never recorded as a pass. Observational WARNs must be converted to explicit PASS/FAIL assertions. Graphics waiver (§2) is recorded, not treated as a fix.

---

## 5. Tested vs inspected — explicit distinction

- **Inspected this session (read-only):** ADB device/version/browser package lists; absence of PATH browser/CDP/listeners; pre-existing forward/reverse; Playwright Chromium binary and module existence; media fixture sizes; `build/web` version + mtime; repo/`/tmp` script contents; source settings key/default; server CLI. No script was executed as an acceptance run.
- **Executed earlier by other workers — NOT by this session, NOT current-source E2E:** Dart 361/0/0 + CF Node 6/0/0 (`FINAL-BUSINESS-TEST-HANDOFF.md`); succession 14/14 + call 12/12 unit (`SESSION-SUCCESSION-HANDOFF.md`), of which 4 succession tests are comparator simulations. These are evidence of unit behavior only.
- **Not tested / open gaps:** any real dual-endpoint run on current artifacts; raw-roomId-vs-roomCode product E2E; member→owner local-file offering; speed dual assertion; real RoomSession succession/source-offline; projection on-device stats; untagged legacy call isolation; real-phone rendering. None may be written as proven.

---

## 6. Snapshot / restore of any later intentional changes (no destructive reset)

Before changing anything during the future run, snapshot and record; restore afterwards. **Never** `pm clear`, uninstall, factory reset, delete media fixtures, or alter emulator graphics settings.

```bash
D=172.17.0.1:14251
adb -s $D reverse --list            # restore pre-existing tcp:8080, tcp:22023; remove only entries we add
adb -s $D forward --list            # currently empty; remove only what we add (e.g. tcp:9223)
adb -s $D shell dumpsys package com.norns.eir | grep -E 'versionName|versionCode|firstInstallTime'  # identity unchanged
ss -ltnp                            # record ports we start; stop our servers by PID
```
- App settings: record original signaling URL, language, theme, light/dark accent via the Settings UI (do not read private pref files); restore the original signaling URL afterward. Web harness state is only the `flutter.eir_setting_signaling_url` test URL in a throwaway browser context — no product data touched.
- Room identity/history: record original Session Info; do not clear app data. Servers started by the recipe are stopped by their recorded PID; port forwards/reverses added by the recipe are removed with `adb -s $D reverse --remove <local>` / `adb -s $D forward --remove <local>`, leaving the two pre-existing reverses intact.
- Keep only the current target APK locally if a build occurs (`rm -f eir-v*.apk`), but building/installing is **out of scope** for this prep task.

---

## 7. Handoff / next action

1. Root receives current Android+Web artifact identity (§1) from Agy (version/build fingerprint + serve URLs) and confirms they are from current source.
2. Only then, within the authorized 60-min dual-acceptance window, run §3–§4 against those artifacts (App+browser and/or two host browser contexts), capturing real dual-end evidence per scenario.
3. Report PASS/FAIL/NOT-TESTED with evidence paths; keep the graphics waiver and real-phone gap explicitly recorded. Nothing in this document is a current-source acceptance result.

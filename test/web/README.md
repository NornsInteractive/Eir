# Eir Web product E2E harness

Reproducible two-context browser E2E for the real Eir Web product build.
It exercises the actual product UI (CanvasKit renderer + native Flutter
semantics) against a real signaling server, with no FakeRoomSession, no injected
business state, and no product test hooks. All pass/fail evidence comes from real
browser media state (`<video>.currentTime`, `readyState`, `paused`, `duration`)
and real accessibility semantics values.

## Files

- `static_media_server.js` — serves the compiled build and exposes loopback
  media fixtures at same-origin URLs with HTTP Range (206/416) so decoding and
  seeking work without CORS.
- `e2e_web_validation.js` — the E2E. Creates two independent persistent browser
  contexts (owner + guest), joins them over a real signaling server, and verifies:
  - create / copy-invite / join, two trusted peers, membership sync
  - guest read-only enforcement
  - URL video shared playback: both ends decode and advance
  - live Playback Progress semantics tracking the real player position
  - play / pause (holds) / seek (jumps) on the owner
  - local MP4 shared over P2P: guest decodes the P2P-delivered media
  - admin grant / revoke and admin control reflecting on the owner
  - language switch, dark mode, independent light/dark accent colors
    WITHOUT rebuilding the room (room id / membership / connection unchanged)
  - cache occupancy display and safe cache clean feedback
- `retry_connection_check.js` — A16 recovery with hard assertions: connects two
  contexts, plays shared media, SIGKILLs the signaling server by real PID
  (non-graceful, SAME URL), and waits for bounded auto-retry exhaustion. It then
  **requires the real Retry Connection button to appear**, restarts the SAME URL
  and **asserts the app does NOT silently auto-recover**, performs a **real click**
  on the product retry entry, and verifies room/identity/playlist preservation plus
  real dual-end decode and shared control after recovery. Auto-recovery is never
  accepted as a substitute for the click; the script exits 2 on any hard FAIL.
  It also records a local two-context position deviation sample (NOT a
  remote-latency or frame-accuracy measurement).
  WARNING: it kills/restarts the loopback signaling server on the given port.

## Prerequisites

- Flutter SDK (Web build), Dart (signaling server).
- Node.js and Playwright with a Chromium binary. Point `EIR_PLAYWRIGHT_PATH` and
  `EIR_CHROME` at them if not in the defaults.
- An H.264/AAC MP4 fixture for the local-share test (default
  `/tmp/eir-media-fixture.mp4`, ~3 MiB / 20 s).

## Steps

```bash
# 1. Build the product Web output (real entry: lib/main.dart)
cd /workspace/projects/Eir
flutter build web --release --output=/tmp/eir-web-final-build

# 2. Signaling server (memory-only, loopback)
dart run server/signaling_server.dart 8799 127.0.0.1 &

# 3. Static + media server
EIR_WEB_BUILD_DIR=/tmp/eir-web-final-build EIR_WEB_PORT=8730 \
  node test/web/static_media_server.js &

# 4. Run the E2E (headed under Xvfb so Chromium exposes Flutter semantics)
xvfb-run -a node test/web/e2e_web_validation.js

# result: /tmp/eir-web-test/e2e-result.json  (+ screenshots in EIR_SHOTS)
```

## Notes

- Flutter Web (CanvasKit) only builds its accessibility/semantics tree after an
  accessibility client connects. The script activates it by dispatching a click
  on `flt-semantics-placeholder`, and runs headed under Xvfb so Chromium enables
  a11y. Without this, role/text locators find nothing (the UI is canvas pixels).
- The only preset state is the test signaling URL stored in localStorage under
  `flutter.eir_setting_signaling_url` (a documented app preference). Invites are
  generated at runtime and never printed or persisted.
- Loopback only; no secrets, no external network, no publishing.

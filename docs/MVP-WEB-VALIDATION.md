# MVP Web End-to-End Validation Report

- **Owner of this report:** Web validation wheel (CodeBuddy `deepseek-v4.1-flash`, free,
  `credits=x0.00`, no paid fallback).
- **Date:** 2026-11-07 (Asia/Shanghai).
- **Scope:** Real product entry `lib/main.dart` compiled to Web, driven in **two truly
  independent browser contexts** against a **real signaling server**, exercising the actual
  product UI. No `FakeRoomSession`, no injected business state, no product test hooks.
  Evidence is real browser media state (`<video>.currentTime / readyState / paused /
  duration`) plus real accessibility semantics values.

---

## 1. OVERALL STATUS

| Area | Result |
|---|---|
| Full two-context E2E (28 items) on the FINAL W3-fixed build | **PASS 28 / FAIL 0 / WARN 0** |
| Retry Connection via real product UI after non-dissolving signaling restart | **PASS 18 / FAIL 0 / INFO 1 — W3 CLOSED** |

The 28-item product E2E passes on the official W3-fixed build. The previously reported A16
defect **W3 is fixed and re-verified on the real product**: after a genuine SIGKILL of the
signaling server and bounded auto-retry exhaustion, the **real Retry Connection button
appears**, the app **does not silently auto-recover** when the same URL returns, and a
**real click** on the product button restores the original room/identity/playlist with
real dual-end decode and shared control.

---

## 2. Build provenance (FINAL W3-fixed source)

| Item | Value |
|---|---|
| Entry | `lib/main.dart` |
| Build cmd | `flutter build web --release --output=/tmp/eir-web-final-build` |
| Build time | 2026-11-07T09:14:29+08:00 |
| `main.dart.js` sha256 | `764e546bad0a9aed919722067525f334a84dfeb3f613f1d449f70b0fd0fec057` |
| `.last_build_id` | `23ebd0fa7f6d36acf78f89e98bda0585` |
| `lib/main.dart` | `186a1d2801e41865990088ddb989aa7a684176e1ff8825b5689136e62594558f` |
| `lib/core/room_session.dart` (W3 fix) | `bbe182e3febc2e862a1f37a09e249befaf3e9983b662e89ec86a504c170ae6ff` |
| `lib/views/cinema_view.dart` (UI Rev3) | `dd68324da4a24366109d41344a8c8e9234ba8a48129022ba283b4741107ba136` |
| `lib/views/settings_dialog.dart` | `52bd4c01cf3bec5515dfb6c08f1b852e7543fbb0bd59d577ee1306376b03627b` |
| `lib/app_localization.dart` | `7f018c330a4998ee91de29e02ef400b78d2a43dbc05d649a68d4ce7b9a428b7a` |
| `lib/media/**` (all dart) | `65c0c38bd88e8d83388135db9d037d8879a7bdbc151fa07296307afea932ef90` |
| `lib/**` (all dart tree, per-file hash method) | `1a2587e790d9a63938faf8520f531fc5ab70cf108331b5bd8e33858d02c1b0a8` |

`dart analyze lib` → **No issues found!** before build.

**Source-delta check:** compared with the previous 05:26 tested snapshot, the *only* changed
file is `lib/core/room_session.dart` (`3a840c81… → bbe182e3…`, the W3 fix). `main.dart`,
`cinema_view.dart`, `settings_dialog.dart`, `app_localization.dart` and the whole `lib/media`
tree are byte-identical to the previously validated snapshot. Provenance note: the core
handoff records a `lib/**` aggregate tree hash of `a3c34013…`; recomputing with every documented
`find` variant on the current tree yields `8f2eab97…`. The **per-file** hashes (authoritative
here) match exactly, so the build is the intended W3 source; the aggregate discrepancy is a
bookkeeping-method difference, not a source mismatch.

---

## 3. Norns MCP pre-check (per AGENTS.md)

Read-only `initialize` + `tools/list` against `https://norns.cc.cd/api/mcp` with the
coordinator's configured bearer token (read programmatically, never printed). HTTP 200, 41
tools, project tools present. No publish/preview. No secrets logged.

---

## 4. Environment

| Component | Value |
|---|---|
| Browser | Chromium 1254 `/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome` |
| Driver | Playwright 1.65.0 `/tmp/eir-browser-tools/node_modules/playwright` |
| App host | `http://127.0.0.1:8730/` (loopback static server, same-origin media) |
| Signaling | `dart run server/signaling_server.dart 8799 127.0.0.1` (loopback, own port) |
| URL fixture | `http://127.0.0.1:8730/sample.mp4` (H.264/AAC, 20 s, 3 MiB; Range 206) |
| Local fixture | `/tmp/eir-media-fixture.mp4` (H.264/AAC, 20 s, 3 MiB) |
| Flags | `--no-sandbox --disable-dev-shm-usage --autoplay-policy=no-user-gesture-required --use-gl=swiftshader --enable-unsafe-swiftshader`; headed under xvfb so Chromium a11y engages |

Semantics activation: dispatch a click on `flt-semantics-placeholder` (Flutter Web only builds
its AX tree when an a11y client connects). Text entry must be a real canvas click on the field
(DOM `.focus()`/`fill()` bypasses Flutter's editing host and is not used).

---

## 5. Full E2E results (28 items, FINAL W3-fixed build)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1-6 | create / identity / invite / join / independent ids / membership | PASS | P2P Connected; `Peers & ACL (2)` both |
| 7 | guest read-only | PASS | read-only controls present; no plain Play |
| 8-9 | URL add + playlist sync / media load | PASS | `Playlist (1)` both; `<video>` dur=20 rs=4 |
| 10-11 | URL decode A / B | PASS | A 1.43→5.44 s, B 1.44→5.44 s, rs=4 |
| 12 | live progress semantics | PASS | `00:01/00:20 (6%)` → `00:05/00:20 (26%)` |
| 13 | pause holds | PASS | paused=true, 5.47→5.47 s |
| 14 | seek | PASS | 30% → 5.91 s |
| 15-18 | local file chooser / add sync / decode A / decode B (P2P) | PASS | A 1.95→5.95 s, B 1.96→5.96 s, rs=4; B src `/eir-media/<id>` |
| 19-22 | admin grant / read-only cleared / control reflects / revoke | PASS | Revoke appears; B pause → A paused (10.30→10.42 s); revoke restores read-only |
| 23-26 | settings / zh lang / independent accents / no rebuild | PASS | room id + membership + P2P stable |
| 27-28 | cache occupancy / safe clean | PASS | `3.0 MB / 512 MB (1%)`; `No unprotected cache to clean (in-use cache preserved)` |

**Summary: pass=28 fail=0 warn=0.**

---

## 6. Retry Connection (A16) — W3 fix verified on the real product

Method (`test/web/retry_connection_check.js`): two contexts, real signaling on 8799, URL
playing on both ends; **SIGKILL the signaling server by real PID** (non-graceful, same URL),
confirm TCP down; wait for bounded auto-retry exhaustion; restart the **same URL** and assert
the app does **not** silently auto-recover; then **click the real product retry button**;
verify preservation and dual-end decode/control.

Observed (18 PASS / 0 FAIL / 1 INFO):

| Phase | Result |
|---|---|
| SIGKILL real PID, TCP down, same URL, no disband | PASS |
| Bounded exhaustion → real `Retry Connection` button + terminal disconnected banner | PASS at **t=8 s** |
| Same URL restarted → **still disconnected after 12 s (no auto-recovery)** | PASS |
| Real click on `cinema-retry-connection-btn` → button/banner cleared, reconnected | PASS |
| Guest B also exposed the retry entry → real click, recovered | PASS |
| Room id preserved | PASS `04b90a8e… → 04b90a8e…` |
| Device identity preserved | PASS `6ee1823c… → 6ee1823c…` |
| Playlist preserved | PASS `Playlist (1) → Playlist (1)` |
| Post-recovery real dual-end decode | PASS A 0.22→5.68 s, B 0.22→5.68 s, rs=4 |
| Post-recovery shared control (A pause) | PASS A paused=true, B paused=true |

Auto-recovery was **not** accepted as a substitute for the click: the test hard-fails if the
retry entry disappears after the endpoint returns, or if the button never appears.

Position deviation sample during normal buffered dual-end playback: max |A−B| = **0.01 s**
over 6 samples. **This is local two-context sampling/estimate latency only — NOT a remote
150 ms or frame-accuracy measurement.**

---

## 7. Defects

1. **W1** `settings_dialog.dart` syntax error — fixed by UI, **verified closed** (build success).
2. **W2-COMPILE** `cinema_view.dart` undefined `PlaybackState.duration` — fixed, **verified closed**.
3. **W2-LIVE-PROGRESS** semantics value frozen — fixed, **verified** (tracks 6%→26% / 7%→27%).
4. **W3 — Retry Connection button unreachable — FIXED, RE-VERIFIED CLOSED (owner CORE F1–F5).**
   Root cause was two coupled defects: exhaustion never set `connectionState = disconnected`,
   and the failed-attempt callback could reschedule/double-count so the loop silently revived.
   Core fixed both in `lib/core/room_session.dart` (`_reconnectExhausted` terminal flag,
   callback gating, retry-failure stays retryable, reset on room state changes). Verified on
   the W3-fixed build: button appears at t=8 s, no auto-recovery after same-URL restart, real
   click recovers with room/identity/playlist preserved and real dual-end decode/control.
   Detail in `/tmp/eir-web-code-issues.md` (ISSUE W3 → CLOSED).

No open Web defects remain.

---

## 8. storage_full (not runtime-tested on Web — by design)

`storage_full` is not produced by the Web media path, so it was **not** faked or injected.
Localization/wiring verified **statically** only:
- `lib/app_localization.dart:184` — zh "存储空间不足，无法缓存该视频，请清理空间后重试" /
  en "Not enough storage to cache this video. Free up space and try again".
- `lib/views/cinema_view.dart:669,690,699` — error banner + `cinema-storage-full-clean-btn`.
- `lib/views/settings_dialog.dart:590-605` — storage warning in the cache section.
No runtime claim is made for storage_full on Web.

---

## 9. Freeze / status

- Core W3 fix frozen at `room_session.dart bbe182e3…` (see `/tmp/eir-core-w3-ready.txt`);
  UI Rev3 `cinema_view.dart dd68324d…`; media tree `65c0c38b…`; final Web artifact
  `main.dart.js 764e546b…` (09:14:29).
- Both Web suites pass on this build; W3 is closed. The tested Web artifact is ready for the
  build wheel to merge with the matching source hashes above.
- Not re-verified here (out of Web scope): Windows/macOS/iOS runtime, real-network
  auto-recovery timing, TURN/symmetric NAT, performance thresholds.

---

## 10. Reproduction (no secrets)

```bash
cd /workspace/projects/Eir
flutter build web --release --output=/tmp/eir-web-final-build
dart run server/signaling_server.dart 8799 127.0.0.1 &
EIR_WEB_BUILD_DIR=/tmp/eir-web-final-build EIR_WEB_PORT=8730 node test/web/static_media_server.js &
xvfb-run -a node test/web/e2e_web_validation.js        # 28-item product E2E
xvfb-run -a node test/web/retry_connection_check.js    # A16 retry / recovery (kills+restarts own 8799)
```

Artifacts: `/tmp/eir-web-test/e2e-result.json`, `retry-result.json`, logs
`e2e-w3.log`, `retry-w3.log`, screenshots under `/tmp/eir-web-test/shots/` and
`retry3-*.png`. Scripts: `test/web/{e2e_web_validation.js,retry_connection_check.js,
static_media_server.js,README.md}`. Ledger: `/tmp/eir-web-code-issues.md`.
No invites, tokens, or keys are printed or stored.

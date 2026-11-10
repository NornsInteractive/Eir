# Eir MVP — Build / Install / Test Status (build wheel)

> 本文主体为历史构建快照，以下哈希及通过结论不能代表当前源码。最新修复、Android 调试包及验收进度以[当前业务修复计划](CURRENT-REPAIR-PLAN.md)为准；Android 视频输出与片尾重播尚未完成验收。
>
> 现有用户设备禁止执行可能卸载应用的Android `flutter test -d`。以下历史命令仅留作追溯；设备验收使用保留数据的`adb install -r`及真实UI操作，自动集成测试只能使用隔离包/专用无用户数据设备。当前测试、构建和安装由主代理负责，UI 修改交由 Agy。

- **Owner of this doc:** Build wheel — CodeBuddy `hy3` (free continuation). No paid fallback. No publish.
- **Date:** 2026-11-07 (Asia/Shanghai). **Native-refresh addendum** after UI re-freeze (W1 syntax fix +
  A11y); a **static six-platform config-review addendum (§12)**; **final native acceptance round 1
  (§13)**; and the **W3 refresh (§14)** — Android/Linux/Windows rebuilt from the W3-frozen core and
  re-verified. Final all-pass `build-ready` is written only after the separate Web worker reports on the
  FINAL frozen source with W3 closed. **No all-platform pass is claimed.**
- **Scope of build wheel:** compile, install, run, all platform tests, environment/config/dependency/packaging.
  Does **not** modify `lib/core`, `lib/media`, product UI, or the web media bridge. Product-code defects
  are reported to their owners (core / media / Agy), never patched here. No publish / no external upload.
- **Frozen code states:** core **W3** (`/tmp/eir-core-w3-ready.txt`; supersedes F1–F5/edge),
  media F5 (`/tmp/eir-media-final-fixes-ready.txt`), UI Rev3 (`/tmp/eir-ui-ready.txt`), config
  (`/tmp/eir-platform-config-ready.txt`) — all present and frozen at build time.

---

## 0. Native refresh (this addendum)
- UI re-frozen: `settings_dialog.dart:551` W1 missing-`)` syntax fix (4-level Semantics/Tooltip/
  GestureDetector/AnimatedContainer nest closed); comprehensive A11y Semantics added across CinemaView,
  LobbyView, SettingsDialog, playlist & member controls (ValueKeys + labels, zh/en, read-only vs enabled).
- UI change set (mtime 03:55–04:08): `lib/app_localization.dart`, `lib/views/lobby_view.dart`,
  `lib/views/cinema_view.dart`, `lib/views/settings_dialog.dart`. Purely presentation — core/RoomSession
  and transport unchanged.
- `flutter analyze` (full) → **No issues found!**; UI/widget tests (`test/ui`, `test/widget_test.dart`,
  xvfb) → **8/8 pass** (incl. lobby create/join, member read-only vs host/admin controls, playlist ops,
  disband, ACL grant/revoke, settings persistence, theme/language no-session-recreate).
- **All three native artifacts rebuilt from the new UI source** (Linux release, Android APK, Windows
  release via the independent 3.44.2 SDK). New checksums in `PLATFORM-MATRIX.md` / `artifacts/mvp/checksums`.
- Heavy core RoomSession integration tests were **not** re-run (UI-only change, net/core unaffected);
  their prior pass evidence is reused and still valid.

## 1. Toolchain / versions (measured)
- Flutter **3.44.2** (stable), Dart **3.12.2** (Linux host SDK and Windows independent SDK
  `C:\eir-build\mvp-9f90d90269\flutter-sdk`).
- Host OS: Linux (x64, GTK). Android emulator 127.0.0.1:14251 (Android 14 / API 34, x86_64).
- Windows build host: Windows **Server 2025 Standard** (SSH 127.0.0.1:14320, ED25519, builder).
- Web: Chromium 1254 (Playwright); product build by Web worker to `/tmp/eir-web-final-build`.

## 2. Static analysis & unit tests (host, final source)
- `flutter analyze` → **No issues found!** (exit 0). Test-only fix this session: `FakeRoomSession`
  implements the V1 §9 cache API abstract members core added; removed an unused import. No product code.
- `flutter test test/core test/media test/ui test/widget_test.dart` (xvfb) → **113 tests passed** (exit 0):
  core 74, media 31, ui/widget 8.

## 3. Linux (x64, GTK) — FULL PASS (rebuilt post-UI-fix)
- **Build:** `flutter build linux --release` → success (`eir` launcher + `lib/libapp.so` rebuilt 04:19,
  contains new UI AOT).
- **Real Secret Service startup:** isolated `gnome-keyring-daemon` test profile (not user keyring);
  `SECRET_SERVICE_OK`; product initialized identity against live Secret Service, no crash.
- **Real RoomSession integration (reused prior evidence, UI-only change):** url 2/2, local 2/2,
  streaming-proof 1/1; 113 unit tests pass.
- Reproduce: `xvfb-run -a flutter test integration_test/<name>.dart -d linux`

## 4. Android (emu 127.0.0.1:14251, API 34 x86_64) — FULL PASS (rebuilt post-UI-fix)
- **Build:** `flutter build apk --debug` → success (rebuilt 04:20). Manifest carries ACCESS_NETWORK_STATE
  + INTERNET; no camera/mic permission requested.
- **Install/run:** installed & ran on live emulator; no native crash.
- **Real RoomSession integration (reused prior evidence, UI-only change):** `room_session_url_test` 2/2
  (base room + concurrency/ACL — core fix verified on-device); `room_session_local_media_test` 1/1.
- Reproduce: `GRADLE_USER_HOME=/tmp/eir-gradle-home flutter test integration_test/room_session_url_test.dart -d 127.0.0.1:14251`

## 5. Windows (x64) — BUILD PASS (new UI), RUNTIME BLOCKED (host)
- **Build:** final source synced cleanly to `C:\eir-build\mvp-9f90d90269\src` (tar excludes
  build/.dart_tool/.gradle/ephemeral/Pods/.plugin_symlinks/.git/artifacts + machine config); `flutter pub
  get` ("Changed 5 dependencies!") + `flutter build windows --release` → success; AOT `data/app.so`
  rebuilt (7.49 MB, contains new UI). Artifact pulled to `artifacts/mvp/windows`.
- **Runtime — BLOCKED, with evidence (NOT a code defect):** `eir.exe` loader 0xC0000135; `flutter_windows.dll`
  hard-imports `OPENGL32.dll`; `OPENGL32.dll` absent on host (`exists=False`, err=126; all other deps OK).
  Host Server 2025 Standard / Server Core: no Desktop-Experience/Server-Gui-Shell payload; no GPU/display.
  Build worker is admin but cannot self-resolve. **Remediation = user provisioning** (Windows Desktop
  GUI+OpenGL host, or install Desktop Experience — admin+reboot, payload absent here). User's decision on
  a desktop Windows environment is still pending and is **not** treated as waived.
- On-device `flutter test -d windows` also fails ("Unable to start the app on the device") — same no-display
  reason. The delivered release bundle runs on a proper Desktop OpenGL host.

## 6. Web (JS) — BUILD PASS (new UI), E2E PENDING separate worker
- **Build:** product `lib/main.dart` built to `/tmp/eir-web-final-build` (artifact refreshed in
  `artifacts/mvp/web`; `main.dart.js` + `eir_media_bridge.js` + ServiceWorker). Production
  `LocalMediaService.start()` injects `eir_media_bridge.js` at runtime (no `web/index.html` change needed).
- **E2E:** owned by a separate CodeBuddy `hy3` Web worker — two independent-browser-context product E2E
  (identity/init, create-invite-join, URL + local MP4 decode play/pause/seek/ACL, theme-language session
  retention, browser secure storage). Result + evidence (`docs/MVP-WEB-VALIDATION.md`, `/tmp/eir-web-ready.txt`)
  merged here after the worker reports. Build wheel does NOT re-run Web E2E nor overwrite the worker's scripts/docs.

## 7. macOS / iOS — not testable here
- macOS: user-paused; untested. iOS: no macOS/Xcode host; untested. Both reported as untested, not passing.

## 8. Norns MCP (read-only, security policy)
- `initialize` → 200, protocol `2024-11-05`; `tools/list` → 200, 41 tools (incl. project tools).
- Token read at runtime only from `/home/dev/.codex/config.toml`; never printed, never written to repo/
  prompt/log. Gateway requires `User-Agent: Codex-MCP/1.0` (403 otherwise) — handled.
- **No** publish / preview / release performed. **No** other-product scripts executed.

## 9. Honest gaps / scope limits
- Windows runtime & on-device integration test: blocked by Server-Core missing `OPENGL32.dll` (host limit).
- Web E2E: pending dedicated Web worker report.
- STUN-only signaling; no TURN relay (out of agreed v1 scope).
- macOS/iOS: untested (paused / no host).
- Android fixture-streaming 2nd case & 65 MiB streaming proof: host-fixture limits (verified on Linux).

## 10. Artifacts (artifacts/mvp/)
See `PLATFORM-MATRIX.md` for the sha256 table. Current checksums:
```
android/app-debug.apk      401c0893337250388c28c3d6827bee576ae9dfd896289fd05a9337c628c5cd5e
linux/eir                 2a2c0f56f58774728664900e5ef27865f8ee61533551cffa9fc8af0102dabcc1
linux/lib/libapp.so       1b9d53467e91120c77dc152532f725377cda9b17ebeece321d191fd5daa10303
windows/eir.exe           568b945586ab10f4c2f9fefb976ec5c0e42d177019c64a25e9013b85b5012629
windows/data/app.so       2fe5d26e7a3619a12abcb1276df0c45f2f39fa73ec5fc55b8fe082bc99149be7
web/main.dart.js          d3ae2ce0559bc06666495e716fbe443517dc8d26fb543d16827f992afe38e66a
```
Layout: `android/ linux/ windows/ web/ logs/ checksums/ old/` (old = stale Nov-6 pre-fix artifacts).

## 11. Reproducible commands (summary)
```
flutter analyze
xvfb-run -a flutter test test/core test/media test/ui test/widget_test.dart
# Linux
flutter build linux --release
xvfb-run -a dbus-run-session -- bash eir-linux-run.sh
xvfb-run -a flutter test integration_test/room_session_{url,local_media,streaming_proof}_test.dart -d linux
# Android
tool/android_debug_apk.sh                      # installable debug APK (lib/main.dart, all ABIs) + verify + publish
tool/android_debug_apk.sh verify <apk>         # reject test/emulator APKs before sharing
GRADLE_USER_HOME=/tmp/eir-gradle-home flutter test integration_test/room_session_url_test.dart -d 127.0.0.1:14251
# NOTE: `flutter test -d <android>` overwrites build/app/outputs/flutter-apk/app-debug.apk with its
#       test APK (x86_64-only engine, test entrypoint). Never install or share that path.
# Windows (SSH builder, secret via sshpass -d)
python3 /tmp/eir-windows-final.py sync-build     # clean sync + pub get + build windows --release
# Web: product build done; E2E by separate Web worker
```

## 12. Platform static config review (config owner; static only — NOT a runtime pass)
- **Scope of this section:** static configuration + delivery docs only. **No** Flutter native
  compile / integration / install; **no** build/linux contention; **no** edits to `lib/core`,
  `lib/media`, product UI, web bridge, tests or pubspec. No publish. Full record:
  `/tmp/eir-platform-config-ready.txt`.
- **Config files changed (only these):**
  - `macos/Runner/Release.entitlements` — added `network.client`, `network.server`,
    `files.user-selected.read-only` (all three were missing; Release previously had only `app-sandbox`).
  - `macos/Runner/DebugProfile.entitlements` — added `network.client`, `files.user-selected.read-only`
    (kept `app-sandbox`, `cs.allow-jit`, `network.server`).
  - `ios/Runner/Info.plist` — added `NSLocalNetworkUsageDescription` (WebRTC LAN P2P, iOS 14+).
  - All edited plists re-parsed with Python `plistlib` → OK. Entitlement wiring confirmed in
    `macos/Runner.xcodeproj/project.pbxproj` (Debug/Profile → DebugProfile; Release → Release).
- **Why (real gaps):** app runs an in-app loopback HTTP media server
  (`lib/media/media_server_io.dart` → `http://127.0.0.1:<port>/`) and reads user-picked files via
  `file_selector openFile` (`lib/core/room_session.dart:3178`); both require macOS sandbox
  entitlements. App has **no camera/mic capture** (grep: zero hits) → no capture permissions added.
  iOS ATS intentionally **not** configured: no NSURLSession-backed client; media_kit/FFmpeg,
  flutter_webrtc and dart:io use raw sockets (not ATS-governed).
- **Per-platform static result:**
  - **Android — no gap.** INTERNET + ACCESS_NETWORK_STATE; debug/profile add INTERNET; no camera/mic/
    storage permission needed (SAF). Loopback cleartext worked in prior on-device tests without
    `usesCleartextTraffic`. **Follow-up (distribution):** release buildType still signs with debug keys
    (`android/app/build.gradle.kts:37`) — owner must supply a release keystore before external shipping.
  - **iOS — fixed (1 key); static only, no host.** Document picker needs no Info.plist key; deployment
    target 13.0; no Podfile yet (generated by `flutter build ios` on a macOS host).
  - **macOS — fixed (2 entitlement files); static only, user-paused.** Deployment target 10.15; no
    Podfile yet. Runtime risks to verify on a real host: Keychain secure storage under sandbox, and
    `codesign -d --entitlements :-` confirming the keys embed.
  - **Windows — no gap; runtime still blocked by host.** Manifest (PerMonitorV2 + Win10/11), Runner.rc
    version info and CMake are standard. Server-Core `OPENGL32.dll` block stands (awaits user desktop).
  - **Web — no gap.** `index.html`/`manifest.json` standard; media bridge injected at runtime. Minor
    placeholder metadata ("A new Flutter project.") left unchanged. `/tmp/eir-web-ready.txt` is a
    **baseline** (28/0/0 on the 04:48 snapshot; core has since advanced) — **not** final freeze.
  - **Linux — no gap (static).** GTK3 + libsecret/Secret Service (previously verified). Not built here.
- **Dependencies / licenses:** no repo-level LICENSE/NOTICE/THIRD_PARTY/COPYING exists — recorded as an
  owner-decision gap (this wheel did **not** choose a project license). `pubspec.lock` pins 118 packages.
  `media_kit_libs_*` bundle FFmpeg/libmpv (typically LGPL-2.1+) — final package must carry the matching
  LGPL notices/source offer; flagged, not decided here.
- **Norns (read-only):** initialize 200, protocol `2024-11-05`, 41 tools; credential read in-memory,
  never printed; no publish.
- **Freeze note:** native artifacts in §10 predate UI REVISION 3 (A16 retry / A17 storage-full) and
  are **not** current. Final unified packaging is deferred to the root coordinator after the source
  freeze; Web must be rebuilt + re-E2E'd from that same frozen source.

## 13. Final native acceptance — round 1 (Android / Windows / Linux; Web still pending)
> This round is **NOT an all-platform pass**. Full detail: `artifacts/mvp/PLATFORM-MATRIX.md`,
> `/tmp/eir-platform-acceptance-stage-ready.txt`.

- **Frozen source:** core F1–F5 (`/tmp/eir-core-final-fixes-ready.txt`) + A13/A14 edge
  (`/tmp/eir-core-edge-validation-ready.txt`); media F5; UI Revision 3. Full `flutter analyze` → **No
  issues found!**; UI/widget → **8/8 pass** (both re-run on the frozen source).
- **Android — FULL PASS (native).**
  - Release APK built (130.9 MB, debug-signed per existing config) and installed; COLD launch OK (pid up,
    lobby renders — screenshot evidence).
  - `room_session_url_test` **2/2**; `room_session_local_media_test` **2/2** (20 s fixture advance + 18 s
    seek); `room_session_core_fixes_test` **4/4** (F1 decode error, F3 same-URL restart, F4 retry,
    late-join/replace/natural-end). Android evidence is on-device, not inferred from Linux.
  - Release-build note: the Android release registrant included the `integration_test` dev plugin and
    failed; built from an isolated copy with that dev-dep excluded (product code identical). Release is
    still debug-signed — supply a release keystore before external distribution.
- **Windows — BUILD PASS, RUNTIME BLOCKED (host).**
  - Final source synced to the independent 3.44.2 SDK; `flutter build windows --release` OK; artifact
    pulled (raw-byte stream, no truncation). AOT `app.so` contains Rev3 UI keys.
  - Runtime not attempted: Server-Core host lacks `OPENGL32.dll` (loader `0xC0000135`), unchanged and
    not re-probed. Awaits a user Windows desktop/OpenGL host; not waived.
- **Linux — FULL PASS (native).**
  - Release rebuilt from final source; real Secret Service startup (`SECRET_SERVICE_OK`, isolated
    keyring), product stayed alive 18 s, no secure-storage/init errors.
  - Heavy core integration **not re-run** (source unchanged; already passed): core 85 unit, URL 2/2,
    local 2/2, 65 MiB 1/1, core-fixes 4/4, edge 3/3. That evidence is core-owned, reused as-is.
- **Web — PENDING, not claimed.** `/tmp/eir-web-ready.txt` remains the **04:48 baseline** (28/0/0; core
  has since advanced). A newer build exists but is not validated/frozen. Not merged; no final packaging.
- **Licenses:** `artifacts/mvp/licenses/` now holds the actual bundled LICENSE/NOTICE files for all
  **118** locked packages (122 files) + `THIRD_PARTY-NOTICES.md`. Project license remains an owner
  decision (none chosen).
- **Test-fixture adaptations (test-only, assertions unchanged):** `FakeRoomSession.retry()`; `ensureVisible`
  before member-ACL taps (Rev3 layout); bundled 20 s/3 MiB + 1.6 s fixtures with asset fallback for
  mobile (Android has no `/tmp`).
- **Checksums:** android/app-release.apk `831bb273…`; linux/eir `2a2c0f56…`, linux/lib/libapp.so
  `03177562…`; windows/eir.exe `582af364…`, windows/data/app.so `b20e601c…`.

---

## 14. W3 refresh — final native rebuild from W3-frozen core (2026-11-07, ~09:13–09:30)

**Trigger:** Web wheel found defect W3 — after a non-dissolving signaling kill on the same URL the UI
stayed `reconnecting` and the Rev3 Retry button never appeared; the app silently auto-recovered when the
endpoint returned. Core fixed it (bounded retry now ends in a real terminal `disconnected` +
`signaling_unavailable`; no auto-revival; explicit `retry()` recovers the same URL/session) and froze
`/tmp/eir-core-w3-ready.txt`.

### Source verification before any build (all four hashes matched the marker)
- `lib/core/room_session.dart` = `bbe182e3febc2e862a1f37a09e249befaf3e9983b662e89ec86a504c170ae6ff`
- `integration_test/room_session_reconnect_exhaustion_test.dart` (core's original) =
  `263f0b71c8c4c49fa04382a80a9e4e11739693ade017a72806dc57cfbc3f9a7f`
- `lib/views/cinema_view.dart` (UI Rev3, unchanged) =
  `dd68324da4a24366109d41344a8c8e9234ba8a48129022ba283b4741107ba136`
- `lib/**` dart tree = `8f2eab97733958626768c700fe11e88b14802304a51631f3e2f477c59e7d160a`
  (previous pre-W3 tree was `6e055983…`, which is what the stale Web marker still references)

### Analysis / UI
- Full `flutter analyze` → **No issues found!** (exit 0).
- `test/ui` + `test/widget_test.dart` → **8/8 pass** on the W3 source.

### Android — FULL PASS (native, W3 source)
- Release APK rebuilt (**136.3 MB**) from `/tmp/eir-android-w3-src`: a tar copy excluding `build/`,
  `.dart_tool/`, `.git/`, `artifacts/`, Gradle caches, with the `integration_test` dev-dep removed **in
  the copy only** (release plugin registrant otherwise references the test plugin). The copy's `lib/**`
  tree hash equals `8f2eab97…` → product source identical. Shared tree was not cleaned.
- Installed + **COLD launch** OK (pid up, Lobby UI renders; screenshot `logs/android-w3-launch.png`).
- Real device tests:
  - `room_session_url_test` **2/2**
  - `room_session_local_media_test` **2/2**
  - `room_session_core_fixes_test` **4/4**
  - **`room_session_reconnect_exhaustion_test` 1/1** — W3: bounded exhaustion reaches `disconnected` +
    `signaling_unavailable` on both peers; room/identity/playlist/playback/DC preserved; playback keeps
    advancing; same endpoint restored → **no** auto-recovery; explicit `retry()` → connected, same
    room/device/playlist/DC, stale error cleared, invite epoch rotated.
- Fixture port (test-only, assertions unchanged): the W3 test hard-coded `/tmp/eir-long.mp4`; Android has
  no `/tmp`, so the 60 s clip is bundled as `assets/eir_long.mp4` and materialized into the app temp dir
  when the host file is absent.

### Linux — FULL PASS (native)
- Release rebuilt from W3 source; packaged as the **complete bundle** (launcher + `lib/` + `data/`).
- Real Secret Service (`SECRET_SERVICE_OK`, isolated `gnome-keyring-daemon`), product alive 18 s, no
  crash, no secure-storage/init errors. Warnings seen are environmental (no a11y bus, PipeWire
  `client.conf`), not app failures.
- Per instruction, the 85 unit suite and the heavy 65 MiB suite were **not re-run**; core's W3
  reconnect 1/1, core-fixes 4/4 and edge 3/3 on the fixed source are reused.

### Windows — BUILD PASS, RUNTIME BLOCKED (host)
- Same W3 source synced to the independent Flutter 3.44.2 SDK; remote `room_session.dart` hash verified
  (`bbe182e3…`); `flutter build windows --release` OK; pulled via raw-byte SSH stream (gzip magic
  verified, `app.so` 7.52 MB, no truncation). AOT contains both Rev3 UI keys.
- Runtime not attempted: Server-Core host lacks `OPENGL32.dll` (loader `0xC0000135`); not re-probed, not
  waived. Awaits a user Windows desktop/OpenGL host.

### Web — FULL PASS (W3 build, merged after hash verification)
- `/tmp/eir-web-ready.txt` was updated at **09:26** to the **FINAL W3-FIXED BUILD**: E2E **28/0/0**,
  A16 retry **18 pass / 0 fail / 1 info — W3 CLOSED** (real button click at t=8 s, no auto-recovery
  after 12 s, same-URL recovery, room/identity/playlist preserved, dual-end decode, shared pause).
- Merge gate satisfied: before copying, every listed hash was re-verified locally —
  `main.dart.js` `764e546b…`, `lib/main.dart` `186a1d28…`, `lib/core/room_session.dart` `bbe182e3…`,
  `lib/views/cinema_view.dart` `dd68324d…`, `lib/views/settings_dialog.dart` `52bd4c01…`,
  `lib/app_localization.dart` `7f018c33…`, `lib/**` per-file aggregate `1a2587e7…`,
  `lib/media/**` tree `65c0c38b…`. All matched the marker.
- Exact tested output copied to `artifacts/mvp/web/` (`main.dart.js` `764e546b…`); E2E/retry JSON and
  logs under `artifacts/mvp/logs/web/`. The old 04:48 baseline stays in
  `artifacts/mvp/old/web-pre-w3-baseline-20261107/` and is not used.
- Scope note: the E2E is two local browser contexts on one host — not a remote-network/latency claim.
  `storage_full` was verified statically only on Web (not produced by the media path; not claimed).

### Licenses
- Dependency set unchanged (`pubspec.lock` untouched; only asset declarations added). Existing collection
  reused: **118 packages / 122 LICENSE-NOTICE files / 0 missing**, indexed by
  `artifacts/mvp/licenses/THIRD_PARTY-NOTICES.md`. Project license still **not chosen** (owner decision).

### Fresh checksums (W3 round)
- `android/app-release.apk` `f3afbd5c6fcede0379f4407167966e5ee1b666e2fae7c3919cedd20c669bd1d4`
- `linux/eir` `2a2c0f56f58774728664900e5ef27865f8ee61533551cffa9fc8af0102dabcc1`
- `linux/lib/libapp.so` `e5d015a6e841943389609b94566a5940a1c51d8247e37da835ecb5bc36c856c7`
- `windows/eir.exe` `0a626eef085bcca9a0b79761974231efae18fbac680e6d93c18a89fb54a83140`
- `windows/data/app.so` `43c2264b905f50c4e678da224069b67b1907da369eb7c992dea2baa73a6fd300`
- `web/main.dart.js` `764e546bad0a9aed919722067525f334a84dfeb3f613f1d449f70b0fd0fec057`

### Non-claims
Not an all-platform pass. Android/Linux/Web are verified on this host; Windows runtime is blocked
externally and not waived; macOS is paused by the user; iOS has no host. Web evidence is local
two-context only (not remote-latency). No publish, no external distribution.

---

## 15. Android debug APK packaging fix (Galaxy Z Flip7 startup crash)

**Symptom:** `build/app/outputs/flutter-apk/app-debug.apk` (sha256 `c76a88a2…`, 240,627,265 B) installed
on a Galaxy Z Flip7 crashed immediately on open.

**Cause (static, deterministic — no code defect):** that file was the integration-test APK left by
`flutter test integration_test/room_session_reconnect_exhaustion_test.dart -d 127.0.0.1:14251`.
It carried `libflutter.so` only under `lib/x86_64/`; `lib/arm64-v8a` and `lib/armeabi-v7a` contained the
plugin libs but **no engine**, and its Dart entrypoint was the test (the kernel blob contains the test
case, not the Lobby). An arm64 phone therefore fails to load the Flutter engine at startup. The same
path is overwritten on every `flutter test -d <android>` run, so it must never be handed out.

**Fix (build/process + docs only; no product code, UI or media source changed):**
- `tool/android_debug_apk.sh` — builds `--debug --target lib/main.dart`, verifies that
  `lib/arm64-v8a/libflutter.so` and `lib/armeabi-v7a/libflutter.so` exist and that the kernel blob is
  not an integration-test entrypoint, then publishes to `artifacts/mvp/android/app-debug.apk`.
  `tool/android_debug_apk.sh verify <apk>` checks an existing file (used as the pre-share guard).
- `artifacts/mvp/RUN.md` and §11 now state the correct installable paths and warn that
  `build/app/outputs/flutter-apk/app-debug.apk` is test output.

**New artifact:** `artifacts/mvp/android/app-debug.apk`, 269,791,348 B,
sha256 `b8479704353ba18b62c3225055c6356e8f40c664beadc94d9a5ac16994083730`
- `lib/arm64-v8a/libflutter.so` 36,747,440 B; `lib/armeabi-v7a/libflutter.so` 31,275,592 B;
  `lib/x86_64/libflutter.so` 37,941,088 B (all three ABIs complete).
- Entrypoint: Lobby string present; `package:integration_test` absent.
- `com.eir.app.eir`, versionCode 1, minSdk 24 / targetSdk 36, same debug signing certificate as the
  release APK (installs over it and keeps app data). 16 KB page alignment OK.

**Verification:**
- Negative test — the guard rejects the old test APK:
  `FAIL: … lacks lib/arm64-v8a/libflutter.so — test/emulator build, not a phone build`.
- Positive — the new APK cold-launches on the API 34 x86_64 emulator and renders the Lobby
  (`artifacts/mvp/logs/android-debug-launch.png`); release APK restored on the emulator afterwards.
- **No physical ARM device was attached**, so arm64 runtime on a phone remains unverified. The packaging
  defect that caused the crash is fixed and guarded; device confirmation still needs an ARM phone.

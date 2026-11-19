# 供片离线 pause 修复与投屏接收——真实 Web 窄回归验收（2026-11-19）

- **性质**：在稳定新构建上对既有脚本的真实双上下文（Web↔Web）复测，**仅测试**，不改产品源码、不构建、不发布、不安装、不碰 ADB、不启停常驻 8080 服务。
- **规范遵守**：遵循 `AGENTS.md` / 全局项目规范。先读 `docs/README.md`、`docs/OFFLINE-FIX-ACCEPTANCE-ENV.md`、`docs/SOURCE-OFFLINE-PAUSE-FIX-HANDOFF.md`、`docs/CALL-SCREEN-INTEGRATION-ACCEPTANCE.md`。模型仅用已核实零费用 `hy3`（`product.json` /models/9 `credits = "x0.00 credits"` 复核）。
- **被测对象身份门槛**：8080 常驻服务实测可达（HTTP 200），served 与 disk 三件套哈希一致：

| 产物 | 实测 SHA-256（live served == disk） |
| :--- | :--- |
| `main.dart.js` | `2960340c18b91b5201ad1487fd3f958e979d5c729038863386d139eab28b6ba8`（4,439,798 B） |
| `eir_media_bridge.js` | `41556baaa3bc377311153c1b3219693d6444bda9739c2c15ec4a36eff9691401` |
| `eir_media_sw.js` | `5124142fc6492d7f5a03d094ff5b5e52697ea483663075e6d1873bde9d50ce23` |
| `version.json` | `1.0.40` / build `41` |

与用户给出的稳定哈希一致；版本号仍 `1.0.40+41`，但本轮以 `main.dart.js` 内容哈希为身份依据，不以版本号为依据（历史报告中同版本号曾发生构建漂移）。

---

## 1. 结论摘要（先说结论）

| 场景 | 旧证据 | 本轮真实复测 | 证据来源 |
| :--- | :--- | :--- | :--- |
| 供片成员离线、无备用项、仅部分缓存 → owner 自动 pause 且播放不推进 | **FAIL**（红） | **PASS** | `offline/raw/source-offline.json` |
| 投屏：真实输入投屏码 + 点击真实 Join Stream → viewer 加入、真实 PC/远端轨/inbound、广播端出站、停止 | **FAIL / 未验证**（脚本误点捷径 + 构建漂移中止） | **PASS**（全部断言） | `cast/raw/viewer-narrow.json` |

**未确认任何业务产品缺陷。** 与本轮两条 FAIL 对应的根因均为**测试脚手架/环境问题**，不是被测产品逻辑：

1. 投屏旧 FAIL：旧脚本误点剪贴板「Watch Now」捷径（错误投屏码）、且会话中途构建被切换触发 fingerprint 守卫中止；并非产品未处理 viewer 加入。
2. 本轮首跑两个 FAIL 也是脚本定位/检测缺陷：Flutter Web 用 `<input>` 而非 `<textarea>` 承载投屏码、确认弹窗的「End Cast」与顶栏同名按钮需区分。已只修定位/检测、保持断言强度不变后复跑全绿（见 §2.2、§3.3）。

---

## 2. 供片离线 pause 真实双上下文复测（source-offline）

- 脚本：`/tmp/eir-offline-runtime-2026-11-19/offline/source-offline.js`（复制自 `/tmp/eir-final-acceptance-2026-11-18/source-offline.js`，**仅改 `OUT` 输出目录**；断言、逻辑、被测 URL 未动）。
- 真实条件：两台独立 Chromium 上下文，A 建房为 owner 并授 admin，B 加入为 member 并添加本地大媒体（`/tmp/eir-streaming-large.mp4`，120s），切到该项播放；`<video src=http://127.0.0.1:8080/eir-media/...>` 真实播放、`member_left` 为真实信令、非 mock。无 URL 改写、无断言放宽。
- 时间：`2026-11-19T03:04:08.431Z` → `03:04:46.498Z`。证据 `source-offline.json` SHA-256 `fdebedd259dc2ba0243ca69f175fa734b4c51aca98b5b1e4858a4cb125e2f9f1`。
- 旧红证据原样保留：`offline/raw/source-offline.OLD-RED.json`（SHA-256 `72cd67cf...`，与 `/tmp/eir-final-acceptance-2026-11-18/raw/source-offline.json` 逐字节一致，未覆盖）。

### 2.1 逐项实际证据

| 步骤 | 状态 | 关键实测值 |
| :--- | :--- | :--- |
| `setup` | PASS | 邀请码 `831229`；A=owner、B=member |
| `owner-playing-guest-local` | PASS | owner 真实播放 B 的本地项：`ct=1.33s`、`dur=120s`、`rs=4`、`paused=false`、`buffered=[[0,13.97]]` |
| `no-complete-cache-at-leave` | PASS | `bufferedEnd=13.97s < dur-5s`、`ct=1.33s<5s` —— **仅部分缓存**，离开时无完整缓存支撑续播 |
| `member-leave-no-backup-pause-cleanup` | **PASS** | B 真实 `Leave Room` 后回到 lobby（`had=true,lobby=true`）；owner 侧收到 `member_left ×1`，`owner_changed=0`、`disbanded=0`（无备用项、未转 owner、未解散）；7 次采样 `ct` 恒为 `0`、`paused=true`、`progressedSamples=0`、`stuck=true` |

**对照旧红**：旧证据同场景 `member-leave-no-backup-pause-cleanup=FAIL`，7 次采样 `ct=6.06→7.11→8.09→9.10→10.11→11.14→12.13`、`paused=false`、`progressedSamples=7`、`stuck=false`——owner 持续消耗缓冲播放。本轮同一场景 owner 在成员离开后立即暂停并停在第 0 秒、播放不再推进，行为反转与 `room_session.dart:_handleMemberLeft` 的 pause 参数补全修复方向一致（本轮不改源码，只做运行时验证）。

### 2.2 视觉核对边界

`source-offline-after-A.png` 等截图已落盘（非空），但本会话工具权限不允许查看图像内容；UI 文案（离线提示/暂停态）以语义树与实际 `<video>` 状态为准。语义采样中 `providerLeft=false`、`sourceOfflineOverlay=false`，但 `paused=true` 与 `ct=0/stuck` 为真实媒体元素状态，pause 判定由媒体状态而非文案给出。

---

## 3. 投屏接收端真实窄复测（viewer-narrow）

- 脚本：`/tmp/eir-offline-runtime-2026-11-19/cast/viewer-narrow.js`（复制自 `/tmp/eir-call-cast-2026-11-19/viewer-narrow.js` 已修正版；改 `OUT` 输出目录，更新 served 基线到目标哈希 `2960340c...`，并修两处**定位/检测**问题，断言强度不变，见 §3.3）。
- 参考旧报告：`/tmp/eir-call-cast-2026-11-19/viewer-narrow-report.md`。
- 时间：`2026-11-19T03:07:27.999Z` → `03:08:04.617Z`。证据 `viewer-narrow.json` SHA-256 `849a0d36cc86486232ef6fdc0520daa96b1b565ad1ace628a8dcef3217ac6e8a`。
- 首跑（未修定位前）原始证据保留：`cast/raw/viewer-narrow.RUN1-detector-bug.json`（SHA-256 `f989224c...`），便于对比。

### 3.1 逐项实际证据（最终复跑）

| 步骤 | 状态 | 关键实测值 |
| :--- | :--- | :--- |
| `fingerprint` | PASS | served/live/disk 三件套哈希全一致，`main=2960340c...`；无构建漂移 |
| `room-setup` / `return-to-lobby` | PASS | A=owner、B=member（码 `745388`）；两端回到大厅后再开投屏页签 |
| `broadcaster-live` | PASS | A 真实屏幕轨 live（`gdmLive=true`），cast code `590090`，进入 Live Cast Dashboard |
| `viewer-field-located` | PASS | 定位到真实输入框 `@668,381 286×46`（Paste 按钮同行左侧锚定） |
| `viewer-field-focused` | WARN | 真实点击后焦点落在 `aria-label="Enter 6-digit cast code"` 的输入框；Flutter Web 无 DOM textarea，属预期，以下一步键入验证为准 |
| `viewer-code-entered` | **PASS** | 真实键盘键入 `590090` 后，输入框 `value="590090"`、activeElement value `590090`，`exactInInput=true`（完整 6 位入框，无吞错） |
| `viewer-join-button-located` | PASS | 锁定真实 `Join Stream` 按钮（`@668,439`），**非**剪贴板 `Watch Now` 捷径 |
| `viewer-join-clicked` | PASS | 真实鼠标点击 Join Stream `@859,462` |
| `viewer-join-signaling` | **PASS** | B、`A` 均发出/收到 `screen_share_viewer_join ×1`，sample `castCode=590090` 与广播码一致；后续 `screen_share_sdp` / `screen_share_ice` 齐全 |
| `viewer-pc-remote-track-inbound` | **PASS** | viewer 端 connected PC ×1；远端视频轨 live；真实 inbound：video `302 packets / 260672 bytes / 1280×720 / 20fps / 87 framesDecoded`，audio `220 packets / 10383 bytes` |
| `broadcaster-outbound-rtp` | **PASS** | 广播端出站 video `315 packets / 273005 bytes / 1280×720`、audio `229 packets / 10926 bytes` |
| `stop-ui` | **PASS** | 点击 End Cast 并在确认弹窗点击确认（`@941,493`）后：`aStopped=true`，viewer 仍 connected PC `[]`，A 回到大厅语义 |

**对照旧证据**：`CALL-SCREEN-INTEGRATION-ACCEPTANCE.md` 与 `viewer-narrow-report.md` 中投屏接收四项（viewer 媒体 / 广播出站 / 信令 / 停止）曾全 FAIL 或「未验证、根因未确定」，且从无 `screen_share_viewer_join`。本轮在稳定目标构建上，viewer 真实入码→真实 Join→`viewer_join`→真实 PC/远端轨/inbound 视频→广播出站→停止全链路均 PASS。合成媒体来自 Chromium `--use-fake-device-for-media-stream`（屏幕源 `Entire screen` 1280×720@20/30），范围为 Web↔Web、loopback 信令、同一构建。

### 3.3 本轮脚本改动（仅定位/检测，未压低断言）

1. `dumpSem` 增采 `<input>` 元素（Flutter Web 用 `INPUT` 承载投屏码，旧版只采 `textarea` 导致 `viewer-code-entered` 首跑误判 FAIL）；`viewer-code-entered` 的 PASS 条件仍是「完整 6 位出现在真实输入框值/语义」，只是把合法取值源从 `textarea` 扩到 `input`/activeElement。首跑该步 FAIL 时 activeElement value 已为 `590090`（见 RUN1 证据），证明为检测器漏读而非产品未入码。
2. `stop-ui` 确认步骤改为在确认弹窗中定位与 `Cancel` 同行的「End Cast」确认按钮并点击（`@941,493`），避免重复命中顶栏同名按钮。断言 `stopPt && aStopped && bViewerConn.length===0` 未改。
3. 未改任何产品/UI 文件、未改业务断言阈值、未改被测 URL/端口、未启停服务。

---

## 4. 未测 / 边界声明（Non-Exemptions）

- **平台范围**：本轮只覆盖 Web↔Web（Chromium 1254，合成摄像头/麦克风与屏幕源，`ws://127.0.0.1:8080/ws` loopback）。**未测** Android / iOS / macOS / Windows / Linux 原生端；未测真机摄像头/麦克风/真实显示器采集。
- **媒体编码**：投屏为浏览器合成画面 + 虚拟音频，1280×720；未测真实高码率/不同分辨率/弱网/ADB reverse 跨机场景。
- **异常分支未测**：仅部分缓存离线 pause 的正向场景已测；未测完整缓存时成员离开、多个备用项、暂停后恢复播放、viewer 中途离开/重连、投屏码错误输入、watchdog 重试等。
- **视觉核对**：截图已落盘但本会话无图像查看权限，UI 文案判断以 a11y 语义与 `<video>`/WebRTC 状态为准；截图仅留档存在性。
- **产物归属**：本轮证明「served==disk==用户给定目标哈希」，不重新证明该构建来自当前源码（按验收准备 §1 由责任方确认）；本轮不触碰 Norns 发布/状态，不连接或调用 MCP。
- **服务**：8080 常驻服务本轮未启停、未覆盖，交既有流程处理。仅清理本任务自身临时资源未涉及删除既有证据。

---

## 5. 最终判定

1. **供片离线 pause 修复**：在稳定目标构建 `2960340c...` 上，以「仅部分缓存 + 无备用 + 真实成员离开」原场景复测，owner 自动暂停且播放不推进（7 次采样全部 `ct=0/paused=true/stuck`），旧红项转绿——**运行时验收 PASS**。未确认缺陷，未改源码。
2. **投屏接收窄回归**：在稳定构建上以「真实输入投屏码 + 点击真实 Join Stream」复测，`viewer_join` 信令、viewer 真实 PC/远端轨/inbound 视频、广播出站、停止全链 PASS——**运行时验收 PASS**。旧 FAIL 根因为测试脚手架（误点捷径/构建漂移）+ 本轮首跑定位检测缺陷，均非产品缺陷。
3. 两份最终 JSON + 日志 + 截图 + 旧红证据均已落盘留档；本轮未构建、未发布、未安装、未动 ADB、未启停服务。

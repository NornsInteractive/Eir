# Web 通话 / 投屏集成证据收尾（2026-11-19）

- 性质：**证据核对与收尾记录**，不是一次新的验收运行。按用户指令：不重跑、不重测、不恢复服务、不构建、不改源码、不发布。
- 核对范围仅限已落地产物：`/tmp/eir-call-cast-2026-11-19/`（`raw/call-cast.json`、脚本、`shots/`）与 `/tmp/eir-oc-call-20261119.jsonl` 的最后有限结果。
- 阅读基线：`docs/README.md`、`docs/DUAL-END-ACCEPTANCE-PREPARATION.md`（尤其 §1 产物身份门槛、§4 S7 通话/投屏判据、§8 A15/A16 规则）、`AGENTS.md`。

## 1. 结论摘要（先说结论）

| 场景 | 判定 | 说明 |
| --- | --- | --- |
| Web 通话真实合成媒体（双向） | **PASS（本证据范围内）** | 双端 ICE/PC `connected`，本地 fake 摄像头/麦克风轨道 live，远端视频/音频轨道 live 且未静音；双端 `inbound-rtp` 均有实际字节/包与音频电平。 |
| 通话信令 / 重拨 / 挂断 | **PASS** | `call_invite/accept/sdp/ice` 齐全两次；重拨后各端新 PC `connected`；挂断后轨道 ended、`call_hangup` 计数 +1。 |
| 投屏：广播端**捕获已启动** | **PASS（仅"启动"）** | A 端出现 live 屏幕轨道 `screen:-3:0`（1280×720@30）、live 假音频、cast code `573270`、a11y 显示 `Live Cast Dashboard / LIVE / End Cast`，并发出 `screen_share_sdp/started/ice`。这不等于端到端投递成功。 |
| 投屏：**接收端真实媒体 / 端到端** | **FAIL（脚本内判定）；产品根因未确定** | B 端未进入观看态、无 PC、无 live 轨道、无 inbound 字节，且**从未出现任何 `screen_share_*` 信令或 `screen_share_viewer_join`**。见 §4 分析：可能是自动化未能真正输入投屏码/点击 Join，也可能是产品未处理 viewer 加入；本证据不足以判定为明确产品缺陷。 |
| 投屏：停止 UI | **FAIL（下游连带）** | 广播端 `End Cast` 已点击并弹出确认、A 端 PC 转为 closed/new；但 B 端从未观看，故"接收端结束态"断言不成立。 |

**不要把超时进程里的中间 `[PASS]` 行当作最终结论。** 本次最终状态以磁盘上已落地的 `raw/call-cast.json` 为准（见 §2），其中 4 项投屏断言明确为 FAIL。

## 2. 证据来源与完整性（已核对，未重跑）

- `raw/call-cast.json`：`startedAt=2026-11-19T02:30:34.351Z`，`finishedAt=2026-11-19T02:33:06.613Z`，共 18 个步骤，14 PASS / 4 FAIL，无 `fatal`。SHA-256 `1ab34921ca4b891dfd11682805261dd27df412f7b0de7f9f40781b814a5863d9`。
- `/tmp/eir-oc-call-20261119.jsonl`：141 行，仅 `step_start / tool_use / step_finish`，无最终文字总结。进程已超时结束。其**最后一条 `tool_use`**（结束于 `2026-11-19T02:33:06Z`）执行的正是 `rm -f raw/call-cast.json && timeout 360 xvfb-run ... node call-cast.js`，输出末尾汇总 `artifact-identity=PASS | ... | cast-start-broadcaster-capture=PASS | cast-viewer-real-media=FAIL | cast-broadcaster-outbound-rtp=FAIL | cast-signaling=FAIL | cast-stop-ui=FAIL`。该时间与 `call-cast.json.finishedAt` 一致 → **磁盘 JSON 就是该超时进程的最终落地结果，而不是中间态**。
- 脚本：`call-cast.js`（真实 UI、无 mock）、`cast-debug.js`、`discover-ui.js`、`discover-media.js`。日志显示 OpenCode 在本次运行前对 `call-cast.js` 做过断言/正则调整（投屏码提取、`End Cast`、`Stop Cast` 文案等）；这属于测试脚手架变更，本次仅核对产物，不据此放宽或重述判据。
- 产物哈希：`served_*` 与 `disk_*` 三项（main/bridge/sw）逐一相等，`version=1.0.40+41`。**注意：**这只证明"当次服务的内容与磁盘构建一致"，不能证明来自当前源码——版本号与旧 `1.0.40+41` 基线相同，当前源码归属仍须由 Agy 按验收准备 §1 确认。
- 截图 `shots/` 共 10 张、非空（84K–195K），含 `call1-incoming-B`、`call1-connected-A/B`、`cast-lobby-A`、`cast-picker-A`、`cast-live-A`、`cast-viewer-B`、`cast-after-stop-A/B`、`cast-debug`。本次工具权限不允许查看图像内容，故画面判断以 JSON 中捕获的 a11y 语义与 WebRTC 统计为准；截图仅作为留档存在性核对。
- 环境：`http://127.0.0.1:8080/` 当前**可达**（HTTP 200，返回 Eir `index.html`，带 `COOP: same-origin` / `COEP: credentialless`；`/proc/net/tcp` 有 `127.0.0.1:1F90` 监听）。按指令仅记录，未做恢复/构建/清理，交 Agy。

## 3. 通话为何是"真实合成媒体通过"（不是控制面/占位）

`call1-connected-real-media`（PASS）detail 中：

- 双端 `connectionState=connected`、`ice=connected`。
- A：`fake_device_0` 视频 live（640×480@20）、`Fake Default Audio Input` live；远端视频 live 未静音、远端音频 live 未静音。B 端对称，设备 id 不同（两台独立浏览器上下文）。
- **真实入站媒体**（`getStats`）：A 收到 video `30008 bytes / 38 packets / 640×480 / 20fps`、audio `1504 bytes / 33 packets / audioLevel 0.062`；B 收到 video `35627 bytes / 44 packets`、audio `1621 bytes / 38 packets / audioLevel 0.0156`。

这是双向实际载荷，不是仅 UI 文案或控制消息。合成媒体来自 Chromium `--use-fake-device-for-media-stream`（`fake_device_0` / `Fake Default Audio Input`），故为**合成媒体**通话，不是真人摄像头/麦克风证据；范围仅限 Web↔Web、loopback 信令。

`call2-redial-connected-real-media` 的 PASS 细节只有 `connA/connB state=connected` 与 `pcsBeforeRedial=2 / pcsAfterRedial=3`，**未记录重拨后的 inbound 字节**。因此"重拨后能建连并恢复 UI"成立；"重拨后再次有真实双向载荷"在本证据里未单独量化，不额外宣称。

## 4. 投屏失败：已启动 / 接收失败 / 脚本问题 / 未验证 的区分

### 4.1 已证实：广播端捕获启动（PASS，仅启动）

`cast-start-broadcaster-capture`：A 端 `aLive=true`、`castCode=573270`，视频轨中出现 live 的 `screen:-3:0`（`displaySurface=monitor`、`logicalSurface=true`、1280×720@30），live 的 `Fake audio`，旧通话轨道均已 ended；a11y 文本为 `Streaming 00:01 Live Cast Dashboard LIVE End Cast Viewer Cast Code 573 270`。wire 中 A 发出 `screen_share_sdp ×1`、`screen_share_started ×1`、`screen_share_ice ×32`。→ **捕获链路在广播端确实起来了。**

### 4.2 失败：接收端无媒体（FAIL，脚本判定）

- `cast-viewer-real-media`：`bViewing=false`、`conn=[]`、所有轨道 ended、`inbound=[]`；B 端 a11y 停留在 `🎬 Cinema 📱 Screen Cast Device ID: ... Start Casting Now / Join Stream / Recent Cast History`，**未出现观看态**。
- `cast-broadcaster-outbound-rtp`：`outbound=[]`、`inbound=[]`（广播端 `getStats` 未采到出站视频字节）。注意：同一浏览器在通话步骤里 `getStats` 能返回真实 inbound，故此处更可能是"没有 viewer 完成协商、没有出站流可统计"，而非统计接口整体失效。
- `cast-signaling`：A 侧信令集合为 `screen_share_sdp / screen_share_started / screen_share_ice`；B 侧仍只有早前通话残留的 `call_ice / call_hangup / call_invite / call_accept / call_sdp`，**没有任何 `screen_share_*`**；全量 wire 中也**没有 `screen_share_viewer_join`**。→ viewer 加入动作从未被产品发出信令。

### 4.3 脚本问题 vs 产品问题：本证据不足以定论，记"未确定"

- 脚本的 viewer 加入逻辑（`call-cast.js` 第 302–315 行）用 `B.getByRole('textbox').first().fill(castCode)` / `getByPlaceholder(/cast code/i)` 输入投屏码，再用 `getByRole('button', {name:/^Join$/})` 点击。被测对象是 Flutter Canvas 应用：可见控件主要在 `flt-semantics` 里，未必暴露为原生 DOM textbox/button；脚本对这些查找均带 `.catch(() => {})` 静默吞错，日志里也没有记录"码是否真的输入/Join 是否真的点到"。因此**存在明显的自动化未能驱动加入 UI 的可能**。
- 另一方面，如果产品 UI 真的接收到了有效的投屏码并触发加入，应当发出 `screen_share_viewer_join`；该信号缺失也可能是产品未处理 viewer 加入、或投屏码 `573270` 未被接受。现有证据无法把这两类原因分开。
- 用户要求：有明确投屏产品问题才给证据，否则记未确定。**故本次不把 4 个投屏 FAIL 直接写成"产品缺陷"**，记为"端到端接收未通过，根因未确定（脚本加入动作未证实 / 产品接收待查）"。

### 4.4 停止 UI 的 FAIL 是下游连带

`cast-stop-ui` 的 `stopped=true`，A 端 a11y 显示 `Stop current screen share and disconnect all sessions? ... End Cast` 确认框，A 端 PC 由 connected/closed 变为含 `new`（5 个 PC：4 closed + 1 new）；但 B 端仍在投屏大厅且断言要求 B 端出现结束态，故 FAIL。这里既受"viewer 从未观看"影响，也留下"A 端停止后仍有 1 个 `new` PC"的现象，是否需要追查为泄漏，本证据不足以判定。

## 5. 判定边界（避免夸大）

- **通过范围**：仅 Web↔Web、Chromium 合成设备、loopback `ws://127.0.0.1:8080/ws`、同一构建版本。不代表真实摄像头/麦克风、真实显示器采集、真机或 Android/iOS/桌面端。
- **产物身份**：`served==disk` 已核对；"是否当前源码构建"未由本报告证明，按验收准备 §1 由 Agy 确认。
- **未验证 / 不宣称**：投屏端到端接收、投屏码加入、`screen_share_viewer_join`、`getStats` 出站统计在投屏路径的有效性、投屏停止后 PC 是否完全清理、通话重拨后的量化媒体载荷。以上均不得以中间 PASS 行或控制面消息替代。
- 本报告不触碰 Norns 发布/状态，不连接或调用 MCP，交 Agy 处理环境与服务。

## 6. 交 Agy 的最小下一步（不在本轮执行）

1. 确认本次 Web 构建（main/bridge/sw 三件套哈希 `e81574…` / `41556b…` / `512414…`）是否来自当前源码；若否，本次通话 PASS 仅代表被服务构建。
2. 若要给投屏定论：用一次真实 UI 交互确认 B 端投屏码输入与 Join 确实生效，并抓取 `screen_share_viewer_join` 与 B 端 `inbound-rtp`（video 有 `frameWidth>0 && bytesReceived>0`）；在此之前投屏接收保持"未通过、根因未确定"。
3. 8080 当前可达且未由本次任务启动/停止；如需清理或重建服务，由 Agy 按既有流程处理。本轮未做恢复、构建、重测或发布。

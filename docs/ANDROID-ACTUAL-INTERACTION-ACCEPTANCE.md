# Android 实际交互验收报告（真实 ADB 操作 + 宿主浏览器第二端）

- 执行时间：2026-11-18 15:22–15:45（约 23 分钟实测，未用满 60 分钟窗口）
- 执行模型：已核实免费的 CodeBuddy `deepseek-v4.1-flash`（`x0.00 credits`，无付费回退）
- 性质：**只做实际测试**。未改产品代码/UI，未构建、未安装、未发布，未 `pm clear`/卸载/清数据，未改图形 GPU 设置，未读 Agy 过程日志。
- Norns：本轮根已检查，本次未重复连接、未发布。

---

## 1. 产物核对（不以版本号相同判新旧）

| 项 | 实测值 | 方法 |
|---|---|---|
| 本地 APK | `eir-v1.0.40.apk`，`e40acbd8a0b467d1d04c7fb84cf4a4be59d9636717f95027bb3fe8f85e8f861e` | `sha256sum` |
| 设备内已安装 base.apk | `e40acbd8a0b467d1d04c7fb84cf4a4be59d9636717f95027bb3fe8f85e8f861e` | `adb pull` 后 `sha256sum`（**逐字节一致**） |
| 设备包信息 | `com.norns.eir`，`versionName=1.0.40`，`versionCode=41`，`lastUpdateTime=2026-11-18 14:18:59` | `dumpsys package` |
| Web 产物 | `build/web/main.dart.js` 14:19:55，`sha256=cf87359f…9928`；`eir_media_bridge.js` `sha256=41556baa…1401` | `ls`/`sha256sum` |
| 实际服务内容 | 8080 返回的 `main.dart.js`/`eir_media_bridge.js` 哈希与 `build/web` **完全一致** | `curl | sha256sum` 对比 |
| 信令服务 | tmux `eir-server`，PID 269719，`dart run server/signaling_server.dart 8080 :: build/web` | `ps`/`tmux capture-pane` |
| 源码基线 | `1db9aa670ceff2ab80f3502f3664ee3e76f4c5fc` | `git rev-parse HEAD` |
| 端点 | Web `http://127.0.0.1:8080/`，信令 `ws://127.0.0.1:8080/ws`；设备 `adb reverse tcp:8080`（预存，未改） | `curl`/`adb reverse --list` |

结论：设备内应用与本地 APK 同一产物，Web 服务内容与 `build/web` 同一轮构建，**不是"版本号相同即旧包"的推断**。

---

## 2. 结果总览

| # | 项目 | 结果 |
|---|---|---|
| 1 | App 启动并可交互 | **PASS** |
| 2 | 设置页可见、可保存 | **PASS** |
| 3 | 房间内改设置不丢房间 | **PASS** |
| 4 | App 创建房间、浏览器凭实际邀请加入 | **PASS** |
| 5 | 浏览器创建、App 凭实际邀请加入 | **NOT TESTED** |
| 6 | App 本地文件供片、Web 播放 | **NOT TESTED** |
| 7 | URL 媒体两端播放/暂停/seek | **FAIL**（Web 端已解码，App 端未加载） |

---

## 3. 逐项证据

### 3.1 App 启动可交互 — PASS

`am start -n com.norns.eir/.MainActivityAliasClassic` 后 `mCurrentFocus=com.norns.eir/.MainActivityAliasClassic`；
uiautomator 结构含 `Create Cinema Room`、`Quick Join`、`Join Cinema`、`Lobby/Cast/Me`，节点 `clickable=true` 且后续真实点按均生效（进入设置、创建房间）。
证据：`docs/evidence-android/a01_launch.png`。

### 3.2 设置页可见可保存 — PASS

房间外打开 Preferences → `Network & Relay`：
- 原始值记录：Server Domain `https://eir.norns.cc.cd`，Signaling `wss://eir.norns.cc.cd/ws`，浅色/深色主题色均为 Classic Blue，主题模式 System。
- 本机配置固定：Server Domain 改为 `http://127.0.0.1:8080` 并点 `Sync from Cloud` → 反馈 `Sync failed: FormatException…`（本地服务无 `/api/config`，**未发生向生产迁移**）；Signaling 改为 `ws://127.0.0.1:8080/ws` 并点 `Save` → 反馈 `Signaling URL saved`。
- 浅色主题色改为 Aurora Purple 后，深色仍为 Classic Blue（独立保存成立）。

### 3.3 房间内改设置不丢房间 — PASS

在房间 `293601` 内打开 Preferences，改浅色主题色 → `Done`。前后对比：
`# 293601 HOST P2P`、`Friends (2)`、`SilentPanda (You) HOST d556f0…4c56`、`FrostyChaser MEMBER 2b3a8a…3234` 全部保持，未重连、未退出房间。
证据：`a22_after_settings.png`。

### 3.4 App 创建 → 浏览器凭实际邀请加入 — PASS

- App 点 `Create Cinema Room`，进入房间：`# 293601`，`HOST`，初始 `Server` 传输。
- 从 App `Room Info` 读取**实际邀请**：`eir:v1:eyJleHBpcmVzQXRNcyI6MTc5NTI0NjEzNzkxNC…`（717 字符），Room ID `80757eea-55d0-44e0-b4e2-a3f77632b738`，Host Device ID `d556f061…4c56`。
- 宿主 Chromium（Playwright，独立 context，无业务状态注入）打开 `http://127.0.0.1:8080/`，把该邀请填入真实输入框并点 `Join Cinema`。
- 双端结果：App `Friends (2)`，成员 `FrostyChaser 2b3a8a…3234 MEMBER`；App 头部由 `Server` 变为 **`P2P`**；Web 端语义树显示 `MEMBER`、`P2P`。两端身份不同（d556f0… vs 2b3a8a…）。
证据：`a17.xml`（Room Info 原文）、`a18_app_member.png`、`b01-lobby.png`、`b02-filled.png`、`b03-joined.png`、`b-state.json`。

### 3.5 浏览器创建 → App 加入 — NOT TESTED

60 分钟窗口内未执行。无结论，不得记为通过。

### 3.6 App 本地文件供片 → Web — NOT TESTED

未执行文件选择器流程（受时间限制）。已把 `short-a.mp4` 推送到 `/sdcard/Download/eir-short-a.mp4` 备用，但**未进行选择与供片**，不构成证据。

### 3.7 URL 媒体两端播放/暂停/seek — FAIL

- App（Host）经 `Add Online URL` 添加 `http://127.0.0.1:8731/eir-media-fixture.mp4` 并 `Switch to this item`。
- **Web 端成功**：`<video src="http://127.0.0.1:8731/eir-media-fixture.mp4" duration=20 readyState=4 videoWidth=320 videoHeight=240 error=null paused=true>`，即清单已同步且 Web 端完成解码。
- **App 端失败**：播放器持续显示 `Buffering...`，时间显示 `00:00 / 00:00`（未取得时长），点击 `Play (Synced)` 后仍为 `Buffering...`，无播放进度。
- 因 App 端未加载，**play / pause / seek 的双端一致性未取得任何真实数据**，本项判 FAIL，不拆分记为通过。
- 归属说明：媒体源为测试期临时 HTTP 服务（宿主 8731 + `adb reverse`），App 对该源未取到时长；无法在本轮区分"测试源/回环转发"与"产品 URL 播放缺陷"，因此**仅记录本端实测症状，不判定为已确认的产品缺陷**，转 Agy/根复核。

---

## 4. 配置恢复与清理

| 项 | 状态 |
|---|---|
| Server Domain | 已恢复 `https://eir.norns.cc.cd`（`Sync from Cloud` → `Config synced`，读回确认） |
| Signaling URL | 已恢复 `wss://eir.norns.cc.cd/ws`（读回确认） |
| 浅色/深色主题色 | 已恢复 Classic Blue（读回 `Selected`） |
| `adb reverse tcp:8731` | 已移除；仅保留预存 `tcp:8080`、`tcp:22023` |
| 测试 HTTP 服务 / 浏览器 | 已按 PID 结束，8731 不可达 |
| 信令服务 8080 | 保持运行（未改动） |
| App 房间 | 保持 `# 293601 HOST`（对端已断开显示 `Server`），未执行解散等破坏性操作 |

---

## 5. 未测/限制

1. 浏览器创建 + App 加入（反向流程）未测。
2. App 本地文件供片与 Web 端解码未测。
3. URL 双端 play/pause/seek 未取得双端数据（App 端未加载）。
4. 图形/硬件解码沿用既有模拟器豁免，仅图形，不豁免交互；本轮交互均为真实点按。
5. 未覆盖断线重连、房主继任、投屏等场景（本轮不在范围）。

## 6. 证据清单（`docs/evidence-android/`）

`a01_launch.png`、`a15_room.png`、`a17.xml`（Room Info 原文）、`a18_app_member.png`、`a22_after_settings.png`、`a30_app.png`（App 端 Buffering 现场）、`a33.xml`（`Buffering… 00:00 / 00:00` 结构证据）、`restore-network.png`（恢复后网络设置）、`b01-lobby.png`、`b02-filled.png`、`b03-joined.png`、`b-state.json`（Web 端房间与身份）。

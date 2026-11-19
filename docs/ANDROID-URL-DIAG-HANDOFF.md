# Android URL 缓冲窄诊断交接（源可达性 / Range / 播放器加载）

- 执行时间：2026-11-18 20:04–20:22（约 18 分钟，未用满 20 分钟窗口）
- 执行模型：已核实免费 `opencode/deepseek-v4.1-flash-free`（全 0 费用，无付费回退）
- 性质：**只诊断/实测**。未改产品代码、UI、服务端、图形设置；未构建/安装/打包/发布；未 `pm clear`/卸载/清数据；未读 Agy 过程日志；未触碰 8080 信令/Web 服务。
- 设备：`172.17.0.1:14251`（`sdk_gphone64_x86_64`，Android 模拟器）
- 被测包：`com.norns.eir`，`versionName=1.0.40`，`versionCode=41`

---

## 1. 结论（先看这里）

**本轮把“测试源 / adb reverse 转发不可达”从 URL 加载失败原因中排除。**

- 宿主到夹具：`curl -H 'Range: bytes=0-99' http://127.0.0.1:8731/eir-media-fixture.mp4` 返回 `206 Partial Content`、`Content-Range: bytes 0-99/3098261`、`Accept-Ranges: bytes`；`/tmp/eir_media/*.mp4` 三份夹具 `ffprobe` 均为 `duration=20.000000`。
- 设备侧经 `adb reverse tcp:8731`（**预存在，本轮未新增/未删除**）可达：Eir 产品链路中的 `addUrl` 必须先在设备内通过 `probeMediaUrl`（`lib/core/url_probe_io.dart`，Range `bytes=0-1023`，只接受 200/206）才会入库；本轮 URL 实际进入播放列表并显示 `NOW PLAYING`，说明设备侧探测已拿到 2xx。
- Eir 播放器实际打开了 URL：`logcat` 出现 media_kit 的 `VideoOutputManager.setSurfaceSize: … 320 240`、`VideoOutput.Resize {width:320,height:240}`，即 libmpv 已解析到视频轨尺寸并创建视频输出；无 `player.stream.error` / `source_offline` / `media_probe_failed` 记录。

**但本轮未能可信复现并量化“持续 Buffering 且 duration=00:00”**：设备被外部进程接管，`com.norns.eir` 被 `shell` 调用 `pm disable`，前台被切到 `com.norns.valhalla` / `com.norns.omnitune`，Eir 进程随后 `has died: fg TOP`。因此**不能判定为已确认的产品缺陷，也不能判为通过**。`07` 项（URL 双端 play/pause/seek）保持 **FAIL/未闭环**。

---

## 2. 实测记录

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| 1 | `eir-media-fixture.mp4` 为 20s 有效媒体 | PASS | 宿主 `ffprobe` `duration=20.000000`（三份夹具相同） |
| 2 | Range 响应正确 | PASS | 宿主 `curl`：`206`、`Content-Length: 100`、`Content-Range: bytes 0-99/3098261` |
| 3 | 设备经 reverse:8731 可达（产品代码路径） | PASS | URL 成功入库并 `NOW PLAYING`；`addUrl` 在入库前强制 `probeMediaUrl`，失败即 `media_probe_failed` 不入库（`lib/core/room_session.dart:4716-4730`） |
| 4 | URL 加入播放列表 | PASS | `Playlist (2)`，条目 `http://127.0.0.1:8731/eir-media-fixture.mp4` |
| 5 | 切到该 URL 后播放器进入加载 | PASS | `logcat 20:09:37.968 I/VideoOutputManager(9047): setSurfaceSize: … 320 240`；`20:09:37.972 I/flutter: VideoOutput.Resize` |
| 6 | 播放器异步错误 | 未见 | 同期无 `media_kit` error / `source_offline` / `media_probe_failed` |
| 7 | “持续 Buffering + 00:00/00:00”可信复现 | **BLOCKED** | 设备被外部接管（见第 4 节）；本轮未取得可归因的 duration/buffering/position 读数 |
| 8 | play/pause/seek 双端一致 | NOT TESTED | 需先有第 7 项可信状态 |

已存在但**不属于本轮**的历史证据：
- `docs/evidence-android/a33.xml`（15:34）：`Buffering...`、`Playlist (1)`、`NOW PLAYING`，是上轮“持续缓冲”的原始症状。
- `docs/evidence-android/a40_url_range_playing.png` / `a41_url_range_playing_after_tap.png`（19:34）：URL Range 源画面；`a40` 仍为暂停中央播放按钮，`a41` 点击后中央按钮消失。**该组截图未显示时长/进度文本，不能单独证明 duration=20 或双端 seek**，也不能归属本轮。

---

## 3. 与产品代码的对应（未修改）

加载链路（Android）：

1. `addUrl` 校验 scheme/loopback → `probeMediaUrl`（Range 1024B，2xx 才通过）→ commit `add_url`（`lib/core/room_session.dart:4716`）。
2. 选中条目后 `_ensureMediaLoaded` 对 `sourceType == 'url'` 直接 `Media(item.url!)`，然后 `player.open(..., play: false)`（`lib/core/room_session.dart:3742`、`:3772-3775`）。
3. UI 进度时长取 `session.player.state.duration`，为 0 时回退到清单 `currentMedia?.duration`（URL 条目无 duration），再回 0；Buffering 遮罩只看 `player.state.buffering`（`lib/views/cinema_view.dart:2688-2697`、`:3834`）。

因此，若后续仍出现“无 duration 持续 Buffering”，最小排查点应集中在 **`open(play:false)` 之后 Android media_kit 是否发出 duration、以及 `state.buffering` 是否在暂停/起播前长期为 true**，而不是源可达性/转发。建议用一次性诊断读数（不改产品逻辑）同时记录：
`player.state.duration`、`position`、`buffering`、`completed`、`width/height`，分别在 `open` 后 0s/1s/3s 与点击 Play 后 1s/3s。若确认 duration 已为 20s 而 UI 仍 00:00，责任在 UI 投影；若 duration 恒为 0，责任在播放器打开参数/平台实现（`lib/core/room_session.dart` 的 `PlayerConfiguration` 与 `open` 调用）。

本轮**未给出修复**，也未改动上述文件。

---

## 4. 明确外部阻塞（导致第 7 项无法闭环）

在 URL 已加载、`setSurfaceSize 320x240` 之后：

- `dumpsys package com.norns.eir` 显示 `enabled=3`（disabled），`lastDisabledCaller: shell:1000`；`pm list packages -e` 中无 `com.norns.eir`，`am start` 报 `Activity class … does not exist`。
- 本轮为继续测试执行了 `pm enable com.norns.eir`（包状态恢复为 enabled），随后能启动。
- 但前台反复被其他会话切走：`topResumedActivity` 先后为 `com.norns.valhalla`、`com.norns.omnitune`；`20:17:13 ActivityManager: Process com.norns.eir (pid 10377) has died: fg TOP`，无 `FATAL EXCEPTION`。
- 该设备同时被其他代理使用，无法保证“独占前台 + 独占 Eir”。按任务要求，遇明确外部阻塞即出最终报告，未继续与外部操作抢夺设备。

**未做**：未读 Agy 日志；未停止/重启 8080；未删除他人 `/tmp/eir_media`、`/tmp/eir_range.log`、8731/8732 服务；未新增或移除任何 `adb reverse`。

---

## 5. 通过 / 失败 / 未测（汇总）

- **PASS**：夹具 20s 有效；HTTP Range 206；设备侧 reverse:8731 可达（产品 `probeMediaUrl` 成功后才入库）；URL 入清单并 `NOW PLAYING`；media_kit 拿到 320x240 视频尺寸并创建视频输出；无播放器异步错误。
- **FAIL（未闭环）**：URL 双端播放/暂停/seek；上轮“持续 Buffering + 00:00/00:00”未能复现并定位到确定责任层。
- **NOT TESTED / BLOCKED**：`open` 后 duration/buffering/position 时序读数；点击 Play 后的实际推进；8732 无 Range 对照；远程 HTTPS 源；弱网；成员端同步；重连；本地文件供片。

---

## 6. 清理与状态

- 删除本轮自身临时 XML：`/tmp/r1.xml`、`/tmp/eir-now*.xml`（保留仓库内既有 `docs/evidence-android/*` 不动）。
- 未改动 `8080`；`adb reverse` 仍为预存的 `tcp:8080/8731/8732/22023`。
- `com.norns.eir` 当前为 enabled（原被外部 `shell` 置为 disabled）；未清数据、未卸载。
- 未修改任何产品/UI/服务端源码，`git status` 中不应出现本轮新增的源码变更（仅本交接文档）。

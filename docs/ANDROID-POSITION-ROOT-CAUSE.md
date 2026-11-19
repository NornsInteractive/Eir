# Android 播放进度恒 0 根因诊断（duration 可得 / position 不推进）

- **执行时间**：2026-11-19 12:06–12:14（+08:00，约 8 分钟有效操作，20 分钟上限内）
- **执行模型**：已核实免费 CodeBuddy `deepseek-v4.1-flash`（`x0.00 credits`，无付费回退）
- **性质**：**只诊断/实测**。未改产品代码、UI、服务端；未构建/安装/打包/发布；未 `pm clear`/卸载/清数据；未改系统图形/GPU/构建配置；未新增或移除 `adb reverse`；未停止其他项目应用。
- **设备**：`172.17.0.1:14251`（`sdk_gphone64_x86_64`，Android 14，x86_64，模拟器）
- **被测包**：`com.norns.eir`，`versionName=1.0.40`，`versionCode=41`，`lastUpdateTime=2026-11-19 11:17:31`（与 02831ded…eece89 一致）
- **房间**：沿用设备上既有生产房间 `# 766248`（HOST）；未新建房间、未使用其他数据。

---

## 1. 结论（先看这里）

| 判定对象 | 结论 |
|---|---|
| 症状可复现（duration 20s、position 恒 0、seek 无效） | **证实** |
| 责任层 = **UI 投影** | **排除** |
| 责任层 = **URL/探测/Range 源可达性** | **排除** |
| 责任层 = **播放管线未推进（libmpv 未起播/被阻塞）** | **证实（行为层）** |
| 与用户已豁免的模拟器 EGL/libmpv 故障**同一根因** | **证据不足**（有指向图形侧的旁证，缺 mpv 直接日志） |

**核心结论**：进度恒 0 不是 UI 把真实进度显示错了，而是**播放器状态本身没有推进**。同一时刻会话权威状态为「正在播放」（按钮为 `Pause (Synced)`），但底层 libmpv 既无音频输出、无解码、无网络活动，`player.state.position` 始终为 0。即：**播放命令/渲染链路停在管线内，UI 只是如实显示 0。**

---

## 2. 复现过程（未改任何应用/系统配置）

1. 设备空闲，`topResumedActivity=com.norns.eir/.MainActivityAliasClassic`，Eir 独占前台（12:06 核验）。
2. 复用**预存** `adb reverse tcp:8731`（未新增）；宿主 `python3 /tmp/eir_range_server.py /tmp/eir_media 8731` 对 `Range: bytes=0-99` 返回 `206`、`Content-Range: bytes 0-99/3098261`、`Accept-Ranges: bytes`（12:07 复核）。
3. 既有播放列表条目指向已下线的 `:8733`，故通过实际 UI「Add Media」新增 `http://127.0.0.1:8731/eir-media-fixture.mp4`（`probeMediaUrl` 通过后才入库，Playlist 1→2）。
4. 「Switch to this item」→ 条目 `NOW PLAYING`，播放器显示 `00:00 / 00:20`，按钮 `Pause (Synced)`，SeekBar `0%`。

### 时间窗采样（position 恒 0）

| 时间 | 读数 | 证据 |
|---|---|---|
| 12:10:0x（切换后 ~6s） | `00:00 / 00:20`、`Pause (Synced)`、SeekBar `0%` | uiautomator dump |
| 12:11:4x（切换后 ~90s） | `00:00 / 00:20`、`Pause (Synced)`、SeekBar `0%` | uiautomator dump |
| 12:12:0x（再采样） | 同上，未出现 `00:01` 及任何递增 | uiautomator dump |

> 期间点击暂停按钮未使按钮变为 `Play`（一次点击未生效或状态被同步回写），未取得「先暂停再播放」的可信切换读数，故不作为证据。

---

## 3. 判定「不是 UI 投影」的直接依据

- 进度条与时间文本**严格取 `session.player.state.position`**，无任何回退/遮罩：
  - `lib/views/cinema_view.dart:2693` `final playerPos = session.player.state.position;`
  - `:2695` 注释即「Truthful UI projection … never disguise a frozen player」，`currentPos = playerPos` 直接投影。
  - duration 回退仅影响总时长，不影响 position。
- `Friends` 遥测的 `positionMs` 同样取自 `player.state.position`（`lib/core/room_session.dart:2843`、`:2901`），与本机 UI 同源。
- 结论：UI 显示 0 ⇔ `player.state.position` 为 0。**UI 投影层已排除。**

## 4. 判定「播放管线未推进」的直接依据

`duration=00:20` 说明 **libmpv 已成功打开并解出媒体**（URL 条目本身无 duration，UI 的 20s 只能来自 `player.state.duration`）；但同一时段：

| 检查 | 实测 | 含义 |
|---|---|---|
| `dumpsys audio` players | 无 `com.norns.eir` 的 AudioPlaybackConfiguration（仅有系统 SoundPool idle） | 无音频输出在跑 |
| `dumpsys media.codec` | 无任何 codec 实例 | 无硬件/软件解码在进行 |
| `ss -tnp \| grep 8731` | 无到夹具的活动连接 | 未在持续拉流 |
| `/proc/16802/task` | 仅 `mpv/mpv core`（S）、`mpv/worker`（S），无 `vd-lavc`/`ao`/`vo` 解码/输出线程 | libmpv 已初始化但**空闲** |
| `logcat`（pid 16802，12:09–12:12） | 仅 `EGL_emulation` / `FrameTracker`，**无 mpv / media_kit / MediaCodec / flutter 日志** | 无起播、无解码、无错误上报 |

夹具 `eir-media-fixture.mp4` 含 H.264 视频轨与 `mp4a` 音频轨（`avc1`/`avcC`/`mp4a`/`esds` box 实测存在，`moov` 位于文件尾部），因此「无音频输出」不是因为没有音轨。

**结论**：会话权威状态为 playing（`PlaybackMode.playing`，见 `cinema_view.dart:2685`），但播放器实际未进入播放。责任在**从 `player.play()` 到 libmpv 起播/渲染这一段**，不是 UI，也不是源。

## 5. 是否与「已豁免的模拟器 EGL/libmpv 故障」同一根因

**证据不足，但现有旁证指向图形侧，不能排除。**

支持「同一族」的旁证：
- 同一进程 `EGL_emulation: app_time_stats` 在观测窗内稳定为 `avg≈2000ms`（约 0.5 fps），说明该模拟器上 Flutter/GL 渲染严重退化；mpv 的 vo 渲染与 VideoController 共用同一图形栈。
- `media_kit` 的 `play()`/`setRate()` 在 `isVideoControllerAttached` 时会 `await videoControllerCompleter.future`（`media_kit-1.2.6/lib/src/player/native/player/real.dart:358-381`、`platform_player.dart:419`；`media_kit_video-2.0.1/.../video_controller.dart:77,136`）。若 `VideoController` 初始化因 GL/EGL 卡住，`play()` 会**永不返回且不报错**，表现为「状态 playing、position 0、无日志」——与本轮现象完全一致。

不支持「已证实」的原因：
- media_kit 未设置 `logLevel`，`PlayerConfiguration` 仅配置 `bufferSize`（`lib/core/room_session.dart:678-682`），**拿不到 mpv 的 `vo/gpu`/`vd`/`ao` 日志**，无法直接看到 EGL 创建失败或渲染回调阻塞。
- 未能区分是「`play()` 未执行/被锁阻塞」还是「`play()` 已执行但 vo 卡死」。两者表现相同，均无日志。

> 因此：**不能凭模拟器型号宣称与豁免的 EGL 故障同因**；本轮只把范围从「UI/源」收敛到「播放管线（含 vo/VideoController 初始化）」。

---

## 6. 必要根因位置与下一步（不改现有产品逻辑即可推进）

**根因位置（按可能性）**：
1. `lib/core/room_session.dart:3646-3668` `_applyPlayerForCommit`：`play()` 前有 `setRate()` 与 `waitForVideoControllerInitializationIfAttached`，后者可能永久挂起；`_loadedItemId != itemId` 时还会静默 `return`。
2. `media_kit_video` `VideoController` 初始化（依赖 `addPostFrameCallback` + 平台纹理创建）在低帧率 EGL 环境下可能不完成，导致 `play()` 阻塞。
3. libmpv `vo=gpu` 在该模拟器上渲染回调阻塞（需 mpv 日志确认）。

**建议下一步（需另行授权，本轮未做）**：
- 用**诊断构建**（仅加 `PlayerConfiguration(logLevel: MPVLogLevel.debug)` 与 `play()` 前后状态打印，不改业务）抓 `vo/gpu`、`vd`、`ao` 与 `videoControllerCompleter` 时序；这是唯一能把「play 未执行」与「vo 卡死」分开的证据。
- 低成本判别实验（无需改代码）：用**纯音频**夹具走同一 URL 流程。若音频也停 → 指向 `play()` 未生效/锁阻塞；若音频能播、仅视频 0 → 锁定 vo/EGL。
- 若确认是模拟器 EGL/libmpv，按用户既有豁免记录为**环境限制**，不以模拟器结论否定真机能力；真机需另测。

---

## 7. 外部阻塞与清理

- **12:12:41 起前台被其他项目 `com.aptora.aptora/.MainActivity` 抢占**（`ActivityTaskManager: Displayed com.aptora.aptora`），此后按任务要求**让出设备、停止交互**；Eir 进程（pid 16802）仍存活，未被杀、未改状态。
- 清理：删除本轮 `uiautomator` 临时文件 `/sdcard/{d2..d9,p1,p2,diag1}.xml` 与 `/tmp/{d2..d9,diag1}.xml`、`/tmp/eir_s1*.png`、`/tmp/eir_s2.png`。
- 未新增/移除 `adb reverse`（仍为预存 `tcp:8080`、`tcp:8731`）；未改动 8731 夹具服务；未清 App 数据。
- 本轮向房间 `# 766248` 播放列表新增了 1 条 `:8731` 测试条目（为复现所需，属本应用自身数据）；因设备已被其他项目占用，未能移回，需后续恢复时删除。

## 8. 汇总

- **PASS/证实**：症状复现；duration=20 可得；`player.state.position` 恒 0；播放管线空闲（无音频/解码/网络/解码线程）。
- **排除**：UI 投影错误；URL 探测与 Range 可达性。
- **证据不足**：与用户豁免的模拟器 EGL/libmpv 故障同一根因（缺 mpv 日志与 VideoController 时序）。
- **未测**：暂停→播放切换读数、纯音频对照、真机。

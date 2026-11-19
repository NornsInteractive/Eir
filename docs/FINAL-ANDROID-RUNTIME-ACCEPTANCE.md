# Eir Android 运行时实际验收（App + Web URL 播放）

- **执行时间**：2026-11-19 11:35–12:05（+08:00，约 30 分钟）
- **执行模型**：已核实免费的 CodeBuddy `deepseek-v4.1-flash`（`x0.00 credits`，无付费回退；hy3 本轮限流退出后接续）
- **性质**：**只做实际验收**。未改产品代码/UI/服务端；未构建、安装、打包、发布；未 `pm clear`/卸载/清数据；未改图形 GPU 设置；未停止或接管其他项目应用。
- **设备**：`172.17.0.1:14251`（`sdk_gphone64_x86_64`，Android 14，x86_64，模拟器）
- **被测包**：`com.norns.eir`，`versionName=1.0.40`，`versionCode=41`，`lastUpdateTime=2026-11-19 11:17:31`
- **APK 指纹**：`02831dedfbddef9a93a33f8ea4583627e021f2717be1b0981f3f975853eece89`（与本轮交接一致；未重复拉取校验）

---

## 1. 结论（先看这里）

| # | 验收项 | 结果 |
|---|---|---|
| 1 | 实际身份与前台空闲（Eir 独占前台，无其他项目抢占） | **PASS** |
| 2 | HTTP Range 206 fixture 与设备侧可达 | **PASS** |
| 3 | App 添加 URL、入清单、切换为 NOW PLAYING | **PASS** |
| 4 | **Android 实测 duration = 00:20** | **PASS** |
| 5 | **Android 连续 position（播放推进）** | **FAIL**（恒为 `00:00`） |
| 6 | **Android seek** | **FAIL**（拖动/点按进度条位置不变） |
| 7 | Web 端真实解码与播放推进 | **PASS**（`ct 0→14.09→20`，`readyState=4`，`320×240`） |
| 8 | 双端同步（App 控制 → Web 跟随） | **PASS（控制下发）** / **FAIL（App 自身未推进）** |
| 9 | App 本地供片 → Web 实际解码 | **NOT TESTED**（被第 5/6 项阻塞） |

**核心判定**：Android 端已能取到真实时长 `00:20`，但播放位置不推进、seek 无效；Web 端同一 URL 正常解码并播放到结尾。因此“实测 Android duration 及连续 position”**只成立 duration，不成立连续 position**。该结果与 [ANDROID-URL-DIAG-HANDOFF](ANDROID-URL-DIAG-HANDOFF.md) 中“持续 Buffering + 00:00”的怀疑方向一致，但本轮是**受控双端实测**，非仅症状记录。

---

## 2. 身份、前台与产物核验（实测）

| 检查 | 实测值 |
|---|---|
| `adb devices -l` | `172.17.0.1:14251 device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64` |
| 系统 | Android 14，ABI `x86_64` |
| 前台 Activity | `com.norns.eir/.MainActivityAliasClassic`（`topResumedActivity` 与 `ResumedActivity` 均为 Eir） |
| 包状态 | `versionCode=41`、`versionName=1.0.40`、`enabled=0`（正常启用）、`lastUpdateTime=2026-11-19 11:17:31` |
| 预存端口映射 | `tcp:8080`、`tcp:8731`（均非本轮新增） |
| 本轮新增映射 | `tcp:8733`（验收后已移除） |

前台检查时设备无 `com.norns.valhalla` / `com.norns.omnitune` 等抢占；全程 Eir 保持前台，未出现外部接管。

---

## 3. 媒体夹具与 Range 实测

- 夹具：`/tmp/eir_media/eir-media-fixture.mp4`
  - 大小 `3,098,261` 字节
  - SHA-256 `f59c34742519dca083c4af34b0e63c2894fde705eebdd9410e134de151960627`
  - `ffprobe`：`duration=20.000000`
- 本轮自建 fixture 服务（仅 127.0.0.1:8733，验收后已停止）实测：

```text
HTTP/1.1 206 Partial Content
Accept-Ranges: bytes
Content-Range: bytes 0-99/3098261
Content-Length: 100
```

- 设备侧通过 `adb reverse tcp:8733 tcp:8733` 访问同一 URL；App 的 `probeMediaUrl` 通过后 URL 才可入清单，本轮 URL 成功入库并显示 `NOW PLAYING`，说明设备侧探测拿到 2xx。

---

## 4. 实测过程与证据

### 4.1 房间与双端连接

- App 侧创建房间 `# 766248`（HOST）。传输状态由 `Server` 变为 **`P2P`**。
- 宿主 Chromium（Playwright，独立 context）打开 `http://127.0.0.1:8080/`，用 **6 位房间码 `766248`** 加入；语义树显示 `MEMBER`、`P2P`，App `Friends (2)`。
- 说明：本轮未改 App 的 `Signaling Config`（默认 `wss://eir.norns.cc.cd/ws`）；尝试切换本地 8080 未持久化，最终双端统一走生产信令。**这是环境事实，不是产品修改**。

### 4.2 URL 入清单与切换

- App `Add Online URL` → `http://127.0.0.1:8733/eir-media-fixture.mp4` → `Playlist (1)`。
- `Switch to this item` 后条目显示 `NOW PLAYING`，播放器出现 `Play (Synced)`。

### 4.3 Android 实测 duration — PASS

显示控制条后，语义节点：

```text
http://127.0.0.1:8733/eir-media-fixture.mp4
00:00 / 00:20
```

- **duration = 00:20**，与夹具 20.000s 一致。
- 播放状态按钮为 `Pause (Synced)`（即 App 认为正在播放）。

### 4.4 Android 连续 position — FAIL

在“正在播放”（`Pause (Synced)`）状态下，多次显示控制条采样，时间恒为：

```text
00:00 / 00:20   （连续 4 次，间隔 2s；另一次播放后 4s 仍为 00:00）
```

- 位置未推进，未取得任何 `00:01`、`00:03` 等递增读数。
- `Friends` 页同步显示：
  - `SilentPanda: Position 00:00 / 00:00`（本机，多次不变）
  - `BreezeOtter: Position 00:01 → 00:05 → 00:09 → 00:19`（Web 端成员，持续递增）
- 即：**Web 端在推进，App 端不推进**。

### 4.5 Android seek — FAIL

- 控制条 `SeekBar` 显示 `0%`，bounds `[605,1046][967,1134]`。
- 点按中点（x≈786）与从 `x=620` 滑到 `x=950` 两种操作后，时间仍为 `00:00 / 00:20`，SeekBar 仍 `0%`。
- 未观察到 seek 提交或位置跳变。

### 4.6 Web 端真实解码 — PASS

Playwright 从真实 `<video>` 读取：

```json
{"src":"http://127.0.0.1:8733/eir-media-fixture.mp4","ct":0,"dur":20,"paused":true,"rs":4,"err":null,"w":320,"h":240}
{"ct":14.09,"dur":20,"paused":false,"rs":4}
{"ct":20,"dur":20,"paused":true,"rs":4}
```

- 完成解码（`readyState=4`）、拿到真实时长 20s、分辨率 320×240、无媒体错误。
- 播放位置从 0 连续推进到 14.09s，最终到 20s 结束并暂停。

### 4.7 双端同步判定

- App 的 `Play (Synced)` 动作成功下发：Web 从 0 开始播放并推进到结尾。
- 但 App 自身播放器不推进，因此“双端一致播放”不成立；暂停/seek 也因 App 端位置恒 0 而无法取得双端一致读数。

---

## 5. 还原与清理

| 项 | 状态 |
|---|---|
| `adb reverse tcp:8733` | 已移除；仅保留预存 `tcp:8080`、`tcp:8731` |
| 本轮 fixture HTTP 服务（8733） | 已停止（`curl` 返回 000） |
| Playwright / Chromium / Xvfb | 已结束本轮进程 |
| 设备临时 XML dump | 已删除 `/sdcard/u*.xml`、`p/q/r/s*.xml` |
| App `Signaling Config` | 未成功修改，仍为 `wss://eir.norns.cc.cd/ws`（与初始一致） |
| App 数据 / 房间 | 未清数据、未卸载；App 仍在房间 `# 766248`（HOST，P2P） |
| 其他应用 / 其他项目 | 未停止、未操作 |
| 产品代码 / 构建 / 安装 / 发布 | 未改动、未执行 |

---

## 6. 限制与未测

1. **App 本地供片 → Web 解码**：NOT TESTED。核心 URL 播放位置不推进已构成明确阻塞，未继续占用时间。
2. **App 端播放缺陷归属**：本轮只证明“duration 可得、position 不推进、seek 无效”，未定位到 media_kit / libmpv / EGL / UI 投影中的具体层；未改产品代码验证。
3. **EGL 图像豁免**：用户已豁免模拟器图像显示问题；本轮**未**把图像问题当作豁免项，播放进度为独立实测，结论不受图像豁免影响。
4. **信令路径**：双端最终走生产信令（`wss://eir.norns.cc.cd/ws`），非本地 8080；本地信令设置未持久化。该差异不影响 URL 播放与进度结论，但记录备查。
5. **历史不一致**：上一房间 `# 935916` 的 `Friends` 曾显示 `SilentPanda: Position 00:20 / 00:20`；本轮受控采样始终 `00:00`，无法据此确认连续推进，故不采信为通过证据。

---

## 7. 证据清单

- App 播放器语义：`00:00 / 00:20`、`Pause (Synced)`、`SeekBar 0%`（本轮 `uiautomator` dump，已清理设备临时文件）。
- `Friends` 语义：`SilentPanda: Position 00:00 / 00:00`；`BreezeOtter: 00:01 → 00:05 → 00:09 → 00:19`。
- Web `<video>` 状态：`dur=20, rs=4, 320×240, err=null`；`ct 0 → 14.09 → 20`。
- 夹具 Range：`206`、`Content-Range: bytes 0-99/3098261`。
- 设备/包：`versionCode=41`、`versionName=1.0.40`、`lastUpdateTime=2026-11-19 11:17:31`、前台 `com.norns.eir/.MainActivityAliasClassic`。

---

## 8. 最终判定

- **PASS**：身份/前台、Range fixture、URL 入清单与切换、Android duration=00:20、Web 真实解码与连续播放。
- **FAIL**：Android 连续 position（恒 00:00）、Android seek（无变化）、由此导致的双端一致播放。
- **NOT TESTED**：App 本地供片 → Web 解码。

建议后续把最小排查点集中在 **Android `open(play:false)` 之后 media_kit 是否推进 position，以及 seek 是否被接受**；本轮未做任何产品修改。

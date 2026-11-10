# Android 渲染配置 rev7 验收记录（rev7 条件性不通过）

- **验收对象**：`lib/views/cinema_view.dart` rev7 —
  `VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec',
  enableHardwareAcceleration: true)`（仅 Android 分支；Web/其他平台走默认配置）。
- **当前文件 hash**：`3425b3ae058de179b753b03dd45c93e08d6f72177878b2c6ecab4b99bae887e6`
  （此前 Web 双端验证的 Rev3 为 `dd68324d…`；rev7 仅改动 Android 分支）。
- **结论**：**双端/SD 卡主流编码通过；硬件不支持编码静默冻结（无像素、无错误、无进度）——
  条件性不通过。** 产品 UI 未被改动；修复需求见 §6 交接。Android release **未**生成
  （未满足"全部通过后生成"的门槛），禁止发布/付款。
- **Norns**：按用户说明 `Norns 已验证`；本会话无内置 Norns MCP 工具，未重复发起连接。
- **日期**：2026-11-08。**设备**：ADB 模拟器 `127.0.0.1:14251`（Android 14 / API 34，x86_64，
  `sdk_gphone64_x86_64`）。

---

## 1. 已安装媒体库实现核查（非假设"官方支持=可用"）

- 锁定版本：`media_kit 1.2.6`、`media_kit_video 2.0.1`、
  `media_kit_libs_video 1.0.7` → `media_kit_libs_android_video 1.3.8`
  （libmpv 构建 `libmpv-android-video-build v1.1.7`，构建期下载）。
- `media_kit_video-2.0.1/.../android_video_controller/real.dart`：
  - **官方默认**：`vo='gpu'`；`hwdec` 未显式指定时走 `getDefaultHwdec()` ——
    已核实开启加速 → `auto-safe`；**检测到 Emulator 时强制 `hw=no`**（即 `'no'`）。
    rev7 显式指定 `hwdec='mediacodec'`，**绕过了官方的 Emulator 软解保护**。
  - 硬编码 `hwdec-codecs: h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1` ——
    该列表之外的编码不会尝试走 MediaCodec。
  - `widListener` 对 `vo=mediacodec_embed` 有特殊处理（重初始化 `vid`），
    说明该 VO 组合在插件层是已知路径；`platform_video_controller.dart` 注释确认
    `vo` 默认仅为 Android `gpu`，故 `mediacodec_embed` 属于**可选非默认**路径，
    本文件用真机证据验证而非依赖文档。
- mpv 语义（据插件默认 `auto-safe` 的反推 + 行为实测）：
  `hwdec=mediacodec` 的含义是**只走 MediaCodec 解码，无软件回退**；
  `vo=mediacodec_embed` 只能渲染 MediaCodec 输出帧，软解帧无法送屏。
  而官方默认 `hwdec=auto-safe` 在硬件不支持时自动落回软件解码（配合 `vo=gpu` 送屏）。
- 模拟器 MediaCodec 实测可用（`dumpsys media.player`）：`c2.android.avc/hevc`、
  `c2.goldfish.h264/hevc`、VP8/VP9/AV1 均存在；**无 Theora / VP7 / FFV1 解码器**，
  与各 Codec `dumpsys` 输出一致。

## 2. 静态分析与回归

- `flutter analyze`（全仓）→ **No issues found!**（rev7 源码；注：临时验证文件存在期间
  会出现 2 个信息级 lint，删除后消失，非产品问题）。
- 宿主单元/Widget 回归：`flutter test test/core test/media test/ui test/widget_test.dart`
  → **147/147 通过**。
- 设备现有回归（rev7 源码）：
  `room_session_url_test` 2/2、`room_session_local_media_test` 2/2、
  `room_session_switch_regression_test` 2/2 —— **6/6 通过**
  （tail-moov 推进、切换往返均真实播放位置断言）。

## 3. 真实 UI 真机验证（ADB 模拟器，真实像素）

临时验证文件（已删除）：`integration_test/_rev7_validate_test.dart`（复刻 rev7 配置；
末项直接挂载真实 `CinemaView` + 真实 `RoomSession` + 真实信令）对同一设备跑通
**8/8**。关键证据（完整日志 `/tmp/r7_full2.log` 已按规范清除，摘要如下）：

| 项 | 结果 | 证据 |
|---|---|---|
| tail-moov 首帧 | 通过 | `rect 320x240`，`id=0`（真实纹理，排除 1x1 占位） |
| tail 推进 | 通过 | 位置 `18.2s`（seek 目标 18s 后到达） |
| seek 到 moov 尾 | 通过 | seek 18s → 实达 `18.2s` |
| pause 保持 | 通过 | 位置锁定无漂移 |
| 切换 tail→head→tail | 通过 | rect 依次 `320x240→160x120→320x240`，每次推进 |
| **引擎像素采样（tail 解码中）** | **通过** | 3503 采样点 `mean=92.9 stdev=78.1 max=226`（彩色 testsrc）——**有真实像素** |
| 真实 CinemaView UI | 通过 | 真实按钮切换/播放：tail `w=320 h=240`、head `w=160 h=120`、真实位置推进 |
| Theora 本地文件探针 | **失败（静默冻结）** | 解包正常 `dur=5s`、`rect` 冒称 `320x240`、`firstFrame=true`，但引擎采样 **3503/3503 全黑**、`mean=0 stdev=0`、位置冻结 `0.033s`、`errors=[]` |
| 恢复（同一播放器回放 tail） | 通过 | 后续打开 tail 立即重启推进（无楔死） |
| 环境说明 | — | 模拟器→宿主 HTTP（`10.0.2.2:8971`）`Connection refused`，连 H.264 也不可达；故 Theora 以本地文件探针执行，不受该层干扰 |

- **像素方法**：`Video` 的 `rect/id` 只反映参数尺寸；故以引擎合成帧
  （`RenderRepaintBoundary.toImage`）做像素级采样。**adb screencap 在此模拟器上看不到
  SurfaceProducer 层**（全黑/底噪），未用作证据。
- **静默冻结细节**：Theora 下用户看到的仅是黑画面 + 无错误、`position` 也冻结在
  `0.033s`；mpv 不抛 `error` 流事件，UI 不弹错误提示，与"卡在 00:00"的历史症状一致的
  误导行为。经核对，`flutter test` 侧**无任何失败被掩盖**。

## 4. 真实源端与独立浏览器接收端

- 以 **rev7 最终源码**重建 Web 产物：
  `flutter build web --release --output=/tmp/eir-web-final-build`
  → `main.dart.js` **sha256 `dbc814074684158341c626ead31dd9a3a517c4d08237dc1fc8930cb4c52841c3`**
  并确认 8730 静态服务实际serve该字节一致的产物（hash 逐字节吻合）。
- 独立双端 E2E（两份独立浏览器上下文、真实信令、真实产品 UI，`test/web/e2e_web_validation.js`）：
  **SUMMARY pass=29 fail=0 warn=1**（两轮一致）。
  - 双端 URL 解码 / 本地 P2P 解码 / 暂停保持 / seek / 缓存占用均 PASS。
  - 唯一 WARN `admin-control-reflects`（`vstate()` 返回数组的原因，`afterAdm.paused` 取到
    `undefined`，属脚本观测口径不一致，**非产品行为结论**）；前序 `pause-holds` 已 PASS。
- rev7 的 Android 守卫分支不影响 Web 路径；Web 证据独立成立。

## 5. 判定

- **PASS**：Android 主流硬件编码（H.264 / HEVC / VP8 / VP9 / AV1 / MPEG4 四者家族，
  以 H.264 tail-moov / head-moov 为代表）真实像素 + 推进 + seek + 切换 + UI 按钮 + 恢复；
  单元/Widget 147/147；设备回归 6/6；Web 双端 29 pass。
- **CONDITIONAL FAIL（真实缺陷）**：`hwdec=mediacodec` 无软件回退，硬件不支持的
  代表性编码（Theora / VP7 / FFV1 等 `hwdec-codecs` 之外格式）表现为**静默黑画面 +
  冻结进度 + 无错误**（引擎像素 `mean=0 stdev=0`，3503/3503 黑）。用户作为广格式
  需求会被直接放弃，且应用层无错误可展示。
- 按约定**不擅改 UI**；Android release **未生成**，未更新交付产物及 hash，
  未执行任何发布/付款操作。

## 6. 交接 Antigravity（UI 唯一owner，会话 70aef10f-…）

**请在 `lib/views/cinema_view.dart` 的 `_createVideoControllerConfiguration()` 中恢复
软件回退**，下列任选其一（推荐第 1 项）：

1. （推荐，改动最小）`hwdec: 'auto-safe'`（保持 `vo: 'mediacodec_embed'` 亦可，
   但需验证 mpv 是否接受软解帧进该 VO；若接受，便能同时保住无 EGL 收益与回退）。
2. 若 1 在该 VO 下仍黑屏：回退到官方默认 `vo: 'gpu' + hwdec: 'auto-safe'`，
   Emulator 的 EGL 失败仅为该模拟器的已知约束，真机正常；或以
   `hwdec: 'mediacodec-copy'` 让 MediaCodec 输出拷贝至系统内存后再由 `vo=gpu` 送屏。
3. 在 `cinema_view.dart` 之外另加 `player.stream.error` 的兜底展示（本仓已有错误提示路径，
   Theora 本次**未**触发 mpv error 流，需对"长时间零推进 + 黑帧"补一个超时兜底）。

验收回归：请在修复后重跑本文件 §3 的 Theora 本地文件探针——期望引擎采样
`mean>30` 且位置推进；重跑 tail/head/seek/切换/UI 四项其余 7/7 不应退化。
需要时本验收侧可原样复跑（临时文件已按约定删除，Hash/产物现状见日志）。

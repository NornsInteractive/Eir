# 相对 seek 业务窄修交接 — 2026-11-18

## 结论

真实缺陷已确认并在**业务层**修复：相对 seek（快进/快退 ±10s）过去用提交锚点
`session.playback.position` 作基准，导致实时播放到 2.42s 时 `+10s` 只跳到 10.0s，
且实时位置超过锚点+10 后会**倒退**。修复改为以实时播放位置为基准，沿用现有
`seek()` 权限/同步提交路径，不改 view、不改 UI 接线、不构建/安装/发布。

- Worker：已核实本机 CodeBuddy `hy3`（`product.json` x0.00 credits，连接探针 OK，无付费回退）。
- 范围：只改业务 core（`lib/core/room_session.dart`）及对应行为测试（`test/core/relative_seek_test.dart`）。
- Norns 本轮协调者已连接；旧本地信令兼容与原子记录属他人变更，未触碰。

## 缺陷与修复要点

- 错误基准：`playback.position` 是最近一次 commit 锚点处的位置（`PlaybackState.position`
  定义为 “Position at anchorSharedMs”），不是实时位置。
- 修复入口：`lib/core/room_session.dart` 新增 `RoomSession.seekRelative(Duration offset)`
  与纯函数 `relativeSeekTarget({base, offset, duration})`。
  - 基准：`_player.state.position`（实时），无 player 时回退 `_expectedPositionNow()`。
  - 上界：优先 player state duration，其次当前条目的声明时长；时长未知则只下界 0，不回零。
  - 下界：`target < 0` 钳到 0。
  - 复用：最终调用现有 `seek()` → `_requestControl('seek', …)`，权限与同步提交路径不变；
    无通用框架、无自研播放器。

## 业务接口（供 Agy 接线，勿改业务逻辑）

```dart
// lib/core/room_session.dart —— 已实现，直接调用
Future<void> RoomSession.seekRelative(Duration offset) async;

// 纯函数，便于单测/复用（可选）
Duration relativeSeekTarget({
  required Duration base,   // 实时播放位置
  required Duration offset, // 正=快进，负=快退
  Duration? duration,       // 已知正时长作上界；null/0 表示未知，不回零
});
```

## Agy 最小 UI 调用契约（本代理未改 view，须由 Agy 接线）

`_seekRelative` 的 6 处按键/按钮调用点（`±10`，`lib/views/cinema_view.dart:1751,1756,3627,3702,5217,5293`）
全部保持不变。**只改 `_seekRelative` 方法体**（`lib/views/cinema_view.dart:361-374`）：

```dart
// 旧（缺陷）：用 playback.position 锚点 + 手算 clamp，时长 0 时回零
final cur = widget.session.playback.position;
final dur = widget.session.player.state.duration;
final target = cur + Duration(seconds: seconds);
final targetMs = target.inMilliseconds.clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 0);
_showGestureHud(seconds > 0 ? 'forward' : 'rewind');
try { await widget.session.seek(Duration(milliseconds: targetMs)); } catch (_) {}
_restartControlsTimer();

// 新（契约）：委托业务层，HUD/定时器/异常吞掉行为保持原样
_showGestureHud(seconds > 0 ? 'forward' : 'rewind');
try { await widget.session.seekRelative(Duration(seconds: seconds)); } catch (_) {}
_restartControlsTimer();
```

不改 `session.signalingUrl`、不改断言、不改其他 UI 语义；仅把目标计算与 seek 调用替换为上面一行委托。

## 测试与验证（实际执行）

`test/core/relative_seek_test.dart` —— **8/8 通过**：

- `relativeSeekTarget` 纯函数：
  - 以实时位置为基准（live 2.42s +10 = 12.42s，且不等于锚点 10s）——覆盖 live≠anchor。
  - 正向 seek 钳到已知时长上界（55+10 → 60）。
  - 反向 seek 钳到 0（3-10 → 0）——覆盖负向 seek。
  - 时长未知（null / Duration.zero）不下界回零（5+10 → 15），反向仍下界 0。
- `RoomSession.seekRelative`（真实 `Player` 状态快照 + 覆盖 `seek()` 的记录会话）：
  - 以实时 player 位置为基准并委托现有 `seek()`（12.42+10 → 22.42）。
  - 用 player duration 作正向边界（55+10 → 60）。
  - 时长未知不回零（5+10 → 15）。
- **授权**：本地信令服务 + 真实 owner/member 加入，未授权 member 调 `seekRelative(+10)`
  经共享 `seek()` 权限门被拒，`lastErrorCode == 'permission_denied'`（无绕过）。

- `flutter analyze lib/core/room_session.dart test/core/relative_seek_test.dart`：**No issues found**。
- 未跑：整仓库全量回归、真实双端 UI 验收（见限制）。

## 限制 / 未验证

- **UI 未接线**：本代理按约束未改 view；新 API 目前无产品调用点，须 Agy 按上节契约接线后才生效。
- **产物未含修复**：当前 Web `main.dart.js`（SHA-256 `cf8735…9928`，version 1.0.40+41）与现有 APK
  均为旧构建，不含本次业务修复；须重新构建后再验收，不能用旧包/旧 JS 证明修复生效。
- **Web seek 验收必须用支持 HTTP Range 的媒体源**：本地 `serve_eir.py`（`SimpleHTTPRequestHandler`）
  对 `Range:` 返回 200 全量、无 `Accept-Ranges`，HTML5 seek 会重启到 0，会被误判为产品缺陷。
- 授权测试在 Dart 单测层用本地信令服务验证 member 拒绝，非真实双端设备。
- 六端原生（Android/iOS/desktop）相对 seek 未逐端实测；本轮只做业务层与 Dart 单测。
- 旧本地信令兼容 / 原子记录 / 成员语义 UI 等他人变更均未触碰，无覆盖。

## 新构建需求（交 Agy）

1. 按上节契约改动 `lib/views/cinema_view.dart:361-374` 的 `_seekRelative` 方法体（仅此一处）。
2. 重新构建 Web + Android + Windows（版本号需可区分旧包），确认新产物包含 `seekRelative`。
3. 用支持 206/Range 的媒体源重跑 seek 验收：live≠anchor 的 `+10` 应落到 live+10；
   增加“播放 > 15s 后按 `ArrowRight` 必须前进而非倒退”的反向用例；同步保持 Δ<0.02s。
4. 发布仅向 Agy 交代“打包 Android 和 Windows 并发布”；本代理未编译、安装、打包或发布。

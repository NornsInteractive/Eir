# 当前完整源码联合回归（2026-11-18）

范围：相对 seek core + UI 接线、本地信令配置兼容、成员列表可访问语义三批改动落地后的
当前工作树。只做一次全量 `flutter test`、一次 Cloudflare Node 测试、对本轮相关 Dart 文件做
`flutter analyze`，并写报告。**未修改产品、UI、测试断言，未执行 formatter，未安装新工具，
未构建/安装/打包/发布，未触碰 Agy 并行的 Android/Web 验收产物与进程。**

## 源码状态

- 仓库：`/workspace/projects/Eir`，分支 `main`，`HEAD = 1db9aa6`；本轮改动均为未提交工作树。
- 相对 seek 业务：`lib/core/room_session.dart` 新增 `relativeSeekTarget` / `seekRelative`。
- 相对 seek UI 接线：`lib/views/cinema_view.dart` 的 `_seekRelative` 委托
  `widget.session.seekRelative(...)`，HUD 与定时器保留。
- 本地配置兼容：`lib/app_settings.dart` 取消旧本地信令地址的硬编码迁移与回写。
- 成员语义：`lib/apple_glass.dart` 新增 `semanticLabel`，`lib/views/cinema_view.dart` 成员行
  改为 `Semantics(container: true)`，动作按钮承接独立语义。
- 旧基线（361 通过）先于上述改动，不再代表当前源码；本报告只以本轮实际执行结果为准。

## 执行命令与结果

| 命令 | 结果 |
| --- | --- |
| `flutter test --reporter expanded` | **344 通过 / 7 失败 / 0 跳过**（`EXIT:1`，耗时 22s，Flutter 3.44.2 / Dart 3.10.0） |
| `node --test test/cloudflare/signaling_worker_test.mjs` | **6 通过 / 0 失败 / 0 跳过**（`EXIT:0`，Node v24.16.0） |
| `flutter analyze`（本轮 9 个相关文件） | **0 error / 4 warning / 2 info** |
| `flutter analyze`（当前全部 25 个已改动 Dart 文件） | **0 error / 4 warning / 5 info** |

Cloudflare 用例全部通过：房间码无 token 解析凭证、仅 roomId 缺 token 不授权、显式 token、
roomCode/roomId 冲突拒绝、协议与 epoch 校验、双人上限与幂等重入。

## 全量 Flutter 结果的失败分解

7 个失败不是 7 个独立缺陷，实际为两个根因：

### 1. 测试替身未跟进新 core API（6 个文件加载失败，31 个 widget 测试未执行）

`test/ui/mvp_ui_flow_test.dart:19` 的 `FakeRoomSession implements RoomSession` 未实现
`RoomSession.seekRelative`，编译期报 “missing implementations for these members”，
并因被其他测试 import 而级联：

- `test/ui/mvp_ui_flow_test.dart`（15 个 widget 测试）
- `test/ui/settings_persist_ui_test.dart`（6 个）
- `test/ui/screen_share_stats_ui_test.dart`（3 个）
- `test/ui/source_offline_ui_test.dart`（2 个）
- `test/ui/profile_view_test.dart`（4 个）
- `test/ui/screen_share_nav_test.dart`（1 个）

归属：**测试代码/测试替身**。产品侧 `lib/core/room_session.dart` 新增方法本身通过 analyze，
`test/ui/relative_seek_ui_test.dart` 自带替身已实现该方法并可编译。修复方式应为给共享
`FakeRoomSession` 补 `seekRelative`（或实现 `noSuchMethod`）；本轮按约束未改测试断言。
这 31 个测试**未执行**，不能记为通过，也不代表对应 UI 功能失败。

### 2. 新 UI 用例对控制栏分支的假设错误（1 个断言失败）

`test/ui/relative_seek_ui_test.dart:155` 期望默认布局直接存在
`ValueKey('cinema-forward-10-btn')`，实际找到 0 个。源码中该键位于
`lib/views/cinema_view.dart:5270` 的“双层控制台”，仅当 `isFullscreen` 或手动
`_isLandscape` 为真时渲染；默认 `_isLandscape = false`（`cinema_view.dart:40`），
`(!isFullscreen && !_isLandscape)` 走单行极简控制栏，不含 ±10 按键。

- 该用例前两步键盘 `ArrowRight/ArrowLeft` 断言已通过，说明 `_seekRelative` →
  `seekRelative` 的 UI 接线在实际可达路径上生效。
- 失败点是“1280×800 物理横屏 ≠ `_isLandscape` 状态”的测试假设，不是产品逻辑缺陷。
- 归属：**测试代码/测试环境**。应改为先进入全屏或调用横屏切换，再断言 ±10 按键。

## Analyze 明细（区分等级）

本轮相关 9 文件：0 error、4 warning、2 info；`lib/` 下 5 个产品文件全部无问题。

- info ×2（测试）：`test/ui/member_semantics_test.dart:6,10` `unnecessary_import`。
- warning ×4（测试）：`test/ui/member_semantics_test.dart:42,44`、
  `test/ui/relative_seek_ui_test.dart:41,43` `override_on_non_overriding_member`
  （`p2pConnecting` / `p2pFailed` 字段并非 `RoomSession` 接口成员，`@override` 多余）。
- 扩展到全部 25 个已改动 Dart 文件后仅多出 3 条 info：
  `test/core/signaling_server_test.dart:146,147,150` `use_null_aware_elements`。
- 无任何 error；上述警告/提示均为测试代码风格，不影响产品行为。

## 限制与未覆盖面

- 31 个 UI widget 测试因测试替身编译错误未执行；全量 344/7/0 只统计实际执行集合。
- 未做真实 Android/Web/Windows 运行验收；未构建任何产品产物；旧 APK/Web 包不含本轮修复。
- Web 相对 seek 验收需支持 HTTP Range 的媒体源（旧 `serve_eir.py` 返回 200 全量会被误判），
  本轮未做真实播放验收。
- 六端原生相对 seek、真实双端成员语义读屏、真实信令配置重启保持均未在设备上复核。
- Agy 并行生成的 Android/Web 验收产物与进程未读取、未改动。

## 第二轮：测试适配修复与复跑（2026-11-18）

仅按最窄范围修改测试代码，产品 `lib/`、UI 接线、断言业务预期均未改动，未删除或跳过任何断言。

- `test/ui/mvp_ui_flow_test.dart`：共享 `FakeRoomSession` 新增 `seekRelative(Duration)`
  记录桩（`lastRelativeSeekOffset` + `notifyListeners`），不复制产品目标计算，不调用
  `relativeSeekTarget`；既有 `seek` 记录与 intent 桩保持不变。
- `test/ui/relative_seek_ui_test.dart`：在键盘 ±10 断言后，用真实 `f` 快捷键进入全屏
  控制台再断言 `cinema-forward-10-btn` / `cinema-rewind-10-btn`，保留键盘与边界接线断言。

| 命令 | 结果 |
| --- | --- |
| 相关 UI 测试 7 文件（含相对 seek 与 6 个共享 fake 依赖方） | **32 通过 / 0 失败**（`EXIT:0`） |
| `flutter test --reporter expanded` | **376 通过 / 0 失败 / 0 跳过**（`EXIT:0`，耗时 18s） |
| `node --test test/cloudflare/signaling_worker_test.mjs` | **6 通过 / 0 失败 / 0 跳过**（`EXIT:0`） |
| `flutter analyze test/ui/mvp_ui_flow_test.dart test/ui/relative_seek_ui_test.dart` | **0 error / 2 warning / 1 info**（`EXIT:1`，均为既有测试风格） |

Analyze 明细：`relative_seek_ui_test.dart:41,43` 的 `override_on_non_overriding_member`
（`p2pConnecting` / `p2pFailed` 非接口成员，`@override` 多余）与
`mvp_ui_flow_test.dart:153` 的 `prefer_final_fields` 均为上一轮已存在、非本轮引入，
按“只清理本轮 unused import/局部变量、不动无关样式”的约束未处理。无任何 error。

## 限制与未覆盖面（延续）

- 本轮全量 376/0/0 仅代表 widget/单元层；未做真实 Android/Web/Windows 设备运行验收。
- 未构建/安装/打包/发布；旧 APK/Web 包不含本轮改动；Agy 并行产物与进程未读取、未改动。
- Web 相对 seek 仍需支持 HTTP Range 的媒体源；六端原生相对 seek、真实双端成员语义读屏、
  真实信令配置重启保持均未在设备上复核。

## 结论与待办归属

- 上一轮阻止全量绿色的两项测试适配问题已修复：共享 `FakeRoomSession` 已跟进
  `RoomSession.seekRelative`，±10 按钮测试已在真实全屏分支执行。
- 本轮当前完整源码联合回归：Flutter **376 通过 / 0 失败 / 0 跳过**、Cloudflare **6/6**、
  相关 analyze **0 error**；测试侧无新增失败，无真实产品失败需转交责任方。
- 仍需在设备上完成六端真实相对 seek 与双端验收；本轮未发布、未构建。

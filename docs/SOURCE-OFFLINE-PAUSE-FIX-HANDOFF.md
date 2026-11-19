# 供片成员离线、无备用项 pause 提交修复交接

## 范围（本轮唯一改动）

- 文件：`lib/core/room_session.dart`
- 位置：`_handleMemberLeft` 中「当前项供片成员离线且无下一可播项」的 `action:'pause'` 分支（约 :1780-1787）。
- 改动：pause 的 `params` 在原有 `'positionMs': 0` 之外补 `'itemId': currentItemId`（当前项 id 来自 `final currentItemId = _playback.itemId`，该分支内已判定非空）。
- 未改：`positionMs: 0`、校验逻辑（`_validateActionParams` :3238-3245）、其余任何文件。

## 缺陷依据（沿用真实红证据，未重复大范围调查）

- `docs/FIXED-WEB-ARTIFACT-ACCEPTANCE.md` 第六节记录了真实场景红结果：120s/65MB 成员本地源、约 1.3s 时供片成员退出、仅有 1 项无备用、缓冲仅约 15.93s（非完整缓存）；owner 未暂停、未清理、未显示离线，继续消耗缓冲至末端才停。
- 静态根因：原 pause 提交 `params` 仅 `{'positionMs': 0}`，缺 `itemId`，被 `_validateActionParams` 对 `play/pause` 的非空 `itemId` 校验判为 `commit_rejected`，既不发送也不本地应用；有备用项时走带 `itemId` 的 `switch_item` 故此前通过。
- 修复后该 pause 参数满足校验，可正常发布并在本地应用，从而进入「无下一可播项则暂停/清理」路径。

## 验证结果

- `dart analyze lib/core/room_session.dart` → `No issues found!`（退出码 0）。
- `flutter test` 相关既有 suite（退出码 0，`All tests passed!`，共 52 项）：
  - `test/media/source_offline_test.dart`
  - `test/media/source_available_test.dart`
  - `test/ui/source_offline_ui_test.dart`
  - `test/ui/member_semantics_test.dart`
  - `test/core/signaling_server_test.dart`
- 说明：仓库现有测试中没有直接覆盖 `_handleMemberLeft` 该分支提交的专门用例；本轮按约束只做这一行业务修复，未新增测试、未改断言。上述结果是回归通过 + 针对校验规则的静态核对，不等同于真实双端复测。

## 未做（遵循本轮约束）

- 未修改 UI、原生构建/打包配置；未安装工具；未整文件格式化；未构建/打包/发布。
- 未改动工作区中其他既有未提交内容：`room_session.dart` 内 `relativeSeekTarget` / `seekRelative` 等更早的改动本轮原样保留，未触碰；其余脏文件同样未触碰。

## 后续（交业务/构建责任方）

- 重建 Web/APK 后，用第六节同一「无备用 + 非完整缓存」真实场景复测（真实 `<video>`、真实 `member_left`、非 mock 状态），确认 owner 自动暂停、清理并显示离线。
- 不要以完整缓存或改 URL/断言的方式掩盖该路径；真实双端业务验收按既有流程执行。

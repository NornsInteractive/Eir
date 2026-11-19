# 角色授予 / 重入房 修复与移交说明（ROLE-REJOIN-FIX-HANDOFF）

- 执行角色：已核实免费 CodeBuddy `deepseek-v4.1-flash`（`product.json` x0.00 credits，无付费回退）
- 执行时间：2026-11-18 15:24 – 15:52
- 被验收对象：Agy 当前预修复产物（未重建）
  - 服务：`http://127.0.0.1:8080/`，`version.json` = `1.0.40+41`
  - Web：`main.dart.js` SHA-256 `cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928`（本轮重新拉取核验，与既有记录一致）
  - APK：`eir-v1.0.40.apk` SHA-256 `e40acbd8a0b467d1d04c7fb84cf4a4be59d9636717f95027bb3fe8f861e`（未重装、未重建）
- 证据目录：`/tmp/eir-acceptance-current/`
  - `grantprobe.js` / `grantprobe.json` / `grantprobe-wire.json`
  - `rejoinprobe.js` / `rejoinprobe.json`
  - `rejoinloop.js` / `rejoinloop.json` / `rejoinloop-wire.json`
  - 截图：`evidence/shots/grantprobe-A.png`、`grantprobe-B.png`、`rejoin-A.png`、`rejoin-B.png`、`rejoinloop-A.png`、`rejoinloop-B.png`

## 结论（先看这里）

两个指定目标在**修正后的真实浏览器 harness** 下均未复现为产品业务缺陷：

| 目标 | 本轮结论 | 性质 |
|---|---|---|
| (1) 房主点击 Grant Admin 后 guest 仍为 MEMBER、无本地添加入口 | **PASS**：点击真实 88×30 按钮后 A/B 均显示 ADMIN，B 出现 `Add Local Video` / `Add Online URL` | 旧 harness 选中了错误的语义节点（成员行），**不是业务 bug** |
| (2) 同邀请/同身份退出→重入不稳定 | **PASS 3/3**：身份不变、`rejoined=true`、房间码不变、`inviteEpoch` 不变、播放列表 `(1)` 恢复、无 `disbanded` | 旧 harness 的离开确认/房间信息读取问题，**不是业务 bug** |

因此：**本轮未修改 `lib/core/room_session.dart`、`lib/core/commit_log.dart`、`server/signaling_server.dart` 或任何 UI/业务源码**，未触发重建，当前产物仍为 Agy 预修复包。不存在“旧包冒充修复”。

## Harness 修正（两个目标共同前置）

旧脚本的问题之一是本地网络配置可能被生产 `api/config` 覆盖或迁移。本轮所有探针统一使用：

1. 写入权威网络记录（`SharedPreferences` web 前缀为 `flutter.`）：

```js
localStorage.setItem('flutter.eir_setting_signaling_url', JSON.stringify('ws://127.0.0.1:8080/ws'));
localStorage.setItem('flutter.eir_setting_network_config', JSON.stringify({
  serverDomain: 'http://127.0.0.1:8080',
  signalingUrl: 'ws://127.0.0.1:8080/ws',
  turnServer: '', turnUsername: '', turnCredential: '',
  lastConfigSyncTime: 0,
}));
```

对应读取点：`lib/app_settings.dart:386-397`（权威记录覆盖旧标量）、`lib/app_settings.dart:746`（记录解析）。

2. 在上下文创建时拦截远程配置：

```js
await context.route('**/api/config', r => r.abort());
```

3. 每个上下文独立、throwaway；不清理设备/浏览器用户数据。

4. 使用真实 UI 语义点击；涉及 `role=button` 嵌套时，按**最小面积的真实动作按钮**点击，不再用 `.first()`。

## 目标 (1)：Grant Admin 未生效

### 精确复现步骤（`grantprobe.js`）

1. 两个独立 Chromium 上下文 A/B，固定本地信令并拦截 `**/api/config`。
2. A 创建 Cinema Room，`Copy Invite` 得到 6 位房间码；B 写入剪贴板后 `Quick Join`。
3. A 打开 `Friends`，枚举所有包含 `Grant Admin` 的 `role=button` 节点。
4. 点击真实动作按钮（88×30），等待 2.5s。
5. 读取 A 的成员行、B 的角色徽章与添加媒体入口。

### 实际观察（`grantprobe.json`）

```
[PASS] setup :: A=owner B=member code=496572
[OBSERVE] grant-count :: count=2 bShort=2dd8563562cc
[OBSERVE] grant-candidates :: [
  {"i":0,"label":"CobaltDolphin\n2dd856...f172\nMEMBER\nGrant Admin: CobaltDolphin",
   "text":"CobaltDolphin: Position 00:00\n00:00Grant Admin","area":80256,"w":1216,"h":66,"x":32,"y":547},
  {"i":1,"label":"","text":"Grant Admin","area":2644,"w":88,"h":30,"x":1148,"y":565}
]
[PASS] grant-click :: index=1 label=|Grant Admin|88x30
[PASS] post-grant-role :: B admin=true member=false
  | A rows=["CobaltDolphin\n2dd856...f172\nADMIN\nRevoke Admin: CobaltDolphin"]
  | B rows=["...ADMIN...Add Local VideoAdd Online URL..."]
[PASS] B-local-add-entry :: count=2
```

信令侧（`grantprobe-wire.json`）：`join_accepted.members` 中 B 的 `deviceId` 为
`2dd856...f172`，与 A 点击的按钮对应的成员行一致；无 `error` 帧。

### 根因

- UI 中成员行（1216×66）与内部动作按钮（88×30）**都**暴露为 `role=button`。
- 成员行的 `aria-label` 末尾包含 `Grant Admin: <name>`，因此
  `getByRole('button', { name: /Grant Admin/ })` 匹配到 2 个节点。
- 旧 harness 使用 `.first()`，命中的是 1216×66 的成员行；点击该行不会触发
  `widget.session.grantAdmin(...)`，所以提交未发送、B 保持 MEMBER。
- 点击真实的 88×30 按钮后，产品链路正常：
  `cinema_view.dart:6119-6143` → `session.grantAdmin(member.deviceId)`
  → `room_session.dart:4667` → `_ownerOnlyAclAction` → `_publishCommit`
  → `commit_log.dart:268-273`（`grant_admin` 置为 `admin` 并递增 ACL version）。
- 业务侧对目标 `memberId` 的校验（`room_session.dart:3320-3328`、
  `commit_log.dart:268-273`）在收到真实成员 ID 时通过；未发现目标成员选错或提交丢失。

### 分类与处理

- **不是业务 bug**。旧失败是 harness 选择器歧义；修正为按最小面积真实按钮点击后通过。
- **UI 移交（非验收阻塞，仅无障碍语义）**：成员行被暴露为 `role=button` 且标签含
  `Grant Admin`，但点击行本身无动作。若 Agy 要消除歧义，可让成员行不暴露为
  button，或让动作按钮成为唯一带 `Grant Admin` 标签的可点击节点。
  本轮**未编辑 UI**；若 Agy 修改，需重建 Web/APK 后按下方范围复测。

## 目标 (2)：同邀请/同身份退出→重入

### 精确复现步骤（`rejoinloop.js`）

1. A 建房，B 用 6 位码 `Quick Join` 入房；记录 B 的 `join_room.deviceId`。
2. A 授予 B admin（真实 88×30 按钮），并添加 1 个 URL，使房间快照含 1 项。
3. 连续 3 轮：
   - B 点击 `Leave Room`；
   - 在确认对话框点击 `Leave`；
   - 等待回到大厅；
   - 将同一房间码写入剪贴板，点击 `Quick Join` 重入；
   - 读取 B 的角色/房间码/播放列表，读取 A 的成员与房间态；
   - 检查信令 `join_accepted`、`member_joined`、`error`、`disbanded`。

### 实际观察（`rejoinloop.json`，3/3 PASS）

每轮共同结果：

- `leftOk=true`：B 确实回到大厅（确认对话框已处理）。
- `bNow.role=member`、`bNow.code=885822`：重入成功且房间码不变。
- `acc.rejoined=true`：服务端按同身份幂等重入接受。
- `acc.inviteEpoch=1`：与首次加入一致，未被误轮换。
- `bIdSame=true`：重入前后 `deviceId` 完全相同。
- `errs=[]`：无 `invalid_invite` / `invite_consumed` / `invite_stale` / `room_not_found`。
- A 收到 `member_joined{rejoined:true}`；A 仍为 `owner`，房间未解散。
- `disband=false`：全程无 `disbanded`。
- `Playlist (1)`：重入后播放列表快照恢复为 1 项。

其中 admin 场景（`rejoinprobe.json`）额外验证：B 退出前为 `ADMIN`，重入后仍为
`ADMIN` 且保留 `Add Local Video` / `Add Online URL`。原因是房主在 P2P 握手后发送
房间快照，B 通过 `_acl.loadSnapshot(...)`（`room_session.dart:4440-4449`）恢复 ACL；
`grant_admin` 的 ACL version 随快照一致。

### 旧 `S1-B-rejoin FAIL` 的根因

旧证据为 `code= devSame=false playlist=-1`，与本轮 3/3 通过不一致。对照旧脚本：

- `roomInfo()` 依赖先点击 `Room Info` 标签，再用
  `texts.find(t => /^[0-9a-f]{64}$/.test(t))` 取设备 ID；
- 实际语义中设备 ID 常与其它文案合并在同一长文本节点（本轮观察为
  `Device ID: <64hex>` 或长房间卡片文本），单独 64hex 节点并不稳定存在；
- 离开/重入后若标签抽屉或确认层未完全关闭，`Room Info` 点击可能失败，
  导致 `code` 与 `dev` 同时为空；
- 旧脚本以 `Play (Synced)` 出现作为重入等待条件，该控件不是重入成功的稳定判据。

因此旧 FAIL 更符合 **harness 观察/状态读取问题**，不是产品重入失败。本轮用真实
`Leave` 确认、同码 `Quick Join`、直接读取角色/房间码/播放列表与信令帧，3 轮均通过。

### 非阻塞观察：服务端成员列表中的 role

重入 admin 场景下，服务端 `join_accepted.members` 中该成员 `role` 显示为 `member`
（`rejoinprobe.json`），而客户端 ACL 快照恢复后 UI 为 `ADMIN`。原因：

- `grant_admin` 是客户端签名 commit，经 DataChannel 传播，服务端不维护 ACL；
- 服务端 `_Room.membersList()` 的 `role` 只来自 `conn.role`（owner/member）；
- 客户端 `_handleJoinAccepted` 不读取该 `role` 字段，角色以本地 ACL 为准。

该差异当前**不影响用户可见行为**。若要服务端 role 与 ACL 一致，需要新增服务端
ACL/协议同步，属于新协议/新功能，超出本轮“不新增协议/功能”的约束，故未修改。

## 修改文件

- 业务/服务端/UI 源码：**无修改**。
- 新增文档：`docs/ROLE-REJOIN-FIX-HANDOFF.md`（本文件）。
- 仅新增 `/tmp` 验收探针：`grantprobe.js`、`rejoinprobe.js`、`rejoinloop.js`
  及对应 JSON/截图；未改动仓库基线测试与既有脚本。

## 测试命令与结果

相关业务测试（真实 `RoomAcl` / 信令服务端 / 继任逻辑）：

```bash
cd /workspace/projects/Eir
flutter test \
  test/core/commit_log_test.dart \
  test/core/signaling_server_test.dart \
  test/core/room_succession_and_playlist_test.dart
```

结果：**47 passed，0 failed**（`All tests passed!`）。其中包含：

- `same identity can rejoin idempotently after dropping`
- `invite is single-use and bound to one identity`
- `join with stale invite epoch is rejected`
- `Succession sorting prioritizes admins over regular members`

窄范围静态检查：

```bash
dart analyze \
  lib/core/room_session.dart \
  lib/core/commit_log.dart \
  server/signaling_server.dart
```

结果：**No issues found!**

## 重建与复测范围

- 本轮**无源码修复**，因此**不需要 Agy 重建**；当前 Web/APK 产物与上述 PASS 结论对应。
- 若 Agy 仅调整成员行/按钮的无障碍语义（目标 1 的 UI 移交项）：
  1. 重建 Web 与 APK（按 Agy 既有流程）；
  2. 用 `grantprobe.js` 复测：真实 88×30 `Grant Admin` 按钮仍存在且唯一，点击后
     A/B 均为 ADMIN、B 出现 `Add Local Video` / `Add Online URL`；
  3. 用 `rejoinloop.js` 复测 3 轮：同身份、`rejoined=true`、房间码/epoch 不变、
     `Playlist (1)` 恢复、无 `disbanded`。
- 若后续出现真实业务修复，必须在 Agy 重建 Web+APK 后重新跑上述两个探针，
  不得用当前旧包声明修复通过。
- 复测命令（服务已由 Agy 保持 `8080` 存活时）：

```bash
cd /tmp/eir-acceptance-current
xvfb-run -a node grantprobe.js
xvfb-run -a node rejoinloop.js
```

## 未覆盖 / 限制

- 本轮只做两个指定目标；seek/next 由另一代理诊断，未触碰。
- 仅浏览器双上下文真实验收，未做原生 Android/iOS 业务交互；未 build/install/uninstall/publish。
- 未清设备或浏览器用户数据；未改图形设置；未停止 `8080` 服务。
- 目标 2 为 3 轮连续重入；更长压测/弱网/服务端重启不在本轮范围。

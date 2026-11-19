# Eir 当前源码双端实测验收（FORMAL 60min）

- 执行角色：已核实免费 CodeBuddy `hy3`（`product.json` x0.00 credits；无付费回退）
- 执行日期：2026-11-18 14:35 – 15:22（约 47 min，早于 60 min 硬性上限收尾）
- 被验收对象：Agy 当前脏源码产物 `1.0.40+41`（非仅凭版本号，已做只读哈希关联）
- 证据目录：`/tmp/eir-acceptance-current/`（脚本、JSON、日志、截图 `evidence/shots/`）
- 方式：两个独立 Playwright Chromium 上下文（throwaway）+ 真实本地信令 WS 线探针。**未使用原生 App 业务交互**。

## 结论速览

| 场景 | 结论 |
|---|---|
| S1 建/邀/入/退/重入房 + roomCode/roomId 准入 | PARTIAL（重入子项 FAIL，见 S1） |
| S2 双角色本地文件远端解码 | PARTIAL：owner→guest PASS；guest→owner FAIL（见 S2） |
| S3 URL 同步 播放/暂停/进度/倍速/natural-next | PARTIAL：解码/播放/暂停/倍速 PASS；seek 数据双向一致但断言方向失败；natural-next NOT TESTED |
| S4 设置语言/主题可见且房间身份保持 | PASS |
| S5 真实 RoomSession owner 退出→成员继任 | PASS |
| S6 成员本地源退出→房主切换/暂停 | NOT TESTED |
| S7 通话连接/挂断、投屏 start/stop/nullable stats、stale 信号边界 | NOT TESTED |
| 模拟器 GPU/渲染 | WAIVED（用户豁免，记录不修，非真机通过） |
| 原生 Android App 业务 | NOT TESTED（本轮仅宿主浏览器双上下文） |

## 产物 / 源码关联（只读核验）

- Git HEAD：`1db9aa670ceff2ab80f3502f3664ee3e76f4c5fc`，工作树按预期 dirty（Agy 在改）。
- APK：`eir-v1.0.40.apk` SHA-256 `e40acbd8a0b467d1d04c7fb84cf4a4be59d9636717f95027bb3fe8f861e`（与 Agy 提供一致）。
- Web：serve `main.dart.js` SHA-256 `cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928`（与磁盘一致）；`version.json` = `1.0.40+41`。
- 设备：`172.17.0.1:14251` Android 14 x86_64，app versionCode 41 / 1.0.40；`adb reverse tcp:8080` 预先存在。
- 服务：tmux `eir-server` 存活，`http://127.0.0.1:8080/` 200、WS `/ws` 正常；**未停止服务**。
- 结论：产物与当前脏源码关联成立；版本号 `41` 单独不作数，已用哈希佐证。

## 关键环境根因（务必记录）

当前产物 `AppSettings.load()` 会把本地 `ws://127.0.0.1:8080/ws` 自动迁移为 `wss://eir.norns.cc.cd/ws`，且启动后台 `RemoteConfigService.syncOnStartup()` 从 `<serverDomain>/api/config` 拉取配置覆盖本地值（`lib/app_settings.dart:240`、`lib/core/remote_config_service.dart:114`）。这导致浏览器上下文 join 时偶发连到生产服，报 “Room not found or has been disbanded”。**这是当前源码行为，不能据此认定为产品设计预期**。`CURRENT-REPAIR-PLAN.md` 要求信令地址明确保存及当前房间地址隔离；仅有旧标量存储且用户明确选择本地地址时的自动迁移、以及启动远程配置覆盖手动配置的边界仍需专项确认。本轮未扩大配置修复范围。本轮验收脚本用两步解决：写入权威网络配置记录 `flutter.eir_setting_network_config`（`lib/app_settings.dart:746`）+ 路由拦截 `**/api/config`，使双端稳定固定在本地服。`joindbg2.log` 中 `B input value after type=` 为空是早期脚本把 6 位房间码敲进“加入码输入框”失败所致；正确路径是 `Copy Invite` 得到 6 位码后写剪贴板触发 “Cinema invite detected” + `Quick Join`（`main-e2e.js joinInvite`），已验证可靠。

## S1 建/邀/入/退/重入房 — PARTIAL（重入子项 FAIL）
证据：`main-e2e.json`、`evidence/shots/S1-A-room.png`、`S1-B-room.png`。
- PASS：A 建房（Disband Room）、读房间码、`Copy Invite`→6 位码、B `Quick Join` 入房、同房间码、两端 `Friends (2)`、B 退出回大厅。
- 准入线探针 `s2-wire-probe.json`（真实 WS）：`room_created` / 6 位 `roomCode` / 仅 roomCode 无 token 入房 PASS / 原始 roomId 无 token 拒绝 `invalid_invite` PASS / 错 token 拒绝 PASS。当前服务器规则符合预期。
- FAIL（重入）：`S1-B-rejoin code= devSame=false`。退出后再次入房未稳定恢复房间态；可能受上述剪贴板/自动迁移竞态影响，不能判定为 PASS。需单独回归。

## S2 双角色本地文件远端解码 — PARTIAL
证据：`s3-run.json`、`s3-run2.log`、`evidence/shots/S3a-owner-local.png`、`S3a-guest-decode.png`。
- PASS（owner→guest）：A 用 `Add Local Video` 直接选本地文件 `eir-media-fixture.mp4`（注意：直接选择即触发 filechooser，无 “Pick Local Video” 中间按钮），切到该项并播放；A `ct=4.12 rs=4 blob=true 320x240`，B `ct=4.1 rs=4`，B 源 `http://127.0.0.1:8080/eir-media/...`（产品自带 `/eir-media/` 桥）。真实双向媒体传输 + 远端解码成立。
- FAIL / NOT TESTED（guest→owner）：`S3b-guest-local-to-owner no filechooser`。根因观察：owner 点击 `Grant Admin` 后，B 自身 UI 仍显示 `MEMBER`，未出现 `Add Local Video` / `Add Media`。源码 `isHostOrAdmin = role==owner||role==admin`（`cinema_view.dart:1418/1734`）会隐藏添加入口；`role` getter 走 `_roleFor(self)`→`_acl.roleOf`（`room_session.dart:345`）。说明 grant_admin 提交未在 B 端同步成 admin（根因待查：提交未送达 / 目标成员选错 / ACL 应用缺陷）。**不冒充通过**；该失败若为产品缺陷则修业务需重新构建，不在本轮内。

## S3 URL 同步 — PARTIAL
证据：`main-e2e.json`、`s4-controls.json`、`evidence/shots/S4-controls-A.png`、`S4-controls-B.png`。
- PASS：A 加 URL→两端 playlist=1；两端真实 `<video>` 解码（A ct 1.25→4.8 rs4 dur20，B 1.23→4.8 rs4）；键盘 Space 暂停两端 `paused=true`；`]` 倍速两端 `rate=1.25`（`lib/views/cinema_view.dart` 快捷键 Space/←/→/[ / ]）。
- seek：`s4-controls` 断言 `A ct 3.42->0.85 B.ct=0.86` — 两端时间点一致（同步生效），但方向断言（期望 +10s）不成立，记为未通过；同步方向需复核。
- natural/explicit next：NOT TESTED（脚本在到达该步前受控件自动隐藏/抽屉态影响未产出有效证据）。
- UI 说明：控制条 4s 自动隐藏、Playlist 抽屉遮挡播放器，点击视频即切换播放；这些是 UI 接线问题，归 Agy，**本轮不改 UI**。

## S4 设置与身份保持 — PASS
证据：`main-e2e.json`。切中文后 zh 标签可见；房间码 / 设备 ID / 连接态在设置前后一致（`codeStable devStable connected`）。

## S5 真实 RoomSession owner 退出→成员继任 — PASS
证据：`s3-s6.json`、`evidence/shots/S6a-member-became-owner.png`。
- 真实产品交互：A(owner)、B(member) 同房；关闭 A 的 socket（真实 owner 掉线，非 Disband 按钮）；B 从 `member` 变为 `owner`（出现 `Disband Room`，说明应用收到 `owner_changed`）。
- 与 `SESSION-SUCCESSION-HANDOFF.md` 记录一致：当前实现以 server 权威 `owner_changed` 继任；旧 A14 固定 owner 规则冲突仍按文档保留，未删除当前功能。普通成员退出未单独断言不触发 `owner_changed`（见 S6 NOT TESTED）。

## S6 成员本地源退出→房主切换/暂停 — NOT TESTED
时间/前置受限：受 S2 guest 角色未升级阻塞，未能构造“成员本地源为当前项后退出、房主切换到备用可播放项或无项则暂停”的真实双端场景。比较器单测不足以替代，记为 NOT TESTED。

## S7 通话 / 投屏 / stale 信号边界 — NOT TESTED
环境未充分具备权限与时间，未做真实通话连接/挂断、投屏 start/stop/nullable stats。不得用单测或伪造信号冒充通过。stale 信号边界可后续用真实 UI 信号日志与既有测试结果分离标注。

## 根因 / 修复 / 重建
- 本轮**未修改任何业务或 UI 源码**，未触发重建（无“旧包冒充修复”）。
- 唯一具体失败（guest 添本地文件被角色门控挡住）根因观察已记录于 S2；若判定为业务缺陷需修 `grant_admin` 角色同步并重建 Web + APK 后重测，本轮按约定停止该场景并上报。
- 脚本/环境问题（旧 UI 标签 `Session Info`、邀请串 `eir:v1:`、剪贴板输入、自动迁移信令、filechooser 触发时机）均为 harness 适配，已在 `/tmp` 内修正，未改动仓库基线测试。

## 设置还原 / 副作用
- 浏览器上下文为 throwaway，未改任何原生 App 设置；未清设备/浏览器用户数据。
- 未 build / install / uninstall / publish；未改图形设置；tmux `eir-server` 保持存活。
- 临时媒体夹具 `build/web/sample.mp4`、`short-a.mp4`、`short-b.mp4` 已删除，目录恢复原状；删除后 `main.dart.js` 哈希不变，`/sample.mp4` 返回 404。
- 过程说明：排障期曾 `tail` 一次本地 `server/server.log`（仅启动行），非 Agy 会话日志；除此外未读取 Agy 日志/状态。

## 移交协调者
- UI 类问题（控件 4s 自动隐藏、Playlist 抽屉遮挡播放器控件、房间码而非邀请串的 UI 语义）交既有 Agy 会话。
- 业务候选问题（guest 被授予 admin 后本地角色未升级，导致无法从成员侧添加本地媒体）建议 OpenCode/CodeBuddy 核实修复并重建后复测 S2/S6。
- 本轮不发布、不 rebuild，产物仍为 Agy 当前包。

# Guest 供片端离线 / 成员退出 双浏览器真实验收（GUEST-SOURCE-OFFLINE-ACCEPTANCE）

- 执行角色：外部已核实免费 CodeBuddy `deepseek-v4.1-flash`（本机 `product.json` 标注 `x0.00 credits`，无付费回退）
- 执行时间：2026-11-18 15:36 – 15:44（20 分钟窄范围窗口内完成）
- 被验收对象：当前 Agy 预修复产物，未重建
  - 服务：`http://127.0.0.1:8080/`，`version.json` = `1.0.40+41`
  - Web：`main.dart.js` SHA-256 `cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928`
  - 本轮开始与结束时两次核验，哈希一致；未发生产物替换
- 证据目录：`/tmp/eir-acceptance-current/source-offline/`
  - 脚本：`run.js`、`recheck.js`
  - 日志/JSON：`run.log`、`acceptance.json`、`recheck.log`、`recheck.json`
  - 截图：`shots/`（8 张，见各子项）
- 方式：两个独立 throwaway Playwright Chromium 上下文，真实产品 UI 操作；本地信令固定 `ws://127.0.0.1:8080/ws`，上下文级拦截 `**/api/config`；使用既有 `grantprobe.js` 的最小面积真实按钮点击法与 `s3-run.js` 的 filechooser/localmedia 链路。未触碰 seek/next。

## 结论速览

| 子目标 | 结论 | 性质 |
|---|---|---|
| 1. 真实 Grant Admin（88×30 按钮）→ guest 变 admin 并添加 LOCAL 文件 → owner 实际接收/解码 | **PASS** | 真实业务链路通过 |
| 2. guest 供片项为当前项，guest 经真实 UI 确认退出 → 无备用项时 owner 暂停 | **FAIL** | **真实业务缺陷**：pause commit 参数缺少 `itemId`，被本地校验拒绝，owner 继续播放已离开 guest 的媒体 |
| 2b. 有 owner 可播放备用项时 → owner 自动切换到备用项并继续播放 | **PASS** | 真实业务链路通过 |
| 3. 普通成员退出不得触发 `owner_changed` 或改变 owner | **PASS** | 真实信令/UI 通过 |
| 产物哈希核验 | **PASS** | 与约定哈希一致 |
| AppSettings legacy-local 配置修复运行时验证 | **NOT TESTED（明确排除）** | 当前服务产物不含该修复；本轮只验证媒体业务，未声称配置运行时已验证 |

## 目标 1：Grant Admin + guest 本地文件 → owner 解码 — PASS

真实操作序列：

1. A 创建 Cinema Room，B 用 6 位房间码 `Quick Join`；A=owner、B=member。
2. A 打开 `Friends`，枚举所有 `role=button` 且文本精确为 `Grant Admin` 的节点，只得到 1 个真实动作按钮：`88×30`、area `2644`（`x=1148,y=565`）。点击该按钮。
3. B 立即变为 `ADMIN`，出现 `Add Local Video` / `Add Online URL`。
4. B 通过真实 `Add Local Video` filechooser 选择 `/tmp/eir-media-fixture.mp4`（20.0s，320×240），切到该项并播放。
5. A 侧真实 `<video>` 状态：

```
A src = http://127.0.0.1:8080/eir-media/261164.../758648...
A ct  = 1.32 → 2.08   (持续前进)
A rs  = 4             (HAVE_ENOUGH_DATA)
A dur = 20, 320×240, err=null, paused=false
B src = blob:http://127.0.0.1:8080/...  ct=1.32 rs=4
```

结论：不是仅收到控制消息。owner 侧真实媒体元素已加载远端 guest 本地文件、`readyState=4`、`currentTime` 连续前进；A 的源为产品自带 `/eir-media/` 桥 URL。**PASS**。

证据：`acceptance.json` 中 `T1-grant-admin`、`T1-guest-local-owner-decode`；截图 `shots/T1-owner-decoding-guest-local.png`、`shots/T1-guest-admin-playing-local.png`。

## 目标 2：guest 供片端退出 — 无备用项暂停 — FAIL（真实业务缺陷）

复现（同一房间，playlist 仅 1 项，且为 B 的本地文件）：

1. B 为 admin，添加 `/tmp/eir-media-fixture.mp4` 并设为当前项、播放。
2. A 已真实解码该远端项（`ct≈1.08, rs=4`，src 为 `/eir-media/...`）。
3. B 点击真实 `Leave Room`，确认对话框点击 `Leave`；B 回到大厅（`hadConfirm=true, lobby=true`）。
4. A 收到真实信令 `member_left{deviceId=865d07a3...}`；无 `owner_changed`；A 仍为 owner。
5. 退出后 1/4/8/12 秒连续采样 A 的真实播放器：

```
t=1s   ct=5.52  paused=false  rs=4  src=/eir-media/...
t=4s   ct=8.59  paused=false  rs=4
t=8s   ct=12.68 paused=false  rs=4
t=12s  ct=16.77 paused=false  rs=4
providerLeft 徽标 = false；Media Source Offline 覆盖层 = false
```

即：供片端成员已离线、当前项无其他可播放备用项，owner **既未暂停，也未进入 source_offline 状态**，仍在播放该已离开 guest 的媒体（20s 夹具，12s 内未触及 EOF，排除 EOF 掩盖）。

根因（只读代码定位，未修改）：

- `lib/core/room_session.dart:1744-1766`：`_handleMemberLeft` 在无下一可播放项时发布
  `action: 'pause'`，params 仅有 `{'positionMs': 0}`，**缺少 `itemId`**。
- `lib/core/room_session.dart:3219-3225`：`_validateActionParams` 对 `play`/`pause` 强制要求
  `params['itemId']` 为非空字符串，否则返回 `commit_rejected`。
- 因此该 pause 在 `_publishCommitNow` 的本地校验阶段即被拒绝，既不发送也不本地应用；
  owner 播放状态保持不变。
- 对比：有备用项时走 `switch_item`，params 含 `itemId`，校验通过并本地应用，故目标 2b 正常。

影响：用户可见——供片者退出后，房主在无备用项时不会按设计暂停，会继续播放已离开成员的本地媒体（在其已缓冲范围内），且不显示“供片端离线/提供者已离开”状态。属于媒体业务逻辑缺陷，不是 harness 或渲染豁免问题。

证据：`recheck.json` 中 `A2-no-backup-extended`（含 4 次采样与 wire）；`acceptance.json` 中 `T2-no-backup-pause`；截图 `shots/A2-no-backup-12s-after-leave.png`、`shots/T2-no-backup-owner-after-leave.png`。

处理：按本轮约束**未打补丁**，交由 root 分派修复。修复后需重建 Web/APK，并用本目录脚本复测。

## 目标 2b：有 owner 备用项 → 自动切换 — PASS

复现：

1. A（owner）先添加自己的本地备用项 `/tmp/eir_20a.mp4`（20.0s）。
2. 授予 B admin；B 添加 `/tmp/eir-media-fixture.mp4`，切为当前项并播放。
3. A 真实解码 B 的远端项：`ct≈1.05, rs=4, src=/eir-media/...`。
4. B 真实 `Leave Room` + `Leave` 确认（`hadConfirm=true, lobby=true`）。
5. A 在 10s 内切换到自己备用项：

```
切换前 src = http://127.0.0.1:8080/eir-media/8397c7.../c1e...  ct=1.05
切换后 src = blob:http://127.0.0.1:8080/44f8d0aa-...           blob=true
ct 4.12 → 5.62（1.5s 内 +1.50，持续播放）
paused=false, rs=4, dur=20, 320×240
A 仍为 owner；member_left 收到；owner_changed 为空
```

结论：owner 自动切换到自己的可播放备用项并真实解码/推进。**PASS**。

证据：`recheck.json` 中 `B2-fallback-switch`；`acceptance.json` 中 `T2F-pre-leave-decode`；截图 `shots/B2-fallback-after-switch.png`、`shots/T2F-owner-playing-guest-item.png`、`shots/T2F-owner-switched-backup.png`。

## 目标 3：普通成员退出不触发 owner_changed — PASS

复现（独立房间，B 未授予 admin，保持普通 member）：

1. A 建房，B `Quick Join`，A=owner、B=member。
2. B 点击真实 `Leave Room`，确认对话框点击 `Leave`；`hadConfirm=true, lobby=true`。
3. A 侧真实信令：收到 `member_left{deviceId=e260471a0078...}`；`owner_changed` 0 条；无新的 `member_joined`。
4. A UI 仍为 owner（`Disband Room` 存在）；`Friends` 仍显示房间成员记录，未发生 owner 转移。

结论：普通成员退出不会触发 `owner_changed`，现有 owner 不变。**PASS**。

证据：`acceptance.json` 中 `T3-member-leave-no-owner-change`；截图 `shots/T3-owner-after-member-leave.png`。

## 产物与环境

- Web 哈希（开始/结束）：`cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928`，与约定一致。
- `version.json`：`{"app_name":"eir","version":"1.0.40","build_number":"41"}`。
- 未修改任何产品源码/UI/测试/服务端；未 build/install/uninstall/publish；未清设备或浏览器数据；未改图形设置；未停止 `8080` 服务。
- 未向 webroot 复制任何临时夹具；本轮媒体文件均从 `/tmp` 通过真实 filechooser 选择，因此无需清理 webroot。
- 浏览器上下文均为 throwaway；结束后已关闭，未保留登录/房间状态。
- 本轮未使用 seek/next，也未与其他代理的 seek/next 场景交互；房间码与上下文独立。

## 限制

- 仅宿主浏览器双上下文真实业务验收；未做原生 Android/iOS 业务交互，未据此声明六端通过。
- 渲染：宿主 Chromium 提供了真实 `readyState`/`currentTime`/分辨率，不是仅控制面证据；GPU 豁免不适用于本轮，因为真实解码已发生。
- 当前服务产物不含 AppSettings legacy-local 兼容修复；本轮固定本地网络配置并拦截 `**/api/config` 仅作为测试前置，**不构成对该配置修复的运行时验证**。
- 无备用项暂停失败仅覆盖“成员真实退出”路径；服务端崩溃、网络中断等其他 source_offline 路径不在本轮范围。

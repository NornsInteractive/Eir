# 反向供片与离房回退 — 真实双浏览器窄验收（REVERSE-SOURCE-ACCEPTANCE）

- 执行角色：已核实免费 CodeBuddy `deepseek-v4.1-flash`（本机 `product.json` 标注 `x0.00 credits`，无付费回退）。
- 执行时间：2026-11-18 19:30 – 19:58（20 分钟窄任务，含 harness 校正）。
- 性质：只测试。**未改产品/UI/服务端源码，未构建/安装/打包/发布，未清数据，未改图形设置。**
- 服务：复用 Agy 常驻 `http://127.0.0.1:8080/`；未停止、未重启、未改端口。
- 证据目录：`/tmp/eir-acceptance-current/`
  - `reversesource.js` / `reversesource.json` / `reversesource-wire.json`
  - 截图：`evidence/shots/reversesource-A-guest-local.png`、`reversesource-B-guest-local.png`、`reversesource-A-fallback.png`

## 被测指纹（先核对，未通过则不测）

| 项 | 实测 | 结论 |
|---|---|---|
| `build/web/main.dart.js` SHA-256 | `cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928` | 与指定指纹**一致** |
| `version.json` | `{"version":"1.0.40","build_number":"41"}` | 当前 Agy 产物 |
| 服务 | `http://127.0.0.1:8080/` 返回 200 | Agy 常驻服务 |

**重要边界：该产物不包含新的“本地信令兼容修复”。** 本轮仅通过测试注入（`localStorage` 权威网络记录 + `context.route('**/api/config')` 中止远程配置）把会话固定到 `ws://127.0.0.1:8080/ws`，属于 **harness 预设**，**不能**声明产品侧本地信令兼容修复已运行或已验证。若后续修复需要产品自身接受本地端点，必须重建后另行复测。

## 测试条件

- Playwright `1.65.0`（`/tmp/eir-browser-tools/node_modules/playwright`），Chromium `chromium-1254`，headed + Xvfb。
- 两个**独立、一次性** context（A=owner，B=guest），各自独立房间身份；互不共享存储。
- 固定信令 `ws://127.0.0.1:8080/ws`，权威网络记录写入 `flutter.eir_setting_*`，`/api/config` 全部 abort。
- 媒体：guest 供片 `/tmp/eir-media-fixture.mp4`（H.264/AAC，20s），owner 备用 `/tmp/eir-business/short-a.mp4`（4s）。二者为**不同文件**，避免同 mediaId 去重掩盖来源切换。
- Range 能力：另起临时 loopback 媒体服务验证 `Range: bytes=0-99` 返回 **206 / 100 bytes**；最终通过场景全部使用本地 P2P 媒体，未使用 URL 片源，因此不存在“无 Range 导致 seek/重启”的假失败。

## 结果（全部来自真实 UI 与真实 `<video>`）

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| 1 | 建房 / 6 位码加入；A owner、B member | PASS | `setup`，code=783265 |
| 2 | 真实 Grant Admin：点击**最小 88×30 动作按钮**，非 1216×66 成员行 | PASS | `grant-candidates` 两项；`grant-click` 88×30 |
| 3 | 授予后 B 显示 ADMIN，具备供片入口 | PASS | `post-grant` B admin=true member=false |
| 4 | guest 本地供片成功，双方播放列表 1 项 | PASS | `guest-add-local` B=1 A=1 |
| 5 | owner 选中 guest 片源并真实解码、位置推进 | **PASS** | `owner-guest-local-decode`：`src=/eir-media/cc7aa159…`、`dur=20`、`rs=4`、`paused=false`、`ct 0.01 → 2.45`、`err=null`、`w=320 h=240` |
| 6 | 当前项确为 guest 片源 | PASS | `owner-current-guest-item`：`Playlist (1)`、`eir-media-fixture.mp4 NOW PLAYING` |
| 7 | owner 加入自己的备用片源后，当前项仍为 guest 片源 | PASS | `owner-add-fallback`：playlist=2，currentStillGuest=true |
| 8 | guest 当前片源播放中离房；B 回到大厅 | PASS | `guest-left` B=lobby |
| 9 | 普通 member 退出**不产生** `owner_changed`，A 仍 owner | PASS | `no-owner-change-for-member-exit`：`owner_changed=[]`、`disbanded=0` |
| 10 | owner 按当前规则转备用片源：0 起播、真实解码并推进 | **PASS** | `owner-fallback`：src 切换为 `blob:…04e533f2…`（short-a，`dur=4`）、`rs=4`、`paused=false`、`err=null`、`ct 2.63 → 4`；A 仍 owner，playlist=2 |

关键对比：guest 源为 `/eir-media/<mediaId>`（Web 媒体服务），owner 备用源为 `blob:`；`src` 发生切换，且 `duration` 从 20s 变为 4s，可确认不是同一条目继续播放，而是按规则切换到了备用片源。

## 未测 / 不计为通过

- **暂停分支未触发**：本轮有可播放备用片源，owner 走“转备用片源”分支；无备用片源时的 `pause(positionMs:0)` 分支未单独构造。
- **URL 片源链路未计入**：临时 Range 服务已实测 206，但产品 UI 的 `Add Online URL` 在本 harness 下（输入值已进入 URL 输入框、Confirm 已点击）播放列表仍为 0，未成功添加；该现象未隔离为产品缺陷，也未作为通过证据。`Add Media` 在空列表时不存在，入口为 `Add Online URL` / `Add Local Video`，与既有脚本的 `Add Media` 假设不同。
- seek / next / 倍速 / 双端同步控制、A15/A16 重连、原生 Android/iOS、服务端重启、弱网均**未测**。
- 图形豁免沿用既有记录；本轮未改图形设置，不作为渲染修复证据。

## 发现与处理

- 本轮**未发现需要上报的产品业务缺陷**。此前 `owner-guest-local-decode FAIL` 已定位为 **harness 断言错误**：guest 供片在 Web 上由同源 `/eir-media/<mediaId>` 提供，并非 `blob:`；断言只接受 `blob:` 导致误判。修正为接受 `/eir-media/` 后，同一真实场景稳定 PASS。
- 未修改任何源码、UI、服务端、测试基线。

## 资源清理

- 临时 Range 媒体服务与诊断脚本已停止/删除；未删除 `/tmp/eir-acceptance-current` 既有 `grantprobe*` / `rejoinloop*` 等用户脚本与证据。
- 未清理浏览器/设备用户数据；未触碰 8080 服务与 Agy 进程；未新增端口转发。

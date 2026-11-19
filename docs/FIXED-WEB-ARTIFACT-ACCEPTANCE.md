# 最终 Web / 产物验收（FIXED-WEB-ARTIFACT-ACCEPTANCE）

- **执行时间**：2026-11-18 20:50 – 21:20 +08:00（60 分钟窗口内）
- **执行角色**：已核实全 0 费用的 `opencode/deepseek-v4.1-flash-free`；无付费回退。Norns 由 Root 报告已检查，本轮未重新连接、未发布。
- **性质**：只测试/写报告/最小 harness 适配。**未修改产品源码、UI、服务端、测试断言；未 formatter；未安装新工具；未构建/安装/打包/发布；未清设备或浏览器用户数据；未停止或改动常驻 8080 服务。**
- **ADB 约束**：同设备被其他项目占用，按指令**未执行任何 ADB UI 操作**，未抢占设备、未停止他人应用；Android 仅做 APK 静态检查。
- **证据目录**：`/tmp/eir-final-acceptance-2026-11-18/`（`raw/*.json|log`、`shots/*.png`、四个 harness 脚本）。报告中的数字均来自该目录原始记录。

## 一、被测产物指纹（先核对，哈希命中后才测）

| 项 | 实测 | 结论 |
|---|---|---|
| Web 常驻入口 | `http://127.0.0.1:8080/` 返回 200；`/ws` 信令同端口 | 复用既有服务，未重启 |
| 服务端提供的 `main.dart.js` | `e81574b5add2185eb76b6f571b2eda6bda84b6e7f0bc48cb831f9ed8f12135fb` | 与报告完整正确值一致 |
| 磁盘 `build/web/main.dart.js` | 同上（`e81574…135fb`） | 服务内容 = 磁盘产物 |
| `eir_media_bridge.js` | `41556baaa3bc377311153c1b3219693d6444bda9739c2c15ec4a36eff9691401` | 磁盘/服务一致 |
| `eir_media_sw.js` | `5124142fc6492d7f5a03d094ff5b5e52697ea483663075e6d1873bde9d50ce23` | 磁盘/服务一致 |
| `version.json` | `{"app_name":"eir","version":"1.0.40","build_number":"41","package_name":"eir"}` | 1.0.40+41 |
| APK | `eir-v1.0.40.apk`，183,345,864 B，SHA-256 `e4563c9b6525f51d0ca655ec46abedb4d23c168cfae9b0f657c94b243901b8a5` | 与指定哈希一致 |
| 本地 APK 数量 | 仅 `eir-v1.0.40.apk` 一份 | 符合单份产物规则 |

> 任务提示行中的 `e815…f12135fb` 为截断/误写值；本轮以环境报告完整值 `e81574b5add2185eb76b6f571b2eda6bda84b6e7f0bc48cb831f9ed8f12135fb` 为准，且实际测得完全一致。仅靠 1.0.40+41 不作为通过依据。

## 二、结论总表

| # | 验收项 | 结论 | 关键依据 |
|---|---|---|---|
| 1 | 当前 Web 双端相对 seek（Range 60s 源，播放 >15s 后正向/负向） | **PASS** | 正向 +10.064s/+10.046s，负向 -10.071s/-10.071s，双端 Δ≤0.006s |
| 2 | 旧标量本地信令、无权威 record 的启动/重载保留 + Settings 真实值 | **PASS** | 标量保持 `ws://127.0.0.1:8080/ws`，record 始终为 null，Settings 输入框与 Profile 行均为本地地址 |
| 3 | 新成员语义唯一真实 Grant Admin、角色更新、同身份重入、设置不重建房间 | **PASS** | 唯一 88×30 动作按钮；成员行 ADMIN；2 轮重入同 deviceId/epoch/rejoined/Playlist(1)；设置切换后 join 帧 1→1、房间码不变 |
| 4 | 无备用且无完整可播缓存时，供片成员离线按既有规则暂停/清理 | **FAIL（真实产品缺陷）** | 120s 源仅缓冲 15.93s；成员离开后 owner 继续播放 7s，`paused=false`，无离线覆盖层 |
| S | APK/Web 静态产物校验（哈希/包名/ABI/TailcatFree/ZFlip7/页对齐） | **PASS + 1 项静态风险** | APK 指纹、双 ABI `TailcatFree`、ZFlip7 guard、zipalign 16K 通过；`libtailcat.so` ELF 页对齐存在 16KB 风险 |
| O | 真实 UI 通话/投屏/getStats | **NOT TESTED** | 见第八节；未用 mock 冒充真实轨道统计 |

## 三、第 1 项：当前 Web 双端相对 seek — PASS

方式：两个独立 Playwright Chromium context（A owner / B member），独立新房；`**/api/config` 上下文级 abort；本地信令固定 `127.0.0.1:8080`。媒体由进程内临时服务器提供 `http://127.0.0.1:8098/eir_long.mp4`（60s，**实测支持 `Range` 返回 206**，与旧 `serve_eir.py` 返回 200 全量的环境不同）。**全程未先暂停、未更新提交锚点**，直接按 `ArrowRight` / `ArrowLeft`。

| 阶段 | A 当前时间 | B 当前时间 | 结果 |
|---|---|---|---|
| 播放超过 15s（前测） | 15.455s | 15.467s | 均 `paused=false`、`readyState=4`、`duration=60` |
| 按 `ArrowRight` 后 | 25.519s | 25.513s | **+10.064s / +10.046s**，双端差 0.006s，未回退 |
| 继续播放到 26.862s / 26.860s 后按 `ArrowLeft` | 16.791s | 16.789s | **-10.071s / -10.071s**，双端差 0.002s，未回 0 |

结论：相对 seek 以**实时播放位置**为基准，正向不再落到旧锚点+10（10.0s），负向也未回零；与 `lib/core/room_session.dart` 的 `seekRelative` 实现一致。首次旧环境（无 Range）会被误判为重启 0，本轮不使用该环境。

证据：`raw/seek.json`、`raw/seek.log`、`shots/seek-before-{A,B}.png`、`shots/seek-forward-after-{A,B}.png`、`shots/seek-backward-after-{A,B}.png`、脚本 `seek.js`。

## 四、第 2 项：旧标量本地信令（无权威 record）启动/重载保留 — PASS

方式：上下文只写入旧标量偏好 `flutter.eir_setting_signaling_url = "ws://127.0.0.1:8080/ws"`；**不预置** `eir_setting_network_config`（无权威 record），并 abort `**/api/config`，避免远程配置覆盖。标量只在**首次导航注入一次**（用 `sessionStorage` 标记），真实 reload 时不再执行 `localStorage.clear()`/重写，避免把“重新注入”误当成“持久化保留”。

| 检查 | 实测 |
|---|---|
| 首次启动存储 | 标量 `"ws://127.0.0.1:8080/ws"`；`eir_setting_network_config = null` |
| 首次 Settings → Network & Relay 中 Signaling 输入框 | `ws://127.0.0.1:8080/ws`（非生产 `wss://eir.norns.cc.cd/ws`） |
| 打开/关闭设置后存储 | 标量不变；record 仍为 null |
| 真实 reload 后存储 | 标量仍为 `"ws://127.0.0.1:8080/ws"`；record 仍为 null |
| reload 后 Profile「Network & Signaling」行 | `ws://127.0.0.1:8080/ws` |
| reload 后 Settings 输入框 | `ws://127.0.0.1:8080/ws` |

结论：无权威记录时，旧标量在启动与刷新后均被保留，未被静默迁移为生产地址；Settings 展示的是真实保存值。本项是本轮**唯一**允许把本地信令作为产品行为证据的场景；其余场景的本地地址仍只是 harness 前置。

证据：`raw/settings.json`、`raw/settings.log`、`raw/settings-discovery.json`、`shots/settings-startup.png`、`shots/settings-reload.png`、`shots/settings-profile-reload.png`、脚本 `settings.js`。

## 五、第 3 项：Grant Admin / 同身份重入 / 设置不重建房间 — PASS

| 子项 | 实测 |
|---|---|
| 唯一真实 Grant Admin 动作 | `role=button` 中匹配 `Grant Admin` 的节点 **仅 1 个**：`88×30`、area 2644、文本 `Grant Admin: <成员名>`；成员行不再作为第二个按钮暴露 |
| 点击后角色更新 | 点击该 88×30 按钮后，A 侧成员行与 B 侧角色均显示 `ADMIN`（B 不再显示 `MEMBER`），B 出现 `Add Local Video` / `Add Online URL` |
| 设置不重建房间 | 在 B 侧打开 Preferences，切换 简体中文 → English、Dark → Light → System 后关闭；B 仍为 `member+ADMIN`、房间码 `578468` 不变；A 仍为 `owner`；B 的 `join_room` 发送帧数 **1 → 1**，无新进房/建房 |
| 同身份重入（2 轮） | 每轮真实 `Leave Room` + 确认后回大厅，再用同一 6 位码 `Quick Join`；`rejoined=true`、`inviteEpoch=1`、重入前后 `deviceId` 完全相同、无 `error`、无 `disbanded`、A 始终 owner；重入后 `Playlist (1)` 恢复 |
| 播放列表快照 | 重入 2 轮均恢复为 1 项（guest/房间快照链路） |

结论：成员语义修复后，Grant Admin 只剩真实动作按钮；角色更新、同身份幂等重入与设置切换均正常，设置未重建房间/未改变身份。

证据：`raw/grant-rejoin-settings.json`、`raw/grant-rejoin-settings.log`、`shots/grant-settings-A.png`、`shots/grant-settings-B.png`、`shots/rejoin-B.png`、脚本 `grant-rejoin-settings.js`。

## 六、第 4 项：无备用 + 无完整缓存时供片成员离线 — **FAIL（真实业务缺陷）**

为避免把“完整可播缓存仍可继续播放”误判为缺陷，本轮刻意使用 **120s / 65MB** 的成员本地文件，并在播放约 1.3s 时让供片成员退出；离开前实测：

- A 真实 `<video>`：`src=/eir-media/037f…/7569…`（guest 本地源）、`duration=120`、`currentTime=1.33`、`readyState=4`、`paused=false`；
- 缓冲范围仅 `[0, 15.93]`（**有界部分缓存，不是完整 120s 可播缓存**），故不能把后续继续播放解释为完整缓存兜底；
- 播放列表仅此 1 项，无备用项。

真实退出与观察：

- B 点击 `Leave Room` → 确认 `Leave` → 回大厅；A 收到真实信令 `member_left`；`owner_changed` 0 条、`disbanded` 0 条，A 仍 owner。
- 离开后 1–7 秒连续采样，A 的播放器：`1.33 → 6.06 → 7.11 → 8.09 → 9.10 → 10.11 → 11.14 → 12.13`，全程 `paused=false`、`readyState=4`；`Provider left` 徽标 **false**、`Media Source Offline` 覆盖层 **false**。
- 即：供片成员已离线、无备用项、缓存不完整，owner 仍未暂停、未清理、未显示离线状态，只是继续消耗已缓冲的约 16s，随后会在缓冲末端停住。按既有“无下一可播项则暂停/清理”规则，这是**真实业务缺陷**，不是 harness、缓存或渲染误判。

静态根因（只读定位，未修改）：

- `lib/core/room_session.dart:1780-1787` 在 `_handleMemberLeft` 无备用项时发布 `action:'pause'`，params 仅 `{'positionMs': 0}`，缺少 `itemId`；
- `lib/core/room_session.dart:3238-3247` 的 `_validateActionParams` 对 `play/pause` 强制要求非空 `itemId`，该 commit 在本地校验即被 `commit_rejected`，既不发送也不本地应用；
- 有备用项时走 `switch_item`（params 带 `itemId`）可通过，与本轮之前“备用切换已过”的记录一致。

处理建议（交 Agy / 业务责任方，本轮未改）：为该 pause 补当前 `itemId`（并在无当前项时按规则清理），重建 Web/APK 后用同一“无备用 + 非完整缓存”场景复测；不要用完整缓存或 mock 状态掩盖。

证据：`raw/source-offline.json`、`raw/source-offline.log`、`shots/source-offline-before-A.png`、`shots/source-offline-after-A.png`、`shots/source-offline-after-B.png`、脚本 `source-offline.js`。

## 七、静态产物校验（APK / Web / 原生对齐）

### 1. APK 身份与打包

| 检查 | 实测 |
|---|---|
| SHA-256 | `e4563c9b6525f51d0ca655ec46abedb4d23c168cfae9b0f657c94b243901b8a5`（命中） |
| 包名 / 版本 | `com.norns.eir`，`versionName=1.0.40`，`versionCode=41` |
| SDK | `minSdk=24`，`targetSdk=36`，`compileSdk=36` |
| `extractNativeLibs` | `false` |
| zipalign 16KB 检查 | `zipalign -c -P 16 -v 4 eir-v1.0.40.apk` → **Verification successful** |
| ZFlip7 启动兼容 guard | 复用 `tool/android_debug_apk.sh verify eir-v1.0.40.apk` → **OK**（arm64-v8a / armeabi-v7a 均含 `libflutter.so`，且非 integration_test 入口） |

### 2. ABI 与 TailcatFree

| ABI | libapp.so | libflutter.so | libtailcat.so | `TailcatFree` 导出 |
|---|---|---|---|---|
| arm64-v8a | 有 | 有 | 有 | **有**（`nm -D`） |
| x86_64 | 有 | 有 | 有 | **有**（`nm -D`） |
| armeabi-v7a | 有 | 有 | **无** | 不适用（该 ABI 未打包 Tailcat 库） |

- “两个 ABI 的 TailcatFree”指 `arm64-v8a` + `x86_64`，均已核实；`armeabi-v7a` 仅有 Flutter 引擎/应用库，32 位设备不会加载 Tailcat 原生库（属现状，不冒充为 Tailcat 可用）。
- `jniLibs` 源库与 APK 内库 SHA-256 不同，是 Gradle 打包剥离调试符号所致；两者 `nm -D` 的 `TailcatFree` 符号偏移一致（arm64 `0xfa3544`、x86_64 `0x10fef80`），不是 ABI 契约不一致。
- `native/tailcat/libtailcat.h:102` 已声明 `extern void TailcatFree(void* ptr);`。

### 3. 需报告给 Agy 的静态风险（未自行修改）

- `lib/arm64-v8a/libtailcat.so` 的 ELF `LOAD` 段 `p_align=0x1000`（4KB），而 `libapp.so`/`libflutter.so` 为 `0x10000`。APK 的 zip 对齐已通过 16KB 校验，但该原生库自身的 ELF 段对齐不是 16KB。若目标设备启用 16KB 页（Android 15+ 部分设备），存在 `dlopen` 失败风险。建议由 Agy 用现有 NDK 重建 Tailcat 原生库时开启 16KB 页对齐（不改打包配置的前提下确认工具链参数），并在真机验证；本轮未修改。
- 该风险不影响本轮 Web 验收与 ZFlip7 既有 guard 的静态结论，但不能据此宣称 16KB 页设备运行时已通过。

### 4. Web 产物

`build/web` 与 8080 实际服务的 `main.dart.js` / `eir_media_bridge.js` / `eir_media_sw.js` / `version.json` 哈希逐一相同（见第一节与 `raw/web-hashes.txt`），1.0.40+41，不存在“服务旧 JS、磁盘新 JS”的错配。

## 八、未测 / 阻塞（明确不记为通过）

1. **Android 运行时与 ADB UI：未测。** 因同设备被其他项目占用，按本轮协调任务限制等待独占窗口，本轮未抢设备、未停止他人应用、未执行安装/启动/点按/通话等 ADB UI 操作；仅静态检查 APK。
2. **真实 UI 通话（呼叫/接听/连接/挂断/重拨）与投屏（start/stop/真实 getStats/No data）：未测。** 在完成 1–4 与静态校验后未继续，避免超出 60 分钟窗口；未使用 mock 数据冒充真实 `RTCPeerConnection` 轨道统计，未添加不安全 origin 实验标志。若后续执行，需以真实音视频轨道的 `getStats` 数值为证据。
3. **物理硬件/真机渲染：未测。** 无三星 Z Flip7 真机；模拟器图形豁免沿用既有记录，本轮未改图形设置，不把豁免当修复。
4. **生产信令/远程延迟/弱网/服务端重启：未测。** 本轮固定本机 8080/ws 并拦截 `**/api/config`，结论仅适用于该本地验收环境。
5. **完整缓存场景：未作为本轮缺陷依据。** 第 4 项已用 120s 源、仅 15.93s 缓冲证明“非完整缓存”；未把完整缓存继续播放误判为失败。

## 九、环境保持与清理

- 未停止/重启 8080 常驻服务；未改动 `server/`、`build/web/`、日志、用户数据、浏览器用户数据、ADB forward/reverse、图形设置。
- 未修改仓库内产品/UI/测试/断言；本轮只新增本报告。
- 临时 Range 媒体服务为进程内创建，脚本结束即关闭；已确认 8098/8099 无残留监听。临时 Playwright Chromium 均已关闭。
- 全部新增脚本/JSON/日志/截图仅保存在 `/tmp/eir-final-acceptance-2026-11-18/`；未删除既有 `/tmp/eir-acceptance-*` 证据或夹具。

## 十、最终判定

- **当前 Web 8080 产物（1.0.40+41，`main.dart.js` `e81574…135fb`）与 APK `eir-v1.0.40.apk`（`e456…b8a5`）已通过身份核对；版本号未作为唯一依据。**
- **相对 seek、旧标量本地信令持久化、Grant Admin/同身份重入/设置不重建房间：PASS。**
- **无备用且无完整缓存时供片成员离线：FAIL，真实业务缺陷，根因已在源码定位，需责任方修复并重建后复测。**
- **静态包结构与 ZFlip7 既有 guard：通过；另发现 Tailcat arm64 原生库 ELF 16KB 页对齐风险，已报告，未自行修改打包配置。**
- 未执行真实 Android UI、通话与投屏；未用 mock/合成状态冒充真实轨道统计证据。

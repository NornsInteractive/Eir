# MVP 核心验收映射（A01–A18 + 安全/重连/自然结束/列表替换/源离线）

> 复核 2026-11-07，CodeBuddy `deepseek-v4.1-flash`（免费，无付费回退，无发布）。
> 本表区分「运行证据」与「仅源码实现」。**源码存在 ≠ 运行通过**。
> F1–F5 本轮已实现并以真实 Linux 集成/单元测试验证（见下）。

## 图例
- ✅ 运行验证通过（附测试/命令）
- ◐ 源码已实现；该场景缺专门运行验证，或仅部分测试
- ✗ 缺口
- ⏳ 平台/网络未验证

## 证据基线（本轮实际运行）
- 单元/组件：`flutter test test/core` → **85/85**（原 74 + 新增 `url_probe_test` 11 项 HLS/URL 边界）。
- Linux 真实双客户端（本轮新增）：`integration_test/room_session_core_fixes_test.dart` → **4/4**
  - F1 异步播放器错误上报与切换清除；
  - F3 同一信令 URL 停服再起的 epoch 旋转与旧邀请失效；
  - F4 `retry()` 同 URL 恢复；
  - 晚加入 / 替换当前项 / 自然结束自动下一条。
- Linux 回归：`room_session_url_test` **2/2**、`room_session_local_media_test` **2/2**、
  `room_session_streaming_proof_test` **1/1**（65 MiB 未传完即播）。
- Linux 边界（本轮新增）：`integration_test/room_session_edge_test.dart` → **3/3**
  - A13a 供片端 `dispose` 后成员缓存续播、房间状态不被 DC 关闭重置；
  - A13b 65 MiB 仅缓存前缀时供片端退出 → `source_offline`/`media_probe_failed` 或停顿等待，无假接力；
  - A14 房主/控制通道断开 → 成员（已授管理员）无新提交、不自行推进自然结束、同 URL `retry()` 有界显式失败。
  - 故障注入为真实 `dispose()`（切断真实 DC 与媒体服务），未强改任何业务字段。
- Linux W3 回归（本轮新增）：`integration_test/room_session_reconnect_exhaustion_test.dart` → **1/1**
  - 同 URL 非 disband 停服 → 3 次有界自动重试（1.1/2.1/4.2 s）耗尽后 `disconnected` +
    `signaling_unavailable`；同 URL 端点恢复后**不自动恢复**；`retry()` 同 URL 恢复，
    房间/身份/播放列表/播放状态/存活 DC 保留，邀请 epoch 旋转，错误码清除。
  - 修复后回归：`room_session_core_fixes_test` **4/4**、`room_session_edge_test` **3/3** 重跑通过。
- Android（主构建轮）：`room_session_url_test` **2/2**、`room_session_local_media_test` **1/1**。
- 静态：`flutter analyze lib/core lib/platform server` + 新测试 → **No issues found**。
- Norns MCP（`/home/dev/.codex/config.toml` → `mcp_servers.norns`）：initialize **200**、
  tools/list **200**、**41** 工具（UA `Codex-MCP/1.0`，协议 `2024-11-05`）；未打印凭据，无发布。

## 功能验收 A01–A18

| 编号 | 要求（简） | 实现定位 | 运行证据 | 结论 |
|---|---|---|---|---|
| A01 | 创建/邀请/加入；第三身份拒绝 | `server/signaling_server.dart`；`room_session.dart` `createRoom/joinRoom` | `signaling_server_test`；`url_test` | ✅ |
| A02 | 邀请重试幂等；他人不可复用 | 服务端邀请代次/消费；同身份幂等重入 | `signaling_server_test`；`commit_log_test` requestId 去重 | ✅ |
| A03 | 管理员增/撤；撤销后拒绝 | `_applyCommitSideEffects`；`RoomAcl` | `commit_log_test`；`url_test` grant→revoke→denied | ✅ |
| A04 | 成员发控制被拒、状态不变 | `_handleControlRequest` `permission_denied` | `url_test`：member `pause()`→`permission_denied` 且 seq 不变 | ✅ |
| A05 | HTTPS MP4/HLS 点播 | `addUrl`+`url_probe_io.dart`；`_mediaForItemAsync`→`Media(url)` | `url_test` 用 loopback HTTP `sample.mp4`；HLS VOD 实际播放未跑 | ◐ HTTPS/HLS 播放未验证 |
| A06 | 过期/网页/直播/DRM 拒绝 | `url_probe_io.dart`：HTTP 非 2xx→`media_probe_failed`；HTML→`unsupported_media`；HLS 分类（`classifyHlsPlaylist`）识别 VOD/master/live/DRM | `url_probe_test` 11 项：live/DRM(AES-128/SAMPLE-AES)/非 http 变体/master 深度均拒绝，VOD 允许 | ✅ 拒绝逻辑（单元） |
| A07 | 本地兼容文件，未收完即播 | `lib/media/**` + `addLocalFile` + `media_manifest_chunk` | `streaming_proof`（65 MiB，`manifestBytesSent>0`，播过 1 s 时 sent<file）；`local_media` Linux 2/2、Android 1/1 | ✅ Linux/Android |
| A08 | 不兼容/损坏/长 GOP：不转码、报错 | 无转码；`_onPlayerError` 订阅 `player.stream.error`→`media_probe_failed`；`_errorItemId` 防过期媒体污染 | `core_fixes_test` F1：损坏媒体→`media_probe_failed`，切回合法项后清空 | ✅ 异步错误已上报 |
| A09 | 播放/暂停/seek/倍速同序列、重复不重放 | 提交链 + requestId 去重 | `url_test` play/seek/rate；`commit_log_test` 去重 | ✅ |
| A10 | 列表并发/删除/替换当前项 | `remove` 选前 NEXT+暂停+保载；`replace` 位置 0+暂停+重载 | `url_test` 并发；`core_fixes_test` 替换当前项两端同步 | ✅ 并发+替换当前项 |
| A11 | 自然结束/列表末尾：房主唯一提交下一条 | `_onPlayerCompleted`→下一条 `switch_item`，否则 `ended_stop` | `core_fixes_test`：1.6 s 片段播完→房主自动切下一条，成员跟随 | ✅ |
| A12 | 晚加入/个人缓冲追赶 | 快照（含 playlist/current/playback/inviteEpoch）+ `_ensureMediaLoaded(seekTo)`；握手后双方 `_requestResync(force)` | `core_fixes_test`：房主先加项，成员后加入→收到完整 playlist | ✅ 晚加入 |
| A13 | 原源退出：缓存可播、缺片等待 | 媒体 `source_offline`；缓存优先；`_mediaForItemAsync`；DC 关闭仅置 `peerVerified=false` 不重置房间 | `edge_test` A13a/A13b：真实 `dispose` 供片端；已缓存部分继续推进，缺块时 `source_offline`/`media_probe_failed` 或停顿，末位置 <60 s | ✅ 运行（Linux 双端） |
| A14 | 房主离线/恢复：续播、禁新控与自动下一条 | 自动下一条仅 owner；控制需 owner 提交；`retry()` 有界失败 | `edge_test` A14：房主 `dispose` 后成员 `seek` 不产生新 seq、自然结束不自动切换、同 URL 重启 + `retry()` 以 `room_not_found`/`signaling_unavailable`/`invalid_invite` 显式失败 | ✅ 运行（有界失败分支） |
| A15 | 信令断开/重启：原连接续、房主重登记 | `stop(graceful:false)` 模拟崩溃（不广播 disband）；`_scheduleReconnect`+`_registerWithSignaling`；重启后旋转 epoch 并重签邀请 | `core_fixes_test` F3：**同一 URL** 停服再起，不改地址/不重建房间，3 次有界重试内恢复、DC 存活、旧邀请被拒、新邀请可加入；`reconnect_exhaustion_test`：耗尽→`disconnected`，手动 `retry()` 同 URL 恢复 | ✅ 同 URL 重启（有界 + 手动恢复） |
| A16 | P2P 故障/休眠/切换：有界重试、可手动重试 | 自动 1.1/2.1/4.2 s×3 后进入 `disconnected` 终态，不再无限重试；公共 `retry()` 复用同流程，保留房间/身份/播放状态，失败仍回 `disconnected` | `core_fixes_test` F4：同 URL 停服再起后 `retry()` 恢复、DC 存活、无残留错误；`reconnect_exhaustion_test`：耗尽终态 + 端点恢复后不自动恢复 + `retry()` 实际恢复 | ✅ |
| A17 | 空间不足/清理缓存：不毁源、不删在用 | `clearUnprotectedCache()`；`onStorageError`→`storage_full`；清理成功后清 `storage_full` | 媒体 `cache_clear_test`/`cache_test`（保护在用，ENOSPC 故障注入）；核心映射+清理接线经 analyze；核心未注入真实 ENOSPC | ✅ 接线（媒体单元） |
| A18 | 可访问性：键盘/焦点/只读区分 | `lib/views/**` Semantics | `test/ui`+`widget_test` **8/8**（构建轮） | ✅ UI 隔离级 |

## 安全与协议检查（V1-ACCEPTANCE §4）

| 检查 | 实现/测试证据 | 结论 |
|---|---|---|
| 伪造签名 / 公钥替换 | `protocol_test`；`identity_test` | ✅ |
| 伪造接纳 / ACL 越权 | `commit_log_test` RoomAcl；`url_test` 成员控制拒绝 | ✅ |
| 随机挑战重用 / DTLS 指纹不匹配 | `url_test` 双向 `peerVerified`；缺指纹→`handshake_failed` | ✅（Linux/Android 真机） |
| 跨房/跨会话重放 | `signaling_server_test` 跨房隔离；`protocol_scope_test` 媒体门禁 | ✅ |
| 撤销权限即时生效 | `commit_log_test` receiver-enforced；`url_test` revoke→denied | ✅ |
| 重复提交/乱序/缺号 | `commit_log_test` duplicate/park/drain；requestId 去重 | ✅ |
| 快照倒退/同序冲突 | `commit_log_test` `resetTo`/`classify` | ✅ |
| 清单替换/坏片/越界块/重叠 | `test/media` manifest/range/cache/frames/transfer | ✅（媒体单元） |
| 超大消息 / 请求洪泛 | `kMaxEnvelopeBytes` 先于 jsonDecode；`signaling_server_test` 超大帧/限流 | ✅ |
| loopback 仅本机/令牌/无目录遍历 | `test/media/range_test`；SW 令牌/双窗口隔离 | ✅（媒体单元/浏览器探针） |
| HLS SSRF / 无限递归 | `classifyHlsPlaylist` 仅跟随 http(s) 变体、master 深度≤1、非 http 变体拒绝 | ✅（单元） |

## 专项：重连 / 自然结束 / 列表替换 / 源离线

| 专项 | 实现 | 证据 | 结论 |
|---|---|---|---|
| 重连（同 URL 重启） | `stop(graceful:false)`+`_registerWithSignaling`+epoch 旋转 | `core_fixes_test` F3/F4 | ✅ |
| 自动重试耗尽（W3） | 3 次后 `_reconnectExhausted`+`disconnected`，回调/定时器不再重启；`retry()` 清除终态 | `reconnect_exhaustion_test`：端点恢复后不自动恢复，手动 `retry()` 恢复 | ✅ |
| 自然结束 | `_onPlayerCompleted`→下一条/`ended_stop` | `core_fixes_test` 自动下一条+成员跟随 | ✅ |
| 列表替换当前项 | `replace`：位置 0、暂停、重载 | `core_fixes_test` 两端 URL 同步 | ✅ |
| 源离线 | 媒体 `source_offline`；缓存优先；缺片等待/超时 | `edge_test` A13a/A13b（供片端真实退出；缓存续播、缺块显式失败或停顿） | ✅ |
| 房主离线 | DC 关闭不重置；成员无权威、不推进自然结束；`retry()` 有界失败 | `edge_test` A14 | ✅ 有界失败分支 |
| 手动重试 | `retry()`（复用重连、去重、保状态） | `core_fixes_test` F4；API 文档 `/tmp/eir-core-retry-ui-api.txt` | ✅ |
| 存储不足 | `onStorageError`→`storage_full`；清理后清除 | 媒体 ENOSPC 单元；核心接线 analyze | ✅ 接线（未注入核心运行时） |

## 明确未验证（不得宣称通过）

| 项 | 状态 |
|---|---|
| HLS **VOD 实际播放** | ⏳ 分类器已单测（VOD 允许），但未用真实 HLS 流跑播放 |
| 直播 / DRM 真实样本 | ⏳ 仅分类器单测拒绝，未用真实流 |
| 性能口径（状态≤3s、连接≤5s、操作≤1s、稳态 P95≤150ms、CPU/内存） | ⏳ 未测量 |
| 跨真实异地网络（不同家宽/移动热点/受限网络/RTT/丢包） | ⏳ 未测量 |
| Windows 运行 | ⏳ Release 构建通过，但宿主机缺 `OPENGL32.dll`（Server Core）无法运行 |
| macOS 运行 | ⏳ 用户暂缓，未测 |
| iOS 运行 | ⏳ 无 macOS/Xcode 主机，未测 |
| Web 产品双端 E2E | ⏳ Web 工作轮进行中；Web 探测受 CORS 限制，仅 scheme 校验，播放失败经播放器错误可见 |
| 房主**返回后**权威重对齐（A14 恢复分支） | ⏳ 仅验证断开期间的有界失败；房主重新登记后的重对齐由 F3 信令层覆盖，未在同一场景端到端重跑 |
| 供片端退出后**重新加入/恢复供片** | ⏳ 仅验证退出时的缓存续播与缺块失败，未验证重新供片 |
| TURN 兜底 / 对称 NAT | ⏳ 无 TURN，按 v1 范围不承诺 |

## 结论
- **核心双端 happy path 与异常生命周期（F1 异步错误、F3 同 URL 重启、F4 手动重试、A11 自然结束、A12 晚加入、A10 替换当前项、A13 供片端中途退出、A14 房主离线、W3 重连耗尽终态）在 Linux 有真实运行证据；Android 由主构建轮验证 URL/local。**
- A16 的自动重连是有界终态：耗尽后 `disconnected` 且不再自动重试（修复前 Web 观测 44 s 仍 `reconnecting` 且端点恢复后自动复活），手动 `retry()` 复用同流程并在同 URL 实际恢复。
- A13/A14 的故障注入均为真实 `dispose()` 切断真实 DataChannel 与媒体服务，未注入伪造业务状态；A14 只覆盖「有界显式失败 + 可手动重试」分支，房主返回后的重对齐仍未端到端验证。
- 本地大文件「未传完即播」在 Linux 65 MiB 有硬证据。
- F1–F5 已实现；F1/F2/F3/F4 有运行证据，F5 为媒体单元+核心接线（未注入核心运行时 ENOSPC）。
- 平台运行（Windows/macOS/iOS/Web 产品 E2E）与性能/跨网、HLS VOD 实际播放、供片端重新供片仍未验证，不得标通过。

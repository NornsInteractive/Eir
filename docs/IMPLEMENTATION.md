# 实施进度

本文保留早期实施过程。当前分工与验收进展以 [MVP 执行记录](MVP-EXECUTION.md)、[构建与平台状态](MVP-BUILD-STATUS.md) 和 [Web 产品验收](MVP-WEB-VALIDATION.md) 为准；下文的早期阻塞、测试数量和工具分工不是当前结论。

## 已确认约束

- 用户已授权开始实现，首版六端 Windows/macOS/Linux/Android/iOS/Web；本地文件与 URL 点播。
- 旧 V1 文档中的桌面首版和仅设计表述已被新决定替代；其他业务规则继续适用。
- UI 仅交固定 Agy 会话 `70aef10f-2cc5-4efb-9d8b-d102153531c2`，模型 `gemini-3.8-flash-high`、effort high，使用 liquid_glass_widgets skill。额度不足暂停告知，不换会话/模型。
- 业务、平台、测试及修复仅用核实免费的 OpenCode 模型；不自动发布。

## 首轮验证

现有 Flutter 工程包含 UI、设置和本地化，未接媒体与 WebRTC。当前发现 Linux 和 Android 模拟器；Windows/macOS/iOS/Web 真机验证尚未完成。

OpenCode 本地模型元数据中 `opencode/beam-free` input/output/cache 均为 0，支持工具调用；仅指定该模型，无付费回退。

计划依次验证：DataChannel/身份指纹能力、播放器 URL 与本地输入、六端媒体入口差异、纯业务同步测试，再交 UI 接线。实际结果在下文更新，不以依赖平台标签代替运行证明。

## 本机基线

- `flutter test`：现有 1 个 UI smoke test 通过；不代表观影业务通过。
- Flutter 3.44.2 / Dart 3.10.0；Linux GTK、libmpv 可用。
- Android 14 模拟器在线，Android SDK 许可未全部接受；未替用户确认许可。
- Flutter 默认未识别 Chrome；本机 Chromium 位于 `/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome`，可通过 CHROME_EXECUTABLE 指定后测试。
- 仓库没有 Git 元数据，不能提供 git diff/提交证明；本轮不自动初始化或发布仓库。
- 底层验证 OpenCode session：`ses_e4f2d89f5ffeguw6qw85xO5ttv`；调用事件的 cost 当前为 0。Agy 只在指定既有会话执行只读审查。

Web 测试环境补充：指定现有 Chromium 后 `flutter devices` 已识别 Chrome 158.0.8127.18。这里只证明测试入口可用，尚未证明媒体或 P2P 可用。

## UI 审查

固定 Agy 会话已提交只读接线建议，并按要求更正无证据的覆盖/实测声明、首版外的聊天/拖放要求和多余 facade 建议。其 CLI 返回 `status=ERROR` / stream interrupted；已生成审查内容，但不视为正常完成或 UI 实现通过。未发现额度告警，未更换会话或模型。仓库 UI 暂未接入业务。

## 构建检查

加入候选 flutter_webrtc/media_kit 依赖后，`flutter build linux --debug` 已成功。此结果只证明 Linux 构建，不证明媒体、身份验证或远程连接。

## 运行阻塞与审查

- 原生媒体测试在 Linux Xvfb 环境读到 sample MP4 时长；旧测试仅凭 duration 判成功，不作为实际画面/完整播放通过。已要求加强断言。
- 并发 Linux 集成构建会共享测试产物，首次结果不采信；后续测试必须顺序执行。
- 独立 WebRTC Linux 测试提前退出、未完成，原因待查，不能宣称 G1 通过。
- Android 测试在 Gradle plugin loader 处被全局仓库策略拦截；工作模型曾临时重命名全局 init.gradle，本协调者已中断并恢复原文件。后续禁止全局配置修改，只允许隔离/项目内验证。
- 审查已要求修正全局超时、ping 关联、真实背压、远端证书来源与媒体测试清理，不采用 SDP 声明冒充 transport 验证。

Linux 崩溃进一步定位：gdb 显示 SIGABRT 栈落在 libwebrtc 的 WebRtcVoiceEngine::Init；当前无音频服务，正在验证环境关联，尚不宣布根因已修复。原始堆栈保存在本轮 /tmp/eir-native-backtrace.txt。

Linux 验证进展：补齐 PulseAudio 后 PeerConnection smoke 与完整 DataChannel loopback 均通过，文本与二进制校验成功；实际 stats 中 transport.remoteCertificateId 对应 certificate fingerprint 可取。并未完成设备密钥签名握手，也未触发队列高水位，不能据此宣布 G1 全部通过。媒体时长可读但无渲染入口时持续 buffering、位置未推进，正在检查标准播放器输出配置。

`flutter build web --debug` 已通过；此构建仍是现有界面入口，没有证明未接线底层模块的 Web 功能通过。

## 底层验证片结果

- OpenCode 同一免费会话完成修复后：`flutter analyze` 无问题；现有 1 个 widget test 通过；Linux WebRTC loopback 1 项通过；Linux 媒体输入 3 项通过。
- HTTP 测试已改成实际播放并断言位置推进；资源/本地/HTTP 均观察到约 35–45ms 的位置推进。URI 的结果日志已脱敏。
- 背压高水位未触发、设备身份签名握手未实现、P2P 分片缓存/HLS 完整链路未实现，所以 G1/G2 仍未完整通过。
- Agy 独占新增 `integration_test/player_surface_test.dart`、`docs/UI-PLAYER-VALIDATION.md` 和所需 media_kit_video 渲染依赖，正在进行最小真实画面测试；尚无通过结论。
- 具体平台矩阵见 [PLATFORM-VALIDATION.md](PLATFORM-VALIDATION.md)。

## UI 画面验证片

固定 Agy 会话完成最小 `VideoController + Video` 集成测试，并经过审查修正：等待实际 320×240 尺寸，不能用 1×1 占位纹理判成功；初始化 shader 并为控制和释放设置超时。Linux 测试通过，覆盖画面输出、位置推进、暂停保持与 seek。见 [UI-PLAYER-VALIDATION.md](UI-PLAYER-VALIDATION.md)。此测试仅证明本机渲染，产品 UI 尚未接入真实房间业务。

## 下一切片

G1/G2 仍待完成：真实设备签名握手与拒绝、跨端连接/ICE 恢复、弱网背压、P2P 视频分片传输及校验缓存、本机 HLS/浏览器媒体桥接。随后才能将真实房间状态接到产品 UI。Android 需要隔离 Gradle 环境验证，Windows/macOS/iOS 需要对应构建/运行环境；Web 需要适合的浏览器测试入口。六端未完成，未发布。

## 开发与编译工具连接

按用户要求使用全局 MCP `norns`，端点为 https://norns.cc.cd/api/mcp。Bearer 认证保存在本机 Codex 全局配置，仓库不保存凭证。后续开发与编译前先检查该服务能力与连接，配置服务不触发构建、上传或发布。

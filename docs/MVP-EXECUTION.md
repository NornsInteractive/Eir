# MVP 实施与验收跟踪

用户授权：继续开发直到 MVP 完成。首版六端，两人房间，本地兼容 MP4 与 HTTPS 点播 URL；既有安全、权限、同步、列表、重连、多语言与主题要求继续有效。

## 分工

- 业务、媒体与构建：OpenCode 免费额度耗尽后，按用户指示自动接续已核实免费的 CodeBuddy `hy3` / `deepseek-v4.1-flash`，不启用付费回退。所有编译、安装、测试及相关环境配置、依赖、打包问题均由这些工作轮自行执行和解决，不编辑产品 UI。
- Agy 固定会话 `70aef10f-2cc5-4efb-9d8b-d102153531c2`，`gemini-3.8-flash-high/high`：唯一 UI 与接线实施者，使用 Liquid Glass skill；额度不足立即暂停告知，不换模型/会话。
- 协调者：需求、分派、跟踪与结果汇总；不接管编译、安装、测试或其配置修复，不绕过上述代码所有权。

## 交付门槛

- 创建、邀请、加入、离开、解散真实可用，无演示房间或假成功。
- 设备身份、签名权限、房主/管理员/成员、撤销与重放检查。
- URL 与本地视频在两端真实播放；本地视频走 P2P、无完整下载前置、支持拖动、校验与有界缓存。
- 权威播放与列表有序提交，单调时钟同步，漂移纠正与重连恢复；UI 消费真实状态。
- 全局中英、本机外观与明暗主题色独立持久化；切换不重建会话。
- 核心自动化、双客户端真实链路和 UI 验证通过，逐端注明构建/运行/测试状态；未测不得标通过。
- 提供运行说明、信令启动方式、可审查构建产物与平台限制；不自动发布。

## Norns 检查

本轮 authenticated initialize/tools/list 和 build environments list 成功。登记有本机 Linux/Android 工具链及 Windows SSH 构建机，暂未发现 macOS/iOS 环境。登记内容为其他产品历史数据，只参考工具链能力，不执行其中产品脚本、不复用其他产品签名。未解密 SSH/签名凭据，未发布。

## 接线依据

业务 API 见 [MVP-API.md](MVP-API.md)，以实际 lib/core/room_session.dart 为准；核心与 UI 各自测试结果见其状态文档，协调者最终核验后才更新完成状态。

## 当前状态

主要功能开发、本轮可用环境验收和最终产物汇总已完成。六端运行验收尚未全部完成，不能标为六端全部通过。产物运行说明见 [RUN.md](../artifacts/mvp/RUN.md)，逐端结果见 [PLATFORM-MATRIX.md](../artifacts/mvp/PLATFORM-MATRIX.md)。

当前平台证据见 [构建状态](MVP-BUILD-STATUS.md) 和 [Web 验收报告](MVP-WEB-VALIDATION.md)。CodeBuddy 已报告核心 85 项、媒体 35 项、UI/widget 8 项通过；Linux 实际 URL、本地文件、65 MiB 未传完即播、恢复与离线边界集成通过。Android 最新源码 Release 安装启动和 URL 2 项、本地 2 项、核心恢复 4 项、重试耗尽恢复 1 项通过。Web 正式产品双上下文 28 项操作通过，W3 重试入口缺陷已由核心修复并在真实浏览器中点击验证恢复，原房间、身份与列表保留，双端实际解码与控制恢复。所有编译、安装、测试及其配置修复均由免费 CodeBuddy 工作轮执行。

Windows 最新 Release 编译通过，运行仍受 Server Core 缺少 OPENGL32.dll 与桌面环境阻塞，待用户提供可运行桌面环境；未将该缺口视为已获豁免。macOS 按用户要求暂缓，iOS 无构建环境。真实异地网络、性能阈值和 Apple 平台运行仍未验证；不包含 TURN 中继。最终包与校验和以构建状态和 artifacts/mvp/PLATFORM-MATRIX.md 为准，无自动发布。

以下按时间保留历史记录；已经解决的历史问题不作为当前阻塞。

## 协调更新

- 初稿安全审查未通过：存在签名布尔值忽略、未绑定实际指纹、未验签控制提交及本地媒体空实现；已停止该工作轮，不作为 MVP 或可用安全实现。
- 后续使用已核实 input/output/cache 全 0 的 `opencode/pulse-alpha-free` 补齐业务切片，保持 Agy 会话/模型不变。
- Windows SSH 登记端口 127.0.0.1:14320 当前 TCP 拒绝连接，未读取凭据；Android 模拟器 127.0.0.1:14251 可达。
- 准备 /tmp/eir-gradle-home 隔离配置，复用既有 wrapper/caches/jdks，避免全局 init.gradle 策略污染；不修改全局文件。

Android 环境更新：使用 GRADLE_USER_HOME=/tmp/eir-gradle-home 执行 android/gradlew help --no-daemon 成功，项目配置阶段已通过；尚未将其视为 APK 构建/运行成功。

Windows 环境更新：用户开机后端口已可达，并显式确认 ED25519 主机指纹。已固定该密钥，通过 Norns 授权获取的连接资料完成 SSH 与 Flutter 工具链检查（3.38.1 / Dart 3.10.0）。为 Eir 建立独立工作目录，未读写其他产品源码或签名。用户要求先暂缓 macOS 构建；代码仍保留跨平台目标。

本地媒体子任务由核实费用为 0 的 `opencode/crouton-alpha-free` 在 lib/media 和独立测试内实现，核心工作轮仍为 pulse-alpha-free；双方不编辑对方文件。UI仍固定原Agy会话/模型。

活动工作会话：核心 OpenCode ses_e4efa03efffeRO5YgDTL7E7f1d；媒体 OpenCode ses_e4eefe678ffeMWuctwKrzkswER。截至本次事件统计，两者报告费用均为0；不启用付费回退。

核心真实链路更新：修复提交消息缺少路由类型及角色同步后，Linux 两个 RoomSession + 实际信令/WebRTC/媒体 URL 集成测试通过，覆盖创建/加入/列表/播放/只读拒绝/管理员增撤/seek/解散；本地媒体与其他平台仍待集成验证。

## 最新独立复核（2026-11-06）

- Norns authenticated initialize 与构建环境查询再次成功；无发布操作。
- `flutter test test/ui test/widget_test.dart`：8 项通过，覆盖真实 UI 控件交互、设置持久化、角色按钮及会话不因主题/语言切换而重建；业务对象为测试替身，不能据此宣称双机互通。
- `flutter test test/core test/media`：102 项通过，仍需结合真实信令/WebRTC/解码集成验证。
- Windows：已在 Eir 专属工作目录安装官方 Flutter 3.44.2 / Dart 3.12.2，未修改其他产品共用的旧 SDK。诊断源码快照执行 `flutter pub get` 与 `flutter build windows --debug` 成功；因仍有修复，此结果不是最终版本构建结论。新 SDK 的 5 个 SDK 锁定依赖发生解析变化，最终交付需记录。
- Android：隔离 Gradle home 下正在执行实际 APK 构建，完成前不标记通过。
- 真实本地媒体集成仍在修复协议路由；Web Service Worker 的 Range/令牌/多窗口隔离正在浏览器验证，未完成项不计入通过。

用户已明确暂缓 macOS 构建。iOS 仍缺少 macOS/Xcode 环境；保留代码与目标，不将编译目标等同于功能验证。

## 媒体实现方案调整

首版改为兼容 MP4 原文件分块，而非先 remux 为 fMP4/HLS：使用已选 `cross_file` 随机访问、`crypto` SHA-256、`flutter_webrtc` DataChannel 与 `media_kit` 解码。原生端使用仅 loopback 可访问、携带会话令牌的 HTTP Range 适配；浏览器使用相同语义的 Service Worker Range 适配。保留无服务器视频上传、按需取块、坏块校验、有界缓存和随机 seek 的目标，避免引入六端不一致的 FFmpeg 可执行程序交付。完整文件哈希准备仍随文件大小增长，首版不承诺渐进清单。

这是架构实现调整，不代表跨平台链路已全部通过。不兼容编码、非 faststart 与长 GOP 文件的开播/seek 行为必须按实际播放器能力报告，不承诺自动转码。

## Android 复核更新

隔离 Gradle 下 `flutter build apk --debug` 成功。随后模拟器真实双会话 URL 集成在 WebRTC 网络线程发生 SIGABRT；日志定位到 `ACCESS_NETWORK_STATE` 权限缺失导致 Android `SecurityException`。已交平台工作轮修复；运行状态仍为未通过，不能用编译成功替代。

Linux 测试环境另补齐 Secret Service 运行工具（gnome-keyring/libsecret-tools），以便后续产品启动验证使用真实安全存储；不改为明文密钥存储。

## 最新执行分工调整

按用户本轮明确要求，所有编译、安装、测试及其环境配置、依赖、打包问题均交给已核实免费的 OpenCode 或 CodeBuddy 自行处理。协调者只分派、跟踪和汇总，不再直接执行或诊断解决上述操作。CodeBuddy 尚未核实免费，不启用。Agy 继续负责产品 UI 与接线实现，测试执行交 OpenCode。此前协调者执行的检查保留为历史证据，后续最终验收由 OpenCode 执行并提供结果。

免费模型服务进展：pulse-alpha-free 曾返回可重试的上游 429，多个工作轮随后长时间无新事件。构建轮保留同一 OpenCode 会话，改用本地模型元信息中 input/output/cache 均为 0 的 `opencode/deepseek-v4.1-flash-free` 重试；禁止付费回退的约束不变。核心/媒体仍在原免费会话继续。

## 历史阻塞：免费模型额度（已由 CodeBuddy 免费接续解除）

OpenCode 日志已明确返回 `Free usage limit reached`，并非仅暂时 429。pulse-alpha-free 与已核实免费的 deepseek-v4.1-flash-free 构建重试均遇到同一免费额度限制。为遵守禁止付费回退，已停止无进展的自动重试，保留源码、会话与工作轮任务。CodeBuddy CLI 已安装，但尚未获得可免费使用的明确证据，未调用其推理模型。

已向用户请求切换有免费额度的 OpenCode 账户，或提供 CodeBuddy 可用免费账号/模型；收到后继续原 MVP，不能将当前状态标为完成。所有后续编译、安装、测试与相关配置/打包仍全部由 OpenCode/核免费 CodeBuddy 执行和处理，协调者不接管。

交接状态：UI 已交接冻结；媒体轮曾实际报告 9 MiB Chromium Range 通过（后台测试，不是产品视频端到端）；缓存清理 API 与测试已开始，最终交接文档未完成；核心并发与紧凑媒体清单等仍需完成；构建轮已开始处理平台配置和 Android 测试，最终六端矩阵与产物尚未交付。全部以工作轮恢复后的实际验收为准。

## CodeBuddy 免费接续

用户明确要求 OpenCode 额度用完后切换 CodeBuddy 免费模型继续。已核实本机 CodeBuddy 产品模型表：`hy3` / `Hy3` 的 `credits` 为 `x0.00 credits`，官方文档也列为限时免费。现改用该模型接续核心、媒体和构建工作；不配置付费回退。原 OpenCode 会话及代码保留，编译/安装/测试和相关配置打包均由 CodeBuddy 自行执行和解决，协调者不接管。

## 最终验收轮

核心并发修复已由 CodeBuddy 完成，核心、媒体及 UI 均已交接；构建工作轮以当前源码统一复核。已报告 113 项单元/UI 测试通过，Linux URL、本地文件与 65 MiB 实际 WebRTC 流式播放集成通过。Android 修复后复验、Windows 最终源码同步构建、Web 产品双客户端实测与最终打包仍在该工作轮执行，不能据此宣布全部平台完成。

此前请求更换 OpenCode 账号已被用户“自动改用 CodeBuddy 免费模型”的指示取代；当前 CodeBuddy Hy3 正常执行，媒体工作轮实际结果记录的 `total_cost_usd` 为 0，不需要用户再次选择账号。后续编译、安装、测试及相关配置/打包均由工作轮自行处理。

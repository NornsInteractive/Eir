# 观影功能文档索引

当前阶段：已授权实施，先验证关键链路。最新范围与执行记录见 [实施进度](IMPLEMENTATION.md)。

## 阅读顺序

1. [第一版需求与业务规则](V1-PRD.md)：做什么、用户流程、权限、状态及异常行为。
2. [第一版技术架构](V1-ARCHITECTURE.md)：Flutter 分层、本地文件与 URL 播放链路、同步算法、部署边界。
3. [第一版协议与安全规格](V1-PROTOCOL.md)：身份、邀请、控制顺序、消息、媒体清单及验证规则。
4. [第一版验收与实施计划](V1-ACCEPTANCE.md)：风险验证、功能验收、安全验收和交付门槛。

[原始 PRD](PRD.md) 保留为完整产品愿景。第一版实施范围以 V1 文档为准；后续能力不能自动算入第一版。V1 文档定义需求与原设计，不代表测试结论；实施中的方案调整和独立复核见 [MVP 执行记录](MVP-EXECUTION.md)。

## App 通用要求

[多语言与主题设置](APP-SETTINGS.md) 适用于整个 App，第一版纳入多语言、主题切换，以及浅色/深色各自独立保存的主题色。

## 项目开发约束

[项目开发原则](DEVELOPMENT-PRINCIPLES.md)：开发任何功能或逻辑前先检查现有实现及成熟库；优先复用，减少自研与封装。App 后续自定义外观开发与切换规则见 [App 通用设置](APP-SETTINGS.md) 第 7 节。

未明确限定平台的功能默认覆盖 Windows、macOS、Linux、Android、iOS、Web，具体规则见 [项目开发原则](DEVELOPMENT-PRINCIPLES.md) 第 5 节。既有 V1 桌面先行仍是待评审假设，不代表用户确认的平台豁免。

## 范围假设

当前首版覆盖 Windows、macOS、Linux、Android、iOS、Web。两人房间，本地兼容文件与 URL 点播；角色权限沿用设计，多人 Swarm、自动转码和 TURN 暂缓。既有 V1 文档中“桌面先行/移动与 Web 暂缓”已被本次六端决定替代，不再作为实施范围。

媒体准备方式按平台能力验证，桌面 FFmpeg 不能直接当作 Web/移动端方案；不得用不可播放占位实现冒充六端支持。

## 实施记录

- [当前业务修复与验收计划](CURRENT-REPAIR-PLAN.md)
- [实施进度与约束](IMPLEMENTATION.md)
- [平台能力验证矩阵](PLATFORM-VALIDATION.md)
- [UI 播放器画面验证](UI-PLAYER-VALIDATION.md)
- [MVP 实施与验收跟踪](MVP-EXECUTION.md)
- [当前构建产物与逐端验证状态](MVP-BUILD-STATUS.md)
- [Web 真实产品双端验收](MVP-WEB-VALIDATION.md)
- [核心需求与验收证据映射](MVP-ACCEPTANCE-MAP.md)
- [Android 渲染配置 rev7 验收与交接](ANDROID-REV7-VALIDATION.md)

实施过程中的历史记录保留用于追溯；当前是否通过应查看上述专项报告的最新结果。构建成功、单元测试通过和双客户端真实播放是不同证据，不能互相替代。

# 项目约束

- 开始工作前阅读 docs/README.md 与任务涉及的设计文档。
- 所有功能和逻辑开发遵循 docs/DEVELOPMENT-PRINCIPLES.md：先检查现有能力与成熟库，优先复用，避免重复造轮子和过度封装。
- App 外观、多语言及主题遵循 docs/APP-SETTINGS.md：支持后续自定义开发与切换，明暗主题色独立配置，外观切换不复制或重建业务逻辑。
- 未明确限定平台的业务功能默认支持 Windows、macOS、Linux、Android、iOS、Web；依赖选型、实现和验收均覆盖目标平台。不得把 Flutter 可编译视为功能可用，平台限制需明确记录，不得静默缩减范围。详见 docs/DEVELOPMENT-PRINCIPLES.md。
- 用户已授权执行实施计划。首版覆盖 Windows/macOS/Linux/Android/iOS/Web；先验证媒体与 WebRTC 关键链路，按功能切片实施和测试，不自动发布。
- UI（包括样式和 UI 接线）仅交既有 Antigravity 会话 70aef10f-2cc5-4efb-9d8b-d102153531c2，固定 gemini-3.8-flash-high/high；使用 liquid_glass_widgets skill，额度不足暂停并告知用户，不新建或切换会话。
- 业务逻辑、平台功能、测试和修复仅交经核实免费的 OpenCode 模型，禁止转付费；CodeBuddy 仅核实免费后备用。

- 开发、编译产品应用前先连接并检查全局 MCP `norns`（https://norns.cc.cd/api/mcp）的相关工具；连接失败如实报告，不静默跳过。认证仅从本机全局配置读取，不写入仓库、提示词或日志。连接配置不代表自动发布授权。

- 用户最新明确要求：UI、编译、安装、打包与发布交既有 Agy Eir 会话，业务逻辑及测试交已核实免费的 OpenCode 或 CodeBuddy。协调者只分派、汇总最终结果和处理超时卡点，不直接执行这些操作。发布阶段只向 Agy 交代“打包 Android 和 Windows 并发布”，具体方式由其依据项目现有流程处理。
- 代理任务采用完成通知，不实时读取日志。代码/UI 20 分钟、编译打包 45 分钟、双端验收 60 分钟仍无结果时，才检查一次卡点；重试重新设置期限。完成标记不等同于主动通知，运行环境不支持通知时明确记录。

- 免费模型接续规则：OpenCode 免费额度不可用时，自动切换至已核实免费的 CodeBuddy 模型继续，不要求用户重复选择。当前已从本机 CodeBuddy `product.json` 核实 `hy3` 的 `credits` 为 `x0.00 credits`；选择时须重新确认免费标识，不配置付费回退或自动购买。

- 已核实 CodeBuddy `deepseek-v4.1-flash` 当前也标注 `x0.00 credits`，可作为免费接续模型；任何切换仍须重新核实免费标识，禁止付费回退。UI 既有 Agy 会话/模型限制保持不变。

- 本地 APK 保留规则：每次编译 APK，本地不需要保留历史安装包，须全部清除（`rm -f eir-v*.apk`），本地仅保留当前目标版本的单份产物。

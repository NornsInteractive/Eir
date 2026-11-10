# Eir Apple 风格交互复刻版 (Web Preview & Prototype)

本项目基于 Stitch MCP 的 Eir 屏幕原型，深度结合 Apple HIG、macOS Sequoia / iOS 18 毛玻璃（Liquid Glass）视觉系统与 Emil Kowalski 设计工程标准，依照项目文档规范完成了完整的高保真交互复刻。

---

## 核心设计与工程特性

### 1. 纯粹的 Apple 毛玻璃材质体系 (Liquid Glass & Vibrancy)
- **多层级光影架构**：
  - **基础画布**：macOS 极夜深空背景（深色 `#060608` / 浅色 `#F5F5F7`），辅以 Apple 动态折射光晕光雾。
  - **一级材质 (Structural Surfaces)**：`backdrop-filter: blur(28px) saturate(210%)`，带 1px 细微半透描边与内层顶光高光（`inset 0 1px 1px rgba(255, 255, 255, 0.28)`）。
  - **二级材质 (Cards & Docks)**：`backdrop-filter: blur(32px) saturate(190%)`，多层物理投影与亚光磨砂深度。
  - **三级浮层 (Modals & Popovers)**：`backdrop-filter: blur(40px) saturate(220%)`。
- **顶面高光反射 (Specular Edge)**：关键按钮与卡片顶部采用高光渐变线（`.specular-top`），模拟光线在磨砂玻璃边缘折射的真实物理质感。
- **微弹簧触控交互 (Spring Dynamics)**：严格落实直接操纵感，所有可点击元素配备 `cubic-bezier(0.2, 0.8, 0.2, 1)` 曲线及 `:active { transform: scale(0.965); }` 缩放反馈。

### 2. 全局通用多语言无损热切 (i18n)
- 遵循 [APP-SETTINGS.md](../docs/APP-SETTINGS.md) 规范：
  - 集中管理翻译字典（简体中文 `zh-CN` 与 English `en-US`）。
  - 支持 **跟随系统**、**简体中文**、**English** 手动选择，默认跟随系统。
  - 动态切换即时生效，无需刷新页面，不丢失输入表单、不重建房间会话、不重置播放器进度。
  - 用户媒体标题、昵称与 URL 保持原文，所有 UI 控件与提示信息实时更新。

### 3. 主题模式与独立主题色配置 (Independent Theme Colors)
- 严格遵循 [APP-SETTINGS.md](../docs/APP-SETTINGS.md) 第 3 节约束：
  - **主题模式**：浅色 / 深色 / 跟随系统，默认跟随系统。
  - **浅色主题色 (`lightThemeColor`)**：独立保存、独立选色（预设 Apple 经典蓝、深靛紫、兰花紫、薄荷青、暖日橙、野玫瑰红及自定义 HEX），独立重置为 `#007AFF`。
  - **深色主题色 (`darkThemeColor`)**：独立保存、独立选色（预设极光蓝、星空紫、霓虹紫、荧光绿、琥珀橙、亮玫红及自定义 HEX），独立重置为 `#0A84FF`。
  - **明暗绝对隔离**：禁止单一变量覆盖两套模式；深色模式下调整浅色主题色仅保存配置并预览，绝不强制切换模式；反之亦然。两套主题色互不串色，重启持久化保留。

### 4. 跨平台响应式与自适应 (UI Adaptivity)
- 覆盖桌面端宽屏（>=1280px）、中屏/笔记本（1024px-1279px）、平板端（768px-1023px）以及紧凑移动端（<768px）。
- 桌面端：顶部浮动毛玻璃 Dock，16:9 剧场级画布，右侧浮动抽屉 Inspector（讨论、列表、成员、遥测四合一选项卡），底部沉浸式同频头像视线流。
- 移动端：自适应全宽视频画布，原生触控悬浮播放控制条，手势友好的底部标签与折叠抽屉。

### 5. 放映室业务流程与高保真交互
- **探索大厅与放映室无缝互通**：点击大厅卡片或创建房间进入放映室，顶部一键退出放映室返回大厅。
- **创建专属放映室模态窗**：设置房间名、选择媒体来源（HTTPS 点播直链 / 本地免转码文件）、生成一次性邀请令牌。
- **粘贴加入**：支持 `⌘V` 一键粘贴加入并验证。
- **播放器控制**：播放/暂停、快进/快退 10s、精准进度条拖拽 seek、音量微调、倍速选择（0.5x, 1x, 1.25x, 1.5x, 2x）、全屏切换。
- **Locked Sync 锁频指示**：展示多端毫秒级单调时钟对齐，进度条上动态渲染各成员视线锚点。
- **媒体播放列表**：支持添加 HTTPS 点播直链、添加本地免转码文件（带 fMP4 切片、SHA-256 签名与 Loopback 挂载模拟进度条）。
- **成员与权限管理**：房主可对普通成员进行“设为管理”与“撤销管理”操作，展示每位成员的 RTT、时钟偏差与缓冲刻度。
- **同步遥测矩阵**：单调时钟矩阵、WebRTC DataChannels（ctrl、data-urgent、data-bulk）状态与丢包率、DTLS 证书指纹双向校验。

---

## 运行与预览

直接在浏览器中打开：
```bash
file:///workspace/projects/Eir/web/index.html
```
或者启动静态服务器：
```bash
cd /workspace/projects/Eir/web && python3 -m http.server 8080
```

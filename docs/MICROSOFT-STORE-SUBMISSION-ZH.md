# Eir · 微软应用商店 (Microsoft Store / Partner Center) 上架提报全览指南

本文档专门为 **Eir** 上架至 **微软合作伙伴中心 (Microsoft Partner Center)** 提供逐项、逐页的完整中文填报材料与指引。所有字段、说明文案与参数均已按照后台最新提报界面规范梳理，可直接对照复制粘贴使用。

---

## 0. 基本信息与交付包速查

| 参数项 | 填写值 / 规格 | 说明 |
| :--- | :--- | :--- |
| **已保留应用显示名称** | `Eir-Synchronized Watch Party` | 必须与后台“产品名称保留”完全一致 |
| **程序包标识名称 (Identity Name)** | `Norns.Eir-SynchronizedWatchParty` | 后台自动分配的包名 |
| **程序包系列名称 (PackageFamilyName)** | `Norns.Eir-SynchronizedWatchParty_sxt4q0tm9x2xr` | 自动派生的包系列名 |
| **发布者 (Publisher)** | `CN=257586C2-E7B0-47F3-BAED-A744A66748A1` | 开发者账号 Publisher ID |
| **发布者显示名称** | `Norns` | 开发者团队名称 |
| **交付程序包文件** | `eir-1.0.40.0-windows-x64-store.msix` | 位于项目根目录，已封装 VC++ 依赖 |
| **程序包版本号** | `1.0.40.0` | 对应版本 v1.0.40 |
| **目标平台与架构** | `Windows.Desktop` / `x64` | 适配 Windows 10 (19041+) 及 Windows 11 全版本 |
| **SHA-256 校验哈希** | `d8378c14dce31feb66e5a7b36ebfe3bbfa5b5c54188022ce3205ebc55d310f2f` | 用于核验程序包完整性 |

---

## 1. 定价和可用性 (Pricing and availability)

点击进入 **“定价和可用性”** 页面：

| 选项名称 | 建议选择 / 填入内容 | 详细说明 |
| :--- | :--- | :--- |
| **市场 (Markets)** | **全部市场 (All markets)** | 推荐勾选全部 240+ 个国家与地区（默认包含中国及海外全部市场）。 |
| **定价 (Pricing)** | **免费 (Free)** | 基础价格选择 `Free`。 |
| **免费试用 (Free trial)** | **无免费试用 (No free trial)** | 应用本身完全免费，无需设置试用。 |
| **销售和促销价格 (Sale pricing)** | **无 (None)** | 留空或不启用。 |
| **预订 (Pre-order)** | **不启用 (No)** | 选择直接发布，不设预订。 |
| **发布计划 (Schedule)** | **认证完成后立即发布 (As soon as possible)** | 审核通过后系统自动上线商店。 |
| **可见性 (Visibility)** | **公开发布并可在应用商店中搜索 (Publicly available)** | 允许用户在 Windows 应用商店直接搜索和浏览下载。 |
| **组织批量许可 (Organizational licensing)** | **允许批量采购与离线许可 (推荐全部勾选)** | 允许企业与教育用户批量分发。 |

---

## 2. 产品属性 (Properties)

点击进入 **“属性”** 页面：

| 选项名称 | 填入内容 / 建议选择 | 说明 |
| :--- | :--- | :--- |
| **主要类别 (Primary category)** | **娱乐 (Entertainment)** 或 **照片和视频 (Photo & video)** | 推荐首选 `娱乐 (Entertainment)`，次选 `照片和视频`。 |
| **子类别 (Subcategory)** | **视频 (Video)** | 与多人在线同步观影属性完全吻合。 |
| **隐私策略 URL (Privacy policy URL)** | `https://github.com/NornsInteractive/Eir/blob/main/PRIVACY.md` | 指向 GitHub 根目录下托管的中英双语隐私政策。 |
| **备用隐私政策 URL (网页版)** | `https://eir.norns.cc.cd/privacy.html` | 亦可作为备用在线网页提交。 |
| **技术支持网页 (Support website)** | `https://github.com/NornsInteractive/Eir` | GitHub 开源项目主页。 |
| **技术支持联系邮箱 (Support email)** | `support@norns.cc.cd` | 官方服务与支持邮箱。 |
| **游戏选项 (Gaming options)** | **否 (No)** | 本应用为社交视听工具，非游戏。 |
| **显示模式 (Display mode)** | **窗口化 / 全屏自适应 (Windowed)** | 标准桌面应用窗口显示。 |

---

## 3. 年龄分级 (Age ratings - IARC 问卷指引)

在 **“年龄分级”** 页面点击完成 IARC 问卷，按下列答案依次如实选择：

1. **您的联系电子邮件**：填写您的接收通知邮箱（如 `support@norns.cc.cd`）。
2. **应用程序类别**：选择 **实用工具、工作效率、通信或其他参考应用程序 (Utility / Productivity / Communication)**。
3. **暴力内容**：选择 **“否”**（应用不含任何暴力、流血或伤害画面）。
4. **性与暗示内容**：选择 **“否”**（应用不含任何色情或性暗示元素）。
5. **恐怖或恐慌**：选择 **“否”**。
6. **赌博或模拟赌博**：选择 **“否”**。
7. **脏话或粗俗语言**：选择 **“否”**。
8. **管制物品（毒品、烟草、酒精）**：选择 **“否”**。
9. **杂项功能调查**：
   - **用户交互（是否允许用户在线聊天、交换音频或媒体）**：选择 **“是 (Yes)”**（应用具备多人房间文字互动、双向语音及屏幕共享功能）。
   - **共享物理地理位置**：选择 **“否 (No)”**（不获取亦不收集用户 GPS 或物理位置）。
   - **购买数字商品（应用内购）**：选择 **“否 (No)”**。
10. **问卷结论**：点击保存并生成评级，系统将自动评定为全球通用的全年龄友好级别（例如 ESRB: Everyone, PEGI: 3, USK: 0）。

---

## 4. 程序包上传 (Packages)

点击进入 **“程序包”** 页面：

1. **上传文件**：将根目录下的 [eir-1.0.40.0-windows-x64-store.msix](file:///workspace/projects/Eir/eir-1.0.40.0-windows-x64-store.msix) 拖拽上传。
2. **解析校验**：上传成功后系统将自动解析出以下信息，请核对是否完全吻合：
   - 软件包名称：`Norns.Eir-SynchronizedWatchParty`
   - 版本号：`1.0.40.0`
   - 目标架构：`x64`
   - 最低操作系统支持：`Windows 10, version 19041.0 或更高版本`
3. **关于签名**：微软商店引入通道会自动使用微软受信任的商业证书进行二次公签，上传此官方 MSIX 即可直接进入审核，用户从商店端安装零证书阻碍。

---

## 5. 受限功能声明说明 (Restricted Capabilities)

上传程序包后，系统会检测到清单声明了 `runFullTrust`（标准 Win32 完整执行信任权限）。Partner Center 会要求在文本框中说明申请该权限的理由。

请将以下说明文字复制粘贴至申明理由文本框中：

### 中文申报文案 (复制此段)
```text
Eir 是一款专注于高画质同步观影与低延迟屏幕共享的 Flutter 桌面应用程序。本应用申请声明 runFullTrust 权限具有不可替代的业务必要性，具体说明如下：

1. 高清多媒体硬件解码：应用内置高性能原生媒体渲染库（libmpv），用于在本地流畅解码 4K/1080P 超高清本地视频及网络媒体流，需依赖标准 Win32 运行时与图形硬件接口。
2. 毫秒级 WebRTC 点对点通信：应用采用去中心化 P2P 架构，通过底层原生 Socket 与 libwebrtc 协议栈实现房间观众间的音视频直传与毫秒级播放进度同步，无需经由中央服务器转发。
3. 本地文件系统选取：用户可自主选择本地视频文件向好友发起同步放映，需访问标准文件选择器。

应用完全秉持“免登录、零留存、端到端加密”的安全原则，绝不执行任何破坏性系统操作，完全符合微软应用商店安全与隐私规范。
```

### 英文对照申报文案 (如后台提示需英文，可复制此段)
```text
Eir is a high-performance Flutter desktop application designed for synchronized video co-watching and low-latency 60 FPS screen casting. The application requires the 'runFullTrust' capability for the following essential purposes:

1. High-Performance Multimedia Engine: It embeds native libmpv binaries to achieve hardware-accelerated 4K/1080P local and network video decoding.
2. Direct P2P WebRTC Pipeline: It utilizes native sockets and libwebrtc libraries to establish low-latency peer-to-peer data and media streaming directly between users without intermediate servers.
3. Local Video Selection: It allows users to pick local media files through standard OS file dialogues for watch party playback.

The application follows strict zero-cloud-retention and end-to-end encryption principles, performs no invasive operations, and fully complies with Microsoft Store safety standards.
```

---

## 6. 应用商店商品名录 (Store listing · 中文简体)

点击进入 **“应用商店商品名录” -> “中文(简体)”**：

### 6.1 产品显示名称 (Product Name)
```text
Eir-Synchronized Watch Party
```

### 6.2 简短说明 (Short description，用于搜索结果摘要与卡片展示，100 字以内)
```text
异地同屏放映室：60 FPS 极速屏幕共享、毫秒级音视频同步观影。免注册免登录，双向语音通话，端到端 P2P 隐私保护。
```

### 6.3 完整描述 (Description，支持纯文本排版)
```text
【产品简介】
Eir 是一款专为朋友、情侣与团队打造的异地同步观影与极速屏幕共享桌面客户端。
无需复杂的注册登录流程，启动即是大厅；一键创建专属放映室，通过 6 位房间码即可让好友跨越千山万水，体验宛如围坐同一块屏幕前的欢聚感动。

【核心功能亮点】
1. 🎬 毫秒级音视频协同放映
   支持本地视频文件（MP4、MKV、WebM 等主流格式）及网络流媒体链接。创新的自适应缓冲与时间戳微秒级对齐算法，拖动进度、暂停、快进全员即时同频，彻底告别“三二一倒数开播”的尴尬。

2. 🖥️ 60 FPS 高清极速屏幕共享
   内置低延迟桌面投屏引擎，支持全屏或单个应用程序视窗捕获。原生支持系统伴音直传，与好友流畅同屏看球赛、看直播、协同工作或联机打游戏。

3. 🎙️ 实时双向语音与氛围弹幕
   边看边聊！集成低延迟语音通话管道，一键开麦交流；房间内支持彩色即时文字弹幕与表情互动，视听互动两不耽误。

4. 🔒 纯粹免登录与端到端隐私保护
   不收集个人身份信息、无繁琐账号密码，不留存观影历史。所有媒体数据及音视频流均基于 WebRTC 点对点直连（P2P）传输与加密，私密交流绝不上云。

5. 💎 极简现代的液态玻璃视觉
   采用现代液态玻璃微质感设计语言，沉浸式极简播放器布局，支持明暗主题自适应与中英多语言无缝切换。
```

### 6.4 本版本新增功能 (What's new in this version)
```text
【v1.0.40 版本新特性】
1. 🪟 微软商店官方 MSIX 发布：针对 Windows 10/11 深度适配，内置完整图形与多媒体运行库，安装更稳定顺畅。
2. 🌐 全面多语言国际化：核心放映室界面、投屏控制台、设置对话框实现全量中英文多语言对齐。
3. 🖥️ 投屏控制台体验升级：优化推流控制逻辑与观众连麦状态显示，提升 60 FPS 投屏稳定性。
4. 🎬 观影体验细节打磨：新增画面比例自适应切换、微秒级缓冲对齐机制与更优雅的房间状态反馈。
5. ⚙️ 网络诊断与穿透增强：支持实时 STUN/TURN 服务器状态探测，改善复杂局域网与校园网穿透成功率。
6. 🛡️ 隐私与安全性保障：强化端到端传输加密机制，严守数据不落云端原则。
```

### 6.5 产品功能列表 (Product features，每个特性独立一行，后台点击“添加功能”)
```text
毫秒级播放进度同步：本地视频与网络串流全员毫秒级同步放映
60 FPS 极速屏幕共享：高清桌面与窗口捕获，支持系统声音内录同传
实时双向低延迟语音通话：边看边聊，沟通零障碍
纯粹免注册免登录：6 位房间码一秒入会，用完即走
端到端 P2P 加密：媒体流量直连传输，数据绝不上云
丰富多媒体格式支持：MP4、MKV、FLV、WebM 及 m3u8 等高清流
互动弹幕与文字聊天：彩色弹幕漂浮，营造真实放映厅互动氛围
液态玻璃现代质感设计：深色/浅色自适应，全界面中英文双语
```

### 6.6 搜索关键词 (Search terms，最多 7 个词，每词 30 字符内)
1. `同步观影`
2. `屏幕共享`
3. `一起看视频`
4. `异地放映室`
5. `WebRTC`
6. `投屏`
7. `WatchParty`

### 6.7 推荐硬件要求 (Hardware requirements)
- **最低配置**：
  - 操作系统：Windows 10 19041 或更高版本 (x64)
  - 处理器：双核 2.0 GHz 或更高
  - 内存：4 GB RAM
  - 显卡：支持 DirectX 11 / OpenGL 3.3 的集成显卡
- **推荐配置**：
  - 操作系统：Windows 11 (x64)
  - 处理器：四核 2.5 GHz 或更高
  - 内存：8 GB RAM
  - 显卡：独立显卡（NVIDIA / AMD / Intel Arc）
  - 网络：宽带互联网连接（推荐下行 10 Mbps+ 用于 1080P/4K 同步）

### 6.8 版权与支持信息 (Copyright & Support)
- **版权声明**：`Copyright © 2026 Norns Interactive. All rights reserved.`
- **支持网站**：`https://github.com/NornsInteractive/Eir`
- **支持电子邮件**：`support@norns.cc.cd`
- **开发者名称**：`Norns`

---

## 7. 提交选项与测试人员说明 (Notes for certification)

在最终的 **“提交选项 (Submission options)”** 页面，找到 **“认证测试人员说明 (Notes for certification)”** 文本框。

这是微软人工审核员审查应用时的核心指引，请将以下文本完整填入：

```text
尊敬的微软审核团队：

感谢您对 Eir-Synchronized Watch Party 的审核！为方便贵方高效完成测试，特说明如下：

1. 账号认证说明：
   本应用为纯粹免登录架构，无需任何账号、密码或手机号码。启动应用即可直接使用全部功能。

2. 快速功能测试步骤：
   步骤一（创建放映室）：
   - 启动应用，进入大厅，点击“创建房间”按钮；
   - 系统将在 1 秒内生成一个 6 位数字房间码并进入放映室。

   步骤二（同步观影测试）：
   - 在放映室内点击顶部或播放器中央的“选择本地视频”按钮，选取本机任意测试 MP4 视频；
   - 或点击“网络流媒体”图标，输入任意公开的 MP4/m3u8 视频 URL 进行播放；
   - 播放器底部的进度条拖拽、暂停、播放和音量调节均可正常操作。

   步骤三（屏幕共享测试）：
   - 点击播放器控制栏右侧的“投屏”图标；
   - 弹出投屏设置面板后，点击“开启屏幕共享”，即可看到系统桌面捕获推流状态。

   步骤四（语音与互动测试）：
   - 点击麦克风按钮可开启双向语音对讲；
   - 在右侧或底部输入框输入文字可发送实时弹幕。

3. 双实例联网测试（可选）：
   - 若贵方在两台测试机（或同一台机器开启两个窗口）分别运行 Eir；
   - 一端创建房间，另一端输入该 6 位房间码点击“加入”；
   - 即可直接观察到两端毫秒级视频同步对齐及实时文字弹幕互通。

4. 隐私与安全性：
   应用所有传输均基于 WebRTC 点对点加密，无任何广告，无云端留存。
   如有任何问题，欢迎随时联系开发者支持团队：support@norns.cc.cd
```

---

## 8. 提报完成与后续流程

1. **保存并提交**：逐项保存后，在提交概览页面确认各项均已显示绿勾，点击 **“提交到商店 (Submit to the Store)”**。
2. **审核周期**：微软合作伙伴中心通常在 **12 至 48 小时** 内完成自动化测试与人工认证。
3. **正式上架**：认证通过后，应用状态将转为“在应用商店中提供”，全球 Windows 用户即可在 Microsoft Store 直接搜索并一键安装。

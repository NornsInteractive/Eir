# Eir 应用商店上架与信息提报物料指南 (App Store Listing Kit)

本文档整理了发布 **Eir** 至各大应用市场（包括 **Google Play Console**、**Apple App Store**、**国内主流应用商店**（小米应用商店、华为应用市场、vivo、OPPO、腾讯应用宝、酷安）、**Microsoft Store / Flathub**）所需填报的全部中英文元数据、权限申明与合规材料。

您可以直接复制对应字段内容至应用商店后台。

---

## 目录
1. [基础元数据快速复制表](#1-基础元数据快速复制表)
2. [短描述与宣传文案](#2-短描述与宣传文案)
3. [完整应用描述（中文版 & 英文版）](#3-完整应用描述)
4. [搜索关键词与分类标签](#4-搜索关键词与分类标签)
5. [权限使用目的申明（应对审核必填）](#5-权限使用目的申明)
6. [年龄分级与问卷选项参考](#6-年龄分级与问卷选项参考)
7. [审核员测试账号与操作指引](#7-审核员测试账号与操作指引)
8. [视觉设计物料规格与文案策划](#8-视觉设计物料规格与文案策划)
9. [版本更新说明 (What's New)](#9-版本更新说明)

---

## 1. 基础元数据快速复制表

| 字段名称 | 中文填写内容 | 英文 / 国际填写内容 | 备注 / 字符限制 |
| :--- | :--- | :--- | :--- |
| **应用名称 (App Name)** | Eir | Eir | 30 字符内 |
| **应用副标题 (Subtitle)** | 异地同步观影与 60FPS 投屏 | Watch Together & 60FPS Screen Share | iOS 30 字符内 |
| **应用包名 (Package Name)** | `com.norns.eir` | `com.norns.eir` | 全局唯一标识符 |
| **开发者主体 (Developer)** | Norns Interactive | Norns Interactive | 组织主体 |
| **主分类 (Primary Category)** | 影音播放 / 娱乐 | Video Players & Editors / Entertainment | 视听影音类 |
| **次分类 (Secondary Category)** | 实用工具 / 社交 | Tools / Social | 协同联机类 |
| **官方网站 (Website)** | https://eir.norns.cc.cd | https://eir.norns.cc.cd | 官方主页 |
| **隐私政策链接 (Privacy Policy URL)** | https://eir.norns.cc.cd/privacy.html | https://eir.norns.cc.cd/privacy.html | **应用商店必填** |
| **技术支持链接 (Support URL)** | https://github.com/NornsInteractive/Eir/issues | https://github.com/NornsInteractive/Eir/issues | 问题反馈 |
| **联系邮箱 (Support Email)** | support@norns.cc.cd | support@norns.cc.cd | 审核与用户联络 |
| **版权信息 (Copyright)** | © 2026 Norns Interactive | © 2026 Norns Interactive | 版权所有 |
| **应用定价与内购 (Pricing)** | 免费（无内购、无订阅） | Free (No In-App Purchases, No Ads) | 纯净免费 |

---

## 2. 短描述与宣传文案

### Google Play 简短说明 (Short Description - 80 字符上限)
- **中文（共 36 字）**：  
  `跨平台异地同步观影与 60FPS 实时投屏放映室，毫秒级低延迟，纯 P2P 传输无广告。`
- **英文（共 77 字符）**：  
  `Synchronized co-watching and 60 FPS live screen casting with low-latency P2P.`

### Apple App Store 宣传文本 (Promotional Text - 170 字符上限)
- **中文**：  
  `Eir 是一款专注于跨平台同步观影与屏幕共享的轻量放映室。支持本地视频与流媒体毫秒级同步播放、60 FPS 极速投屏、双向语音对讲与即时弹幕。无需注册账号，点对点加密传输，随时与好友同屏共赏。`
- **英文**：  
  `Eir brings synchronized co-watching and 60 FPS screen casting across platforms. Enjoy millisecond-accurate sync for local & URL media, encrypted voice intercom, and live danmaku—with no registration and zero cloud media upload.`

### 国内应用商店一句话简介 (15 - 30 字符限制)
- **版本 A（推荐）**：`异地同步观影与 60FPS 实时投屏放映室`（23 字）
- **版本 B（突出功能）**：`跨平台同屏观影与屏幕共享协同工具`（18 字）
- **版本 C（突出纯粹）**：`轻量免登录的异地同步观影与投屏工具`（19 字）

---

## 3. 完整应用描述

### 3.1 中文版完整应用描述（适用于各商店详情页）

```markdown
Eir 是一款轻量、优雅且功能强大的跨平台异地同步观影与实时投屏工具。无论您与好友相隔多远，只需一个 6 位房间码，即可瞬间进入专属的私人放映室，共享视听盛宴。

【核心功能亮点】

1. 🎬 异地同步观影放映室
• 毫秒级进度同步：播放、暂停、进度拖拽双向实时对齐，体验顺畅如坐同席。
• 本地视频与网络流媒体双支持：支持播放手机本地视频文件（MP4、MKV、WebM 等主流格式）及网络流媒体链接。
• 好友缓冲自适应等候：网络波动导致一方缓冲时，系统自动协调等候，告别“一人看前面、一人在后面”的脱节尴尬。
• 播放列表循环与画面比例：支持顺序播放、单曲循环、列表循环，画面自适应 16:9、4:3、铺满与原始比例。

2. 🖥️ 60 FPS 极速低延迟投屏
• 高清流畅投屏：支持将手机屏幕、游戏画面或指定视窗以高达 60 FPS 实时推流至好友设备。
• 系统伴音直传：高品质音频同步传输，游戏开黑、设计协同、操作演示清晰呈现。
• 后台稳定推流：支持系统级前台服务保障，锁屏切后台不中断推流。

3. 🎙️ 语音对讲与氛围弹幕
• 双向语音连麦：内置 WebRTC 高清音频通话，观影同时随时吐槽畅聊，无需额外开启通话软件。
• 趣味全屏弹幕：支持彩色弹幕与即时文字互动，为主播与观众带来互动沉浸感。
• 游戏常驻胶囊：投屏状态下支持悬浮窗快捷展示好友互动，全屏游戏不遮挡视线。

4. 🔐 纯粹隐私与去中心化设计
• 零云端转存：本地媒体与投屏画面仅在您与好友设备之间通过 WebRTC P2P 点对点加密传输，绝不上传至任何中心化云端服务器或数据库。
• 免注册即开即用：无繁琐注册登录，无手机号或社交账号绑定要求，会话退出自动销毁。
• 纯净无广告：绝无第三方商业广告联盟与隐私行为追踪代码，还原纯粹观影体验。

5. 🌐 跨平台互联互通
全面适配 Android、iOS、Windows、macOS、Linux 以及现代 Web 浏览器，手机与电脑随时互联。

【适用场景】
• 异地恋情侣 / 好友同屏追剧、看电影、分享搞笑视频
• 游戏联机开黑直播与操作演示
• 远程协作、设计评审与跨设备演示

官网：https://eir.norns.cc.cd
技术支持：support@norns.cc.cd
```

---

### 3.2 英文版完整应用描述 (English Full Description)

```markdown
Eir is a modern, lightweight, and privacy-first cross-platform application designed for real-time synchronized co-watching and 60 FPS live screen casting. Connect with your friends anywhere in the world using a simple 6-digit room code and enjoy shared moments in your private theater.

KEY FEATURES:

1. Synchronized Co-Watching Theater
• Millisecond-Accurate Synchronization: Play, pause, and seek commands are kept in real-time lockstep between all members in the room.
• Local Media & Network Streams: Watch local video files (MP4, MKV, WebM, etc.) directly from your device storage, or stream external media URLs.
• Adaptive Buffering Coordination: Automatically pauses and waits if a peer encounters buffering delays, preventing desynchronization.
• Aspect Ratio & Playback Controls: Seamlessly toggle between 16:9, 4:3, Fill, and Fit modes with repeat and loop playlist controls.

2. 60 FPS Ultra-Low Latency Screen Casting
• Smooth Real-Time Streaming: Broadcast your device screen, gameplay, or specific app window at up to 60 FPS.
• System Audio Transmission: Crystal-clear direct audio streaming perfect for multiplayer gaming, presentations, and remote design reviews.
• Reliable Background Service: Robust Android foreground service ensures screen broadcasts continue smoothly even when multitasking.

3. Voice Intercom & Live Danmaku
• Built-in Two-Way Voice: High-fidelity WebRTC voice chat lets you talk and react in real-time without running separate voice software.
• Interactive Floating Danmaku: Send and view real-time comments across the screen for an engaging theater atmosphere.
• Broadcaster Chat Capsule: Optional floating overlay allows the broadcaster to see viewers' reactions while playing full-screen games.

4. Privacy by Design & Zero Cloud Media Storage
• True Peer-to-Peer (P2P): Media files and live screen frames are streamed directly between connected devices using standard DTLS-SRTP encryption. Nothing is ever uploaded, stored, or archived on centralized cloud servers.
• Account-Free & Instant: No registration, no login, and no email or phone number required.
• Completely Ad-Free: Zero third-party ad networks, zero analytics SDKs, and no tracking.

5. Cross-Platform Connectivity
Seamlessly connect across Android, iOS, Windows, macOS, Linux, and modern Web browsers.

Website: https://eir.norns.cc.cd
Support: support@norns.cc.cd
```

---

## 4. 搜索关键词与分类标签

### Apple App Store 关键词 (Keywords - 严格控制在 100 字符内，英文逗号分隔)
```text
同屏观影,异地追剧,一起看,屏幕共享,投屏,私密放映室,WebRTC,局域网投屏,弹幕,连麦,Watch Together,Screen Share
```
*(总长 93 字符，精准命中核心搜索词)*

### Google Play 标签分类 (Tags)
- **主类别**：Video Players & Editors（视频播放与编辑）
- **辅选标签**：
  - Media & Video（媒体与视频）
  - Video sharing（视频共享）
  - Entertainment（娱乐）
  - Tools（工具）

### 国内市场分类与标签
- **一级分类**：影音播放
- **二级分类**：视频播放器 / 投屏工具
- **标签推荐**：`同步观影`、`投屏`、`屏幕共享`、`异地恋`、`一起看`、`无广告`、`P2P`、`放映室`

---

## 5. 权限使用目的申明（应对审核必填）

应用商店（特别是 Google Play 与国内各大市场）对高敏权限审核极其严格，请直接使用以下规范化说明文本填报：

### 1. 麦克风权限 (`android.permission.RECORD_AUDIO` / `NSMicrophoneUsageDescription`)
- **中文申明**：  
  `用于在放映室和投屏直播中提供实时双向语音对讲与连麦通话功能。该权限仅在用户主动开启麦克风通话时使用，未开启语音时绝不调用，绝不录制或上传音频。`
- **英文申明 (iOS Info.plist)**：  
  `Eir uses the microphone to provide two-way real-time voice intercom during synchronized co-watching and screen sharing sessions when actively enabled by the user.`

### 2. 屏幕捕获与录制权限 (`MEDIA_PROJECTION`)
- **中文申明**：  
  `用于在用户主动发起投屏共享时捕获屏幕画面和应用内容，以极速低延迟形式实时推送给同房间的好友。应用不会将屏幕内容保存至本地或上传至云端服务器。`
- **英文申明**：  
  `Required solely to capture screen frames when the user actively initiates a live screen share session to stream to room members via direct P2P.`

### 3. 本地音视频媒体访问权限 (`READ_MEDIA_VIDEO` / `READ_EXTERNAL_STORAGE`)
- **中文申明**：  
  `用于供系统文件选择器读取用户自主选取的本地音视频文件，以便在放映室中与好友同步播放。应用绝不擅自扫描或读取未选取的其他私有文件。`
- **英文申明**：  
  `Required for the system file picker to load user-selected local video and audio files for synchronized in-room playback.`

### 4. 前台服务权限 (`FOREGROUND_SERVICE_MEDIA_PROJECTION` & `FOREGROUND_SERVICE_MEDIA_PLAYBACK`)
- **中文申明**：  
  `用于在 Android 设备上进行屏幕推流或音视频同步播放时，保证应用切换至后台或全屏游戏时传输连接不中断，并在系统通知栏常驻提供控制面板与快捷停止功能。`
- **英文申明**：  
  `Ensures continuous screen broadcasting and audio synchronization while multitasking or gaming, with a persistent notification control.`

### 5. 悬浮窗 / 悬浮组件权限 (`SYSTEM_ALERT_WINDOW`)
- **中文申明**：  
  `用于主播在全屏运行游戏或其他应用时，展示轻量半透明的观众互动弹幕胶囊，方便主播随时查看好友发来的消息与反应（可在设置中随时关闭）。`
- **英文申明**：  
  `Displays a lightweight, non-intrusive floating chat capsule during full-screen broadcasts so the broadcaster can see peer comments without leaving the game.`

---

## 6. 年龄分级与问卷选项参考

在 Google Play Console（IARC 问卷）或 App Store Connect 年龄分级问卷中，按如下选项勾选即可获评**适宜全年龄或 12+**：

1. **暴力、血腥内容**：否 (No)
2. **色情、裸露或性暗示**：否 (No)
3. **语言粗俗或脏话**：否 (No)
4. **受管制药物、酒精或烟草**：否 (No)
5. **赌博或博彩模拟**：否 (No)
6. **是否允许用户之间互动或交换内容**：**是 (Yes)**  
   *（说明：应用提供基于点对点 WebRTC 的房间音视频与文字聊天互动）*
7. **是否向第三方分享用户的精确物理位置**：**否 (No)**
8. **是否包含应用内购买或充值**：**否 (No)**

- **最终分级结果参考**：
  - Google Play / IARC：PEGI 12 / Everyone 10+（因支持不受管制的网络实时点对点通信交互）
  - Apple App Store：12+（轻微偶发的网络通信互动）
  - 国内应用市场适龄提示：**12+ 岁**

---

## 7. 审核员测试账号与操作指引

在应用商店后台的“审核备注 (App Review Notes)”中填入以下内容，助审核员快速通过审核：

```text
致应用审核团队：

Eir 是一款去中心化、免账户体系的跨平台同步观影与屏幕共享工具。应用无需注册，无需提供用户名或密码即可体验所有核心功能。

【推荐审核测试步骤】：
1. 启动应用后直接进入主大厅，无需登录。
2. 点击“创建房间”按钮，系统将立即生成一个 6 位数字房间码（例如 839201）并进入放映室。
3. 若需测试双端互联：
   - 可在另一台设备（或在电脑浏览器访问 https://eir.norns.cc.cd）启动 Eir。
   - 在加入房间框中输入上述 6 位房间码，点击“加入”，两端即可瞬间完成点对点连接。
4. 放映室测试：
   - 点击“添加本地视频”或选择测试演示视频，即可体验两端毫秒级同步播放、暂停与进度拖拽。
5. 屏幕共享测试：
   - 在控制栏点击“投屏”图标，授予系统屏幕录制权限，同房间观众即可实时观看 60 FPS 流畅画面。
6. 双向语音测试：
   - 点击麦克风图标开启通话，即可体验实时低延迟对讲。

应用内所有连接均采用 WebRTC 端到端加密，本地媒体与投屏内容绝不上云。
如有任何疑问，请随时联系：support@norns.cc.cd
```

---

## 8. 视觉设计物料规格与文案策划

### 8.1 应用图标 (App Icon)
- **规格**：`512 x 512 像素`，PNG 格式，32-bit，无透明度，无圆角（应用商店会自动切圆角）。
- **设计风格**：深色背景（`#0a0b10`），中央为 Eir 经典液态玻璃质感几何“E”字徽标，紫蓝渐变微光。

### 8.2 Google Play 置顶大图 (Feature Graphic)
- **规格**：`1024 x 500 像素`，PNG / JPEG 格式。
- **文案规划**：
  - 主标题：`Eir · 异地同屏放映室`
  - 副标题：`60 FPS 极速投屏 · 毫秒级同步观影 · 纯粹免登录`
  - 视觉背景：高质感暗夜深空与液态玻璃视窗构图，展示跨端同屏画面。

### 8.3 手机端截屏规划 (5 张推荐版面)

| 序号 | 截屏展示场景 | 顶部推荐配文（8-14 字） | 详细说明 |
| :---: | :--- | :--- | :--- |
| **第 1 张** | 专属放映室主界面（观影同屏） | **异地同步观影 · 毫秒级对齐** | 展示视频画面、进度条、双向同步状态及彩色弹幕互动效果。 |
| **第 2 张** | 60 FPS 极速屏幕共享 | **高清流畅投屏 · 伴音直传** | 展示正在直播的手游或桌面视窗，以及悬浮观众连接胶囊。 |
| **第 3 张** | 双向语音与即时连麦 | **实时双向对讲 · 边看边聊** | 突出低延迟语音连麦状态栏与清晰的麦克风控制面板。 |
| **第 4 张** | 极简大厅与 6 位房间码 | **一键创建加入 · 免注册登录** | 展示优雅的大厅玻璃拟态卡片，6 位房间码一键快速连入。 |
| **第 5 张** | 跨端互通与全平台支持 | **全平台互联 · 纯粹无广告** | 展示手机、电脑与 Web 端同屏联动，强调 P2P 隐私保护。 |

---

## 9. 版本更新说明 (What's New)

用于新版本发布时填入应用商店的“新版本特性”输入框：

### 中文版本更新日志 (v1.0.40)
```text
【v1.0.40 版本新特性】
1. 🔐 开发者身份合规认证升级：完成 Android 官方开发者身份认证（ADI）凭证资产规范化植入与签名核验。
2. 🌐 全面多语言国际化重构：彻底消除全部核心视图中的硬编码，新增 65+ 项国际化词条，中英文自适应无缝切换。
3. 🖥️ 投屏控制台双语升级：推流控制、投屏码管理、观众连麦状态全量支持中英双语。
4. 🎬 观影体验细节优化：画面比例自适应调整、缓冲协调提示与房间解散逻辑全面对齐。
5. ⚙️ 设置与网络诊断增强：新增多语言 STUN/TURN 服务器连通性探测与清晰的状态反馈。
6. 🛡️ 隐私与安全性提升：健全隐私政策指引，严守端到端加密与零云端留存承诺。
```

### English Release Notes (v1.0.40)
```text
[What's New in v1.0.40]
1. 🔐 Official Android Developer Identity (ADI) verification assets integrated and verified.
2. 🌐 Full localization overhaul across all core views with 65+ new internationalized strings.
3. 🖥️ Bi-lingual screen casting console with localized controls, stream codes, and viewer states.
4. 🎬 Enhanced co-watching experience with adaptive aspect ratios and buffer sync coordination.
5. ⚙️ Diagnostic and NAT traversal upgrades with real-time multi-language STUN/TURN probing.
6. 🛡️ Updated privacy policies and hardened end-to-end P2P encryption standards.
```

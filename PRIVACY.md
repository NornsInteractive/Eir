# Eir Privacy Policy / 隐私政策

> **Language / 语言切换**: [🇨🇳 简体中文 (Chinese)](#-eir-隐私政策-中文版) | [🇬🇧 English](#-eir-privacy-policy-english-version)  
> **Official Website**: [https://eir.norns.cc.cd](https://eir.norns.cc.cd) · **Web Mirror**: [https://eir.norns.cc.cd/privacy.html](https://eir.norns.cc.cd/privacy.html)  
> **Repository**: [https://github.com/NornsInteractive/Eir](https://github.com/NornsInteractive/Eir) · **Contact**: support@norns.cc.cd  

---

## 🇨🇳 Eir 隐私政策 (中文版)

**生效日期**：2026 年 11 月 16 日  
**最近更新日期**：2026 年 11 月 16 日  
**开发者/运营主体**：Norns Interactive  
**应用名称**：Eir（异地同屏观影与实时投屏）  
**应用包名**：`com.norns.eir`  

### 核心设计原则
Eir 严格遵循**“数据最小化”、“零云端留存”与“端到端点对点（P2P）传输”**原则。应用采用免账号设计，无需注册登录，所有本地媒体播放与屏幕共享均在您与好友设备之间建立端到端加密通道传输，绝不在云端服务器保留或备份。

---

### 一、我们如何收集与使用您的信息

Eir 采用去中心化、免账户体系架构，**我们不要求您注册账号、绑定手机号码、提供真实姓名、身份证件号或支付信息**。在您使用本应用的过程中：

1. **本地音视频媒体与文件**：当您在放映室中选择播放本地音视频时，仅通过系统文件选择器读取您主动选取的本地文件数据流。**音视频文件绝不会上传至任何中心化云端服务器或数据库**，同屏播放时仅通过 WebRTC / 本地局域网 P2P 加密通道在两端直传。
2. **实时屏幕投屏数据**：当您作为主播主动开启投屏共享时，系统将捕获您指定的屏幕、应用视窗或伴音，并在本地编码后直接通过 WebRTC P2P 通道发送给房间内好友。**我们绝不对您的屏幕内容进行服务端录制、截图、抓取或分析**，投屏结束即刻销毁全部临时缓冲区。
3. **双向语音连麦与对讲**：当您主动开启房间对讲麦克风时，音频经由国际标准 DTLS-SRTP 协议点对点加密传输。**我们不收集、不录制亦不转写您的任何语音通讯**。
4. **房间信令与临时交互数据**：为建立 P2P 链路，边缘信令服务（`wss://eir.norns.cc.cd/ws`）临时交换 6 位数字房间码、会话随机 UUID 及 WebRTC SDP/ICE 候选地址。此类信令仅存在于临时内存中，房间退出或关闭后**立即自动销毁**。弹幕与文字聊天在退出房间后自动清空，不存云端。
5. **坚决不收集的信息**：
   - ❌ 绝无商业广告联盟 SDK
   - ❌ 绝无用户行为分析与画像追踪 SDK
   - ❌ 绝不读取设备 IMEI、IMSI、MAC 地址或硬件序列号
   - ❌ 绝不索取 GPS 定位权限

---

### 二、设备权限申请与使用规则

| 权限名称 / 标识 | 对应平台 | 使用场景与业务目的 | 必要性 |
| :--- | :--- | :--- | :--- |
| **麦克风权限**<br>`RECORD_AUDIO` | Android / iOS / 桌面 | 仅在您主动开启放映室连麦或投屏双向对讲时使用。未开启语音时绝不调用。 | 否（仅语音依赖） |
| **屏幕录制 / 投屏权限**<br>`MEDIA_PROJECTION` | Android / 桌面 / Web | 仅在您主动发起屏幕共享时由操作系统弹出系统级确认框，用于向好友实时传输屏幕。 | 否（仅投屏主播依赖） |
| **媒体与视频访问权限**<br>`READ_MEDIA_VIDEO` / `READ_EXTERNAL_STORAGE` | Android / 移动端 | 仅供系统文件选择器读取您主动选择的本地视频文件。 | 否（仅本地观影依赖） |
| **网络通信权限**<br>`INTERNET` / `ACCESS_NETWORK_STATE` | 全平台 | 连接信令服务与建立 WebRTC P2P 点对点传输，同步播放进度与传输流媒体。 | 是（核心功能） |
| **前台服务权限**<br>`FOREGROUND_SERVICE_MEDIA_PROJECTION` | Android | 投屏过程中切换至游戏或后台应用时保持推流稳定不中断，并在状态栏常驻提示。 | 否（仅后台投屏依赖） |
| **悬浮窗权限**<br>`SYSTEM_ALERT_WINDOW` | Android | 主播全屏游戏时展示半透明弹幕聊天胶囊，方便主播查看观众反应（可在设置中关闭）。 | 否 |

---

### 三、第三方服务与数据安全

1. **零第三方广告与追踪 SDK**：Eir 不集成任何第三方商业广告平台或分析 SDK。
2. **STUN / TURN 穿透中继集群**：在复杂双重对称 NAT 网络下无法直连时，系统经由中继节点（`ip.norns.cc.cd`）中转加密二进制包。所有数据均受 WebRTC DTLS-SRTP 端到端加密保护，中继节点无法解密或窥探视听内容。
3. **用户权利与控制权**：无需注册，随时可在系统设置中关闭权限；可在应用内“设置 -> 存储与缓存”一键清空房间历史与本地偏好；卸载应用即可自动彻底删除本地沙盒数据。

---

## 🇬🇧 Eir Privacy Policy (English Version)

**Effective Date**: November 16, 2026  
**Last Updated**: November 16, 2026  
**Developer / Operating Entity**: Norns Interactive  
**Application Name**: Eir (Synchronized Cinema & Live Screen Share)  
**Package Name / Application ID**: `com.norns.eir`  

### Core Architecture & Privacy Principles
Eir is built upon the fundamental pillars of **"Data Minimization", "Zero Cloud Storage of Media", and "End-to-End Peer-to-Peer (P2P) Transmission"**. Eir is an account-free application requiring no registration or personal profile. All media streaming and screen casting take place directly between you and your peers over encrypted P2P connections without touching cloud storage.

---

### 1. Information We Collect and Process

1. **Local Media & Video Files**: When selecting local videos in a co-watching room, Eir reads only the files you explicitly pick via system dialogues. **Your media files are NEVER uploaded to any central cloud server or database.** Streaming occurs strictly peer-to-peer between devices.
2. **Live Screen Sharing Streams**: When initiating screen sharing as a broadcaster, screen capture frames are encoded on your device and transmitted directly to room members via WebRTC. **We do not record, intercept, or snapshot your screen on any server.**
3. **Two-Way Voice Intercom**: When you unmute in a room, audio is transmitted peer-to-peer using standard DTLS-SRTP encryption. We never record, transcribe, or retain your audio communications.
4. **Ephemeral Signaling Data**: To negotiate direct P2P connections, our edge signaling server (`wss://eir.norns.cc.cd/ws`) routes ephemeral 6-digit room codes, session UUIDs, and WebRTC SDP/ICE candidate packets. **These exist only in volatile server memory and are wiped immediately upon room exit or disconnect.** In-room chat messages are discarded upon leaving.
5. **What We NEVER Collect**:
   - ❌ No third-party ad networks (e.g. AdMob)
   - ❌ No behavioral analytics or profiling SDKs
   - ❌ No device IMEI, IMSI, or MAC address tracking
   - ❌ No GPS or location requests

---

### 2. Device Permissions and Usage

| Permission | Platform | Business Purpose & Context | Required? |
| :--- | :--- | :--- | :--- |
| **Microphone**<br>`RECORD_AUDIO` | Android / iOS / Desktop | Used solely when you actively unmute to talk in co-watching rooms or screen sharing sessions. Never accessed when muted. | No (Optional) |
| **Screen Capture**<br>`MEDIA_PROJECTION` | Android / Desktop / Web | Requested via OS prompt only when you choose to share your screen with peers. | No (Optional) |
| **Media Access**<br>`READ_MEDIA_VIDEO` | Android / Mobile | Used solely by the file picker when you choose a local video file from storage to watch together. | No (Optional) |
| **Network Access**<br>`INTERNET` | All Platforms | Required to connect to signaling and establish direct P2P WebRTC data channels and video streams. | Yes (Core Feature) |
| **Foreground Service**<br>`FOREGROUND_SERVICE` | Android | Maintains background screen streaming while playing games or multitasking, displaying a persistent notification. | No (Only during broadcast) |
| **Overlay**<br>`SYSTEM_ALERT_WINDOW` | Android | Displays a floating chat capsule during full-screen games so broadcasters can view peer reactions (can be toggled in Settings). | No |

---

### 3. Third-Party Services & User Rights

- **Zero Commercial Trackers**: No third-party tracking, analytics, or monetization SDKs.
- **Relay Encryption (STUN/TURN)**: When direct P2P is blocked by firewalls, traffic routed through `ip.norns.cc.cd` remains encrypted end-to-end via DTLS-SRTP. The relay server cannot decrypt or inspect payloads.
- **Data Deletion & Rights**: No account is ever created. Local cache and room history can be cleared in one click inside **Settings -> Storage & Cache**. Uninstalling the app completely wipes all sandbox data.

---

## 📬 Contact & Support / 联系我们

- **Organization / 开发组织**: Norns Interactive  
- **Official Website / 官方网站**: [https://norns.cc.cd](https://norns.cc.cd)  
- **GitHub Repository / 仓库**: [https://github.com/NornsInteractive/Eir](https://github.com/NornsInteractive/Eir)  
- **Privacy Page on GitHub**: [https://github.com/NornsInteractive/Eir/blob/main/PRIVACY.md](https://github.com/NornsInteractive/Eir/blob/main/PRIVACY.md)  
- **Email / 电子邮箱**: [support@norns.cc.cd](mailto:support@norns.cc.cd)  

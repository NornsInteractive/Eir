# 最新修复双端业务验收环境就绪报告（CURRENT-FIXED-ACCEPTANCE-ENV）

- **报告生成时间**：2026-11-18 20:25 +08:00
- **执行会话**：`70aef10f-2cc5-4efb-9d8b-d102153531c2`（固定 `gemini-3.8-flash-high/high`）
- **当前阶段**：双端业务验收环境就绪（**明确暂不发布**）
- **规范遵守**：遵循 `AGENTS.md`，使用 `liquid_glass_widgets` 规范，不修改业务核心逻辑与 UI 界面，本地仅维护单份目标版本 APK，不清除用户数据，不调整模拟器图形驱动。

---

## 一、可追溯新产物指纹与新旧版本比对

本次重新构建完整纳入了如下已落地的最新修复与接线：
1. **相对快进 UI 接线**（`lib/views/cinema_view.dart` `_seekRelative` 委托 `RoomSession.seekRelative`，不再使用本地过期提交锚点手算 clamp）；
2. **成员列表可访问语义最小修复**（`lib/apple_glass.dart` 暴露 `semanticLabel`，`cinema_view.dart` 消除成员行误暴露为 `role=button`，保持独立按钮名称与 tap 动作）；
3. **本地信令地址兼容修复**（`lib/app_settings.dart` 消除本地 `ws://127.0.0.1` 等地址被静默迁移并覆盖为生产地址的缺陷）；
4. **Native ABI 对齐**（`libtailcat.so` 全架构导出 `TailcatFree` 释放契约）；
5. **更新下载校验**（接入 `expectedSha256` 与 `expectedSize`）；
6. **网络看板 UI 适配**（`ScreenShareService` 统计指标 nullable 适配）。

### 1. 版本与产物哈希对比表（杜绝旧包冒充）

| 产物项 | 规格 / 属性 | 旧产物记录（不含本轮修复） | **本次最新产物（已包含全部新修复）** |
| :--- | :--- | :--- | :--- |
| **版本名称 (Version Name)** | 元数据 | `1.0.40` | `1.0.40` |
| **版本代号 (Version Code)** | 元数据 | `41` (`1.0.40+41`) | `41` (`1.0.40+41`) |
| **应用包名 (Application ID)** | 元数据 | `com.norns.eir` | `com.norns.eir` |
| **Android APK 文件路径** | 本地单份产物 | `eir-v1.0.40.apk` | [eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk) |
| **Android APK 构建时间** | 本地编译时间 | 2026-11-18 14:18:55 | **2026-11-18 20:19:46 +08:00** |
| **Android APK 大小** | 字节数 | 183,345,864 字节 | **183,345,864 字节** |
| **Android APK SHA-256** | 完整文件指纹 | `e40acbd8a0b467d1d04c7fb84cf4a4be59d9636717f95027bb3fe8f85e8f861e` | `e4563c9b6525f51d0ca655ec46abedb4d23c168cfae9b0f657c94b243901b8a5` |
| **Web Release 输出路径** | 目录 | `build/web/` | [build/web/](file:///workspace/projects/Eir/build/web/) |
| **Web 构建完成时间** | 本地编译时间 | 2026-11-18 14:19:57 | **2026-11-18 20:17:43 +08:00** |
| **Web `main.dart.js` 大小** | 字节数 | 4.3 MB | **4.3 MB** (~4,496,547 字节) |
| **Web `main.dart.js` SHA-256** | 脚本核心指纹 | `cf87359f82e50158d181a937232aafc86dc0ce1f32199af3d8b67afcccbb9928` | `e81574b5add2185eb76b6f571b2eda6bda84b6e7f0bc48cb831f9ed8f12135fb` |

---

## 二、Android 设备安装与环境状态

### 1. 单份本地产物保留规则
- 构建前已根据 `AGENTS.md` 规则执行 `rm -f eir-v*.apk` 清除全部历史安装包；
- 本地根目录仅保留唯一目标版本产物：[eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk)。

### 2. ADB 设备覆盖安装（保留数据）
- **目标设备**：`172.17.0.1:14251` (Android 14, x86_64, `sdk_gphone64_x86_64`)；
- **安装指令**：`adb -s 172.17.0.1:14251 install -r ./eir-v1.0.40.apk`；
- **安装结果**：`Performing Streamed Install` -> `Success`；
- **数据保留**：采用 `-r` 保留原有用户配置与 SharedPreferences 数据覆盖升级，未执行 `pm clear`；
- **设备内状态核实**：
  ```
  dumpsys package com.norns.eir | grep -E 'versionCode|versionName'
  versionCode=41 minSdk=24 targetSdk=36
  versionName=1.0.40
  ```
- **原生库 ABI 校验**：实测解压 APK 内 `lib/x86_64/libtailcat.so`，`nm -D` 提取确认导出符号 `TailcatFree`。
- **端口反向代理映射**：`adb -s 172.17.0.1:14251 reverse tcp:8080 tcp:8080` 状态激活，设备内 App 可直接通过 `http://127.0.0.1:8080` 连通宿主机统一服务。

---

## 三、Web 与信令服务常驻运行机制

### 1. 脱离 CLI 生命周期的常驻方案
- **常驻托管**：Linux 独立后台守护会话 `tmux`（会话名 `eir-server`）；
- **主进程**：`dart run server/signaling_server.dart 8080 :: build/web`（PID: 269719，父进程 PID 294，系统 init 级守护）；
- **服务日志**：`/workspace/projects/Eir/server/server.log`；
- **生命周期独立**：本进程与 Antigravity CLI 进程组彻底解耦，CLI 退出、报错或重启均**不会终止**该服务，端口 `8080` 持续常驻监听。

### 2. 服务内容即时更新核实
实测通过 HTTP 访问拉取当前正在服务的 `main.dart.js`：
```bash
curl -s http://127.0.0.1:8080/main.dart.js | sha256sum
e81574b5add2185eb76b6f571b2eda6bda84b6e7f0bc48cb831f9ed8f12135fb  -
```
证明常驻服务已实时无缝对外提供本次包含最新修复的 Web 产物。

### 3. 多网络与协议持续可访问地址
- **监听协议**：`InternetAddress.anyIPv6` (`::`) 双栈监听，覆盖 IPv4 与 IPv6。
- **推荐安全上下文地址（全功能可用）**：
  - 本机 IPv4 回环：`http://127.0.0.1:8080/`
  - 本机 IPv6 回环：`http://[::1]:8080/`
- **局域网 / 专用网可访问地址**：
  - 局域网 IPv4：`http://192.168.1.106:8080/`
  - 局域网 IPv4：`http://192.168.1.145:8080/`
  - Tailscale 专网：`http://100.86.170.61:8080/`
  - 公网 IPv6：`http://[240e:379:8e8d:b000:aaa1:59ff:fed6:5a7c]:8080/`
- **WebSocket 统一信令端点**：`ws://<host>:8080/ws`

---

## 四、安全上下文 (Secure Context) 边界与测试指引

> [!IMPORTANT]
> **关于 COOP/COEP 与浏览器安全上下文的精确区分：**
> 1. **COOP/COEP 仅开启跨域隔离**：响应头中的 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: credentialless` 仅用于解锁 `SharedArrayBuffer` 高性能特性，**绝对不会将普通的非加密 HTTP 判定为可信安全上下文**。
> 2. **用户当前测试不要求配置证书**：本阶段为内部联调与业务验收，不强求配置 SSL/TLS 证书。

### 访问入口特性对比：

| 访问入口 / Origin | 浏览器安全上下文认定 | 影响的功能项 | 验收测试建议 |
| :--- | :--- | :--- | :--- |
| **本机回环** (`localhost` / `127.0.0.1` / `[::1]`) | **天然安全上下文** (Potentially Trustworthy Origin) | 完整支持：WebRTC 音视频对讲、`getDisplayMedia` 投屏推流、Service Worker 媒体流缓存分块均可无阻碍调用。 | **首选 Web 验收入口**。推荐在宿主机浏览器直接打开 `http://127.0.0.1:8080/` 进行全功能联合验收。 |
| **局域网 IP / 公网 IPv6 / 域名 (纯 HTTP)** | **非安全上下文** (Not a Secure Context) | 受限功能：现代浏览器（Chrome/Edge/Firefox 等）在非安全上下文下会**强制禁用** `getDisplayMedia`（投屏）、`navigator.serviceWorker` 及摄像头/麦克风权限。普通文本互动与房间信令连接正常。 | 若需使用外部设备或跨机通过 HTTP 进行投屏/音视频验收，可通过 Chrome 实验参数 `--unsafely-treat-insecure-origin-as-secure=http://<IP>:8080` 启动浏览器测试，或通过反向代理配置 HTTPS。 |
| **Android 端 (APK 安装)** | **原生沙盒与应用权限控制** | 原生 WebRTC、摄像头、麦克风及系统投屏权限通过 Android 权限清单受管，不依赖浏览器安全上下文机制。 | 配合 `adb reverse tcp:8080 tcp:8080`，可直接通过 `127.0.0.1:8080` 与宿主机信令无缝通信。 |

---

## 五、真实限制声明 (Non-Exemptions)

> [!IMPORTANT]
> **构建成功、安装成功与服务启动不等于完整业务功能验收通过。**

真实存在的环境与功能限制说明如下：
1. **模拟器硬件限制**：
   - 当前已连接的 ADB 目标 `172.17.0.1:14251` 为 Android x86_64 虚拟设备，缺少物理摄像头及部分 OpenGL ES 扩展，受限于虚拟驱动，图形与视频硬件解码可能出现黑屏或降级提示（沿用既有模拟器图形验收豁免，不把豁免记作修复）。
2. **多端实际业务流转待联合回归**：
   - 本阶段完成产物构建、新旧哈希隔离与双端服务部署；Android 客户端与 Web 浏览器之间的真实进房、URL/本地片源同步播放、自然下一条切集及语音通话，仍需由后续验收流程开展真实联调。
3. **未构建桌面/iOS 端产物**：
   - 本阶段根据指令限定准备 Android 与 Web 双端验收环境，未构建 Windows/macOS/iOS 发布包。
4. **发布授权约束**：
   - 本阶段为双端业务验收环境准备，**未向任何应用商店、GitHub Releases 或 Yggdrasil 平台执行发布推送**。

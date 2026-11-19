# Android 与 Web 双端业务验收环境准备报告

- **报告生成日期**：2026-11-18
- **执行会话**：`70aef10f-2cc5-4efb-9d8b-d102153531c2` (固定 `gemini-3.8-flash-high/high`)
- **当前阶段**：双端业务验收环境准备（**明确暂不发布**）
- **规范遵守**：遵循 `AGENTS.md`，使用 `liquid_glass_widgets` 规范，不修改业务核心逻辑与 UI 界面，仅维护单份本地目标版本 APK。

---

## 一、实际版本信息与构建可追溯指纹

### 1. 版本号
- **版本名称 (Version Name)**：`1.0.40`
- **版本代号 (Version Code)**：`41` (`1.0.40+41`)
- **应用包名 (Application ID)**：`com.norns.eir`

### 2. 源码与构建时间追溯指纹
- **Git 基线 Commit**：`1db9aa670ceff2ab80f3502f3664ee3e76f4c5fc` (`origin/main`)
- **原生库构建完成时间**：`2026-11-18 14:10:35 +08:00`
  - Android `x86_64` / `arm64-v8a`：通过 Android NDK r27 编译，均含 `TailcatFree` 导出符号（SHA256 与符号经 `nm -D` 验证）。
- **Android APK 构建完成时间**：`2026-11-18 14:18:55 +08:00`
  - APK 文件大小：`183,345,864 字节` (~174.85 MB)
  - APK SHA-256：`e40acbd8a0b467d1d04c7fb84cf4a4be59d9636717f95027bb3fe8f85e8f861e`
- **Web Release 构建完成时间**：`2026-11-18 14:19:57 +08:00`
  - `build/web/version.json`：`{"app_name":"eir","version":"1.0.40","build_number":"41","package_name":"eir"}`
  - `build/web/main.dart.js`：`4.3 MB`

---

## 二、Android 产物与设备安装

### 1. 产物规格与单份保留
- **本地唯一样本路径**：[eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk)
- **构建输出路径**：`build/app/outputs/flutter-apk/app-release.apk`
- **规则执行**：构建前已清理全部历史安装包（`rm -f eir-v*.apk`），本地仅保留当前目标版本的单份产物。

### 2. ADB 设备安装目标
- **目标设备**：`172.17.0.1:14251` (Android 14, x86_64, `sdk_gphone64_x86_64`)
- **安装指令**：`adb -s 172.17.0.1:14251 install -r eir-v1.0.40.apk`
- **安装状态**：`Success`（保留既有用户配置与数据覆盖安装，`dumpsys` 确认 `versionCode=41`、`versionName=1.0.40`）
- **端口映射**：执行 `adb reverse tcp:8080 tcp:8080`，设备内应用可直接通过 `http://127.0.0.1:8080` 连通本机。

---

## 三、Web 产物与服务常驻运行

### 1. Web Release 产物
- **输出目录**：[build/web/](file:///workspace/projects/Eir/build/web/)
- **关键资源**：
  - `index.html` (现代液态玻璃微质感 Web 视窗)
  - `main.dart.js` (4.3 MB，已完成生产构建)
  - `eir_media_bridge.js` & `eir_media_sw.js` (本地媒体分块与 Service Worker P2P 桥接)
  - `version.json` (版本追踪元数据)

### 2. 服务常驻机制（脱离 CLI 生命周期）
针对前期“CLI 退出时清理 Daemon Task”的问题，当前服务已改为通过 Linux 独立守护会话托管：
- **常驻管理器**：`tmux` 专属后台会话 `eir-server`
- **常驻进程**：`dartvm ... server/signaling_server.dart 8080 :: build/web`（PID: 269719）
- **服务日志重定向**：`/workspace/projects/Eir/server/server.log`
- **生命周期保障**：会话与进程直接挂载在系统后台 `tmux` 服务上，**在本次 Antigravity CLI 退出、重启或断开后依然持续常驻**，确保已交接的 8080 端口稳定可用。

### 3. 多协议访问地址
- **监听绑定**：`InternetAddress.anyIPv6` (`::`)，端口 `8080`（双栈支持 IPv4 与 IPv6）
- **实测可用地址**：
  - **本机回环**：
    - IPv4: `http://127.0.0.1:8080/`
    - IPv6: `http://[::1]:8080/`
  - **局域网 IPv4**：
    - `http://192.168.1.106:8080/`
    - `http://192.168.1.145:8080/`
  - **Tailscale 虚拟专网**：
    - `http://100.86.170.61:8080/`
  - **公网 IPv6**：
    - `http://[240e:379:8e8d:b000:aaa1:59ff:fed6:5a7c]:8080/`
  - **WebSocket 信令直连端点**：`ws://<host>:8080/ws`

---

## 四、安全上下文 (Secure Context) 边界与真实限制说明

> [!IMPORTANT]
> **关于 COOP/COEP 与浏览器安全上下文的精确区分：**
> - **COOP/COEP 仅开启跨域隔离**：响应头中的 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: credentialless` 是为了在隔离环境下解锁高性能计算与 `SharedArrayBuffer`，**绝对不会将普通的非加密 HTTP 判定为可信安全上下文**。
> - **用户当前阶段测试不要求配置证书**：本阶段为纯内部业务验收与联调，不强求接入 SSL/TLS 证书。

### 真实访问限制对比：

| 访问途径 / Origin | 浏览器安全上下文认定 | 影响的功能项 | 验收建议与适配方案 |
| :--- | :--- | :--- | :--- |
| **本机回环** (`localhost` / `127.0.0.1` / `[::1]`) | **天然安全上下文** (Potentially Trustworthy Origin) | 浏览器可提供 WebRTC、`getDisplayMedia` 和 Service Worker；实际仍受浏览器实现、用户授权、系统捕获源及设备能力限制，需逐项验收。 | **推荐验收入口**。Web 端测试直接在宿主机浏览器打开 `http://127.0.0.1:8080/` 验收全功能。 |
| **局域网 IP / 公网 IPv6 / 域名 (纯 HTTP)** | **非安全上下文** (Not a Secure Context) | 受限功能：现代浏览器（Chrome/Edge/Firefox 等）在非安全上下文下会**强制禁用** `getDisplayMedia`（投屏推流）、`navigator.serviceWorker` 以及摄像头/麦克风权限。普通信令通信与纯文字互动正常。 | 若需使用外部设备或跨机通过 HTTP 进行投屏/音视频验收，可通过 Chrome 实验性标志 `--unsafely-treat-insecure-origin-as-secure=http://<IP>:8080` 启动浏览器测试，或通过反向代理配置 HTTPS。 |
| **Android 端 (APK 安装)** | **受原生沙盒与应用权限控制** | 原生 WebRTC、摄像头、麦克风及系统投屏权限通过 Android 权限清单受管，不依赖浏览器安全上下文机制。 | 配合 `adb reverse tcp:8080 tcp:8080`，可直接通过 `127.0.0.1:8080` 与宿主机信令无缝通信。 |

---

## 五、源码与原生库 (Native FFI) 契约对应情况

为解决旧签入二进制缺失 `TailcatFree` 导出符号、无法证明新 FFI 内存释放契约生效的问题，本轮已完成下列目标的原生库重建与校验；不代表所有平台均已重建：

1. **导出符号适配**：
   - 源码 `native/tailcat/tailcat_bridge.go` 与 `libtailcat.h` 已明确导出：
     ```c
     extern void TailcatFree(void* ptr);
     ```
   - 对应 Dart FFI `lib/core/transport/tailcat_ffi.dart` 中使用 `TailcatFree` 专职释放 Go 侧由 `C.CString`/`C.CBytes` 分配的内存。
2. **多目标重构与打包实证**：
   - **Android `x86_64`**：通过 NDK r27 编译为 `android/app/src/main/jniLibs/x86_64/libtailcat.so`；经 `nm -D` 提取并验证包含 `TailcatFree`；已真实打包进 `eir-v1.0.40.apk`。
   - **Android `arm64-v8a`**：通过 NDK r27 编译为 `android/app/src/main/jniLibs/arm64-v8a/libtailcat.so`；经 `nm -D` 提取并验证包含 `TailcatFree`；已真实打包进 `eir-v1.0.40.apk`。
   - **Linux Desktop**：通过 host Go 编译为 `native/tailcat/libtailcat.so` 与 `./libtailcat.so`，经 `nm -D` 验证包含 `TailcatFree`。
3. **一致性结论**：当前 APK 与本地运行环境中的 `libtailcat.so` 均严格匹配本轮最新 ABI，消除了旧库缺少 `TailcatFree` 抛出 `UnsupportedError` 的缺陷隐患。

---

## 六、真实限制与验收声明 (Non-Exemptions)

> [!IMPORTANT]
> **构建成功、安装成功与启动成功不等于完整业务功能验收通过。**

真实存在的环境与功能限制说明如下：
1. **模拟器硬件限制**：
   - 当前已连接的 ADB 目标 `172.17.0.1:14251` 为 Android x86_64 虚拟设备，缺少真实硬件摄像头及部分 OpenGL ES 扩展，受限于虚拟驱动，图形和视频硬件解码可能会有黑屏或降级提示（沿用既有模拟器图形验收豁免，不把豁免记作修复）。
2. **双端实际通话/同屏互联待联调**：
   - 本阶段仅完成运行环境、服务端口与最新代码产物的部署就绪；真实 Android 设备与 Web 浏览器之间的 P2P 观影同步进度、投屏画面流转及双向语音对讲，仍需在后续业务验收步骤中开展真实信令交互测试。
3. **未构建桌面/iOS 端产物**：
   - 本阶段根据指令限定准备 Android 与 Web 双端环境，未构建 Windows/macOS/iOS 发布包。
4. **发布授权**：
   - 本阶段为验收环境准备阶段，**未向任何应用商店、GitHub Releases 或 Yggdrasil 平台执行发布推送**。

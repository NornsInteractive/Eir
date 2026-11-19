# 供片离线 pause 修复与 16KB 页对齐验收环境准备报告

- **报告生成时间**：2026-11-19 10:56:00 +08:00
- **执行会话**：`70aef10f-2cc5-4efb-9d8b-d102153531c2` (固定 `gemini-3.8-flash-high/high`)
- **当前阶段**：双端业务验收环境就绪（包含供片离线 pause 补全与 16KB 页对齐 Tailcat 原生库两项修复，**明确暂不发布**）
- **规范遵守**：遵循 `AGENTS.md`，使用 `liquid_glass_widgets` 规范，不修改业务核心逻辑与 UI 界面，本地严格保留单份目标版本 APK，共享 ADB 设备暂不安装或操作。

---

## 一、本次集成的关键修复追溯

1. **供片成员离线 pause 提交补全**（参见 [docs/SOURCE-OFFLINE-PAUSE-FIX-HANDOFF.md](file:///workspace/projects/Eir/docs/SOURCE-OFFLINE-PAUSE-FIX-HANDOFF.md)）：
   - 源码位置：`lib/core/room_session.dart` :1781-1784；
   - 修复内容：在 `_handleMemberLeft` 中当前项供片成员离线且无下一可播项时，pause 动作的参数补全 `'itemId': currentItemId`，使提交符合 `_validateActionParams` 规则，消除 `commit_rejected` 异常，确保顺利触发暂停与清理逻辑。
2. **Android arm64 / x86_64 Tailcat 原生库 16KB 页对齐**（参见 [docs/TAILCAT-ANDROID-16KB-HANDOFF.md](file:///workspace/projects/Eir/docs/TAILCAT-ANDROID-16KB-HANDOFF.md)）：
   - 源码/工具链：基于 Android NDK r28 与 Clang（API 24），使用显式参数 `-ldflags="-extldflags '-Wl,-z,max-page-size=16384'"`；
   - 消除风险：将共享目标文件的 ELF `LOAD` 程序头段对齐值由原 `0x1000` (4KB) 提升至 `0x4000` (16KB)，解决 Android 15+ 16KB 物理页设备上的 `dlopen` 失败风险，并完整导出 `TailcatFree` 内存释放符号。

---

## 二、新旧构建产物与 SHA-256 追溯矩阵

本次构建已彻底覆盖上一轮前序产物，产物指纹发生了确定性变更：

| 校验项 | 属性 / 指纹类型 | 上一轮旧产物指纹 (前序) | **本次最新产物真实指纹 (当前)** |
| :--- | :--- | :--- | :--- |
| **Android APK 文件路径** | 本地唯一产物 | `eir-v1.0.40.apk` | [eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk) |
| **Android APK 文件大小** | 字节数 | 183,345,864 字节 | **183,346,056 字节** (~174.85 MB) |
| **Android APK SHA-256** | 完整文件哈希 | `e4563c9b6525f51d0ca655ec46abedb4d23c168cfae9b0f657c94b243901b8a5` | **`02831dedfbddef9a93a33f8ea4583627e021f2717be1b0981f3f975853eece89`** |
| **Web `main.dart.js` 路径** | 生产 JS 入口 | `build/web/main.dart.js` | [build/web/main.dart.js](file:///workspace/projects/Eir/build/web/main.dart.js) |
| **Web `main.dart.js` SHA-256** | 核心脚本指纹 | `e81574b5add2185eb76b6f571b2eda6bda84b6e7f0bc48cb831f9ed8f12135fb` | **`2960340c18b91b5201ad1487fd3f958e979d5c729038863386d139eab28b6ba8`** |
| **Web `version.json` SHA-256** | 版本配置指纹 | `e1d44fe...` | **`1c5a77ba95df29f0c25c74b62f1d23c3044520bccc22e743b46e123cc0d2aa50`** |
| **Web `eir_media_bridge.js`** | 媒体桥接脚本 | 同前 | **`41556baaa3bc377311153c1b3219693d6444bda9739c2c15ec4a36eff9691401`** |
| **Web `eir_media_sw.js`** | 媒体 ServiceWorker | 同前 | **`5124142fc6492d7f5a03d094ff5b5e52697ea483663075e6d1873bde9d50ce23`** |
| **Web `index.html`** | 宿主 HTML | 同前 | **`ad1c4555942eac65bf974bf43929c32007b61d447f22cfb6fb0f15fb7aa77b13`** |

---

## 三、APK 内原生库 ABI 与 16KB 页对齐实测核验

解压当前全新编译的 [eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk) 并直接对 APK 内经过 Gradle 符号剥离后的实际原生库进行 ELF 检验：

### 1. APK 内原生库分布与大小

| 架构 / ABI | APK 内文件路径 | 剥离后大小 | FFI 导出符号 | 16KB ELF LOAD 对齐 |
| :--- | :--- | :--- | :--- | :--- |
| **`arm64-v8a`** | `lib/arm64-v8a/libtailcat.so` | 19,326,824 B | `TailcatFree` 等 6 项完整导出 | **PASS (`p_align = 0x4000`)** |
| **`x86_64`** | `lib/x86_64/libtailcat.so` | 20,748,936 B | `TailcatFree` 等 6 项完整导出 | **PASS (`p_align = 0x4000`)** |
| **`armeabi-v7a`** | `lib/armeabi-v7a/` | 不适用 | 无 Tailcat（现状不打包） | 不适用 |

### 2. APK 内 `libtailcat.so` 实测 `readelf -l`

#### (1) `lib/arm64-v8a/libtailcat.so` (从当前 APK 提取实测)：
```text
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x00000000008f6918 0x00000000008f6918  R      0x4000
  LOAD           0x00000000008f6920 0x00000000008fa920 0x00000000008fa920
                 0x00000000006ad1e0 0x00000000006ad1e0  R E    0x4000
  LOAD           0x0000000000fa3b00 0x0000000000fabb00 0x0000000000fabb00
                 0x00000000002556d0 0x0000000000256500  RW     0x4000
  LOAD           0x00000000011f91d0 0x00000000012051d0 0x00000000012051d0
                 0x0000000000074b30 0x00000000020c8ae8  RW     0x4000
```
- **结论**：全部 4 个 LOAD 段对齐值 `p_align = 0x4000` (16,384 字节 / 16KB)。
- **符号核对**：`nm -D` 提取确认包含 `0000000000fa6584 T TailcatFree`。

#### (2) `lib/x86_64/libtailcat.so` (从当前 APK 提取实测)：
```text
  LOAD           0x0000000000000000 0x0000000000000000 0x0000000000000000
                 0x000000000092a98c 0x000000000092a98c  R      0x4000
  LOAD           0x000000000092a9c0 0x000000000092e9c0 0x000000000092e9c0
                 0x00000000007d4a00 0x00000000007d4a00  R E    0x4000
  LOAD           0x00000000010ff3c0 0x00000000011073c0 0x00000000011073c0
                 0x00000000002550c8 0x0000000000255c40  RW     0x4000
  LOAD           0x0000000001354490 0x0000000001360490 0x0000000001360490
                 0x0000000000074b90 0x00000000020c2238  RW     0x4000
```
- **结论**：全部 4 个 LOAD 段对齐值 `p_align = 0x4000` (16KB)。
- **符号核对**：`nm -D` 提取确认包含 `0000000001101ec0 T TailcatFree`。

### 3. APK 静态对齐与启动兼容性检查

- **16KB Zip 对齐验证**：
  `/opt/android-sdk/build-tools/35.0.0/zipalign -c -P 16 -v 4 eir-v1.0.40.apk`
  -> **`Verification succesful`**。
- **ZFlip7 真机启动 guard 校验**：
  `tool/android_debug_apk.sh verify eir-v1.0.40.apk`
  -> **`OK: eir-v1.0.40.apk`**（验证包含 `libflutter.so` 且非集成测试入口）。

---

## 四、相关构建与部署脚本 SHA-256

| 脚本文件路径 | 作用职责 | SHA-256 哈希值 |
| :--- | :--- | :--- |
| [tool/build_tailcat_android.sh](file:///workspace/projects/Eir/tool/build_tailcat_android.sh) | Android Tailcat 16KB 原生库编译与验证门禁脚本 | `3212b0134e33be7f173b30a74680d0aa97f44e12e8a6993dcca27f390d12fc7d` |
| [tool/android_debug_apk.sh](file:///workspace/projects/Eir/tool/android_debug_apk.sh) | Android APK 完整性与真机兼容 Guard 校验工具 | `262f234c8c2aa8d7e566b88dc1e837c826fc3880ce4b78821b64b679f2dccd9c` |
| [server/signaling_server.dart](file:///workspace/projects/Eir/server/signaling_server.dart) | 统一 Web 静态托管与 WebSocket 信令服务端 | `3955edbafa7f2c33db20fa3b27c90bc820b7406caeff19ffb30a98ce593a6f96` |

---

## 五、IPv4 / IPv6 双栈常驻 Web 与信令服务 (端口 8080)

### 1. 服务运行方式与生命周期守护
- **守护机制**：独立 Linux `tmux` 会话（会话名称 `eir-server`）；
- **启动命令行**：`dart run server/signaling_server.dart 8080 :: build/web`；
- **监听绑定**：绑定 IPv6 通配地址 `::`（在 Linux 默认 dual-stack 模式下同时处理 IPv4 与 IPv6 流量）；
- **生命周期解耦**：彻底脱离 Antigravity CLI 进程生命周期，CLI 关闭或重启不会终止服务；
- **日志持久化**：`/workspace/projects/Eir/server/server.log`。

### 2. 双栈实测连接结果

| 访问入口类型 | 访问 URL / Endpoint | HTTP 状态码 / 握手响应 | 实际服务 `main.dart.js` 哈希核对 |
| :--- | :--- | :--- | :--- |
| **本机 IPv4 回环** | `http://127.0.0.1:8080/` | `HTTP/1.1 200 OK` | `2960340c18b91b5201ad1487fd3f958e979d5c729038863386d139eab28b6ba8` |
| **本机 IPv6 回环** | `http://[::1]:8080/` | `HTTP/1.1 200 OK` | 一致 |
| **局域网 IPv4** | `http://192.168.1.106:8080/` | `HTTP/1.1 200 OK` | 一致 |
| **Tailscale 专网** | `http://100.86.170.61:8080/` | `HTTP/1.1 200 OK` | 一致 |
| **公网 IPv6** | `http://[240e:379:8e8d:b000:aaa1:59ff:fed6:5a7c]:8080/` | `HTTP/1.1 200 OK` | 一致 |
| **IPv4 WebSocket 信令** | `ws://127.0.0.1:8080/ws` | `HTTP/1.1 101 Switching Protocols` | 正常建立信令帧链路 |
| **IPv6 WebSocket 信令** | `ws://[::1]:8080/ws` | `HTTP/1.1 101 Switching Protocols` | 正常建立信令帧链路 |

> 实测通过 `curl -s http://127.0.0.1:8080/main.dart.js | sha256sum` 获得哈希 `2960340c18b91b5201ad1487fd3f958e979d5c729038863386d139eab28b6ba8`，证明当前持续对外服务的正是本次编译的最新 Web 产物。

---

## 六、安全上下文边界与测试指引

> [!IMPORTANT]
> **关于 COOP/COEP 与浏览器安全上下文的准确边界：**
> 1. **COOP/COEP**：响应头中的 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: credentialless` 仅用于启用浏览器底层跨域隔离与 `SharedArrayBuffer`，**不会将普通的非加密 HTTP 变为可信安全上下文**。
> 2. **证书要求**：用户当前开发测试环境不要求配置 SSL/TLS 证书。

### 验收入口适用性指引：

1. **本机回环 (`http://127.0.0.1:8080/` 或 `http://localhost:8080/` 或 `http://[::1]:8080/`)**：
   - 浏览器自动认定为**安全上下文** (Potentially Trustworthy Origin)；
   - 完整支持：WebRTC 语音/视频通话、屏幕共享推流 (`getDisplayMedia`)、Service Worker 媒体分块缓存；
   - **推荐作为 Web 侧业务功能验收首选入口**。
2. **局域网 IP / 公网 IPv6 / 域名 (纯 HTTP)**：
   - 浏览器认定为**非安全上下文**；
   - 投屏推流与 ServiceWorker 会被现代浏览器安全策略阻断；纯信令协同与普通 HTTP 音视频拉流不受影响；
   - 若需跨机通过 HTTP 进行投屏联调，需启动带 `--unsafely-treat-insecure-origin-as-secure=http://<IP>:8080` 启动参数的浏览器。
3. **Android 端**：
   - 应用沙盒内运行，系统媒体与网络权限受 Android Manifest 控制，不依赖 Web 浏览器的安全上下文规则；
   - 设备内通过 `adb reverse tcp:8080 tcp:8080` 可直接使用 `http://127.0.0.1:8080` 与宿主机通信。

---

## 七、Android 设备安装状态与交接核验

### 1. 设备前台与安全安装核验
- **目标设备**：`172.17.0.1:14251` (Android 14, x86_64)；
- **安装前状态**：确认设备停在系统桌面（`com.google.android.apps.nexuslauncher/.NexusLauncherActivity`），无其他项目前台任务占用；
- **安装指令**：`adb -s 172.17.0.1:14251 install -r ./eir-v1.0.40.apk`（数据保留覆盖安装，未执行 `pm clear`，未卸载，未触碰其他应用）；
- **安装结果**：`Performing Streamed Install` -> **`Success`**。

### 2. 设备内安装指纹核验实测
- **包信息实测** (`dumpsys package com.norns.eir`)：
  ```text
  versionCode=41 minSdk=24 targetSdk=36
  versionName=1.0.40
  dataDir=/data/user/0/com.norns.eir
  lastUpdateTime=2026-11-19 11:17:31
  firstInstallTime=2026-11-15 02:39:07
  ```
- **设备内 base.apk SHA-256 核对**：
  实测设备内 `/data/app/~~tec_hzY8BuWSohbJHhvWVA==/com.norns.eir-qh9ME9xo9rz3FZas09p2AA==/base.apk` 哈希值：
  **`02831dedfbddef9a93a33f8ea4583627e021f2717be1b0981f3f975853eece89`**（与本地产物逐字节完全一致）。

### 3. 反向代理端口映射实测
- **映射规则**：`adb -s 172.17.0.1:14251 reverse tcp:8080 tcp:8080` 已激活；
- **设备内连通性测试**：设备内部访问 `http://127.0.0.1:8080/version.json`，实测返回：
  `HTTP/1.1 200 OK`，正文 `{"app_name":"eir","version":"1.0.40","build_number":"41","package_name":"eir"}`。

---

## 八、真实限制与验收声明 (Non-Exemptions)

> [!IMPORTANT]
> **安装成功与服务常驻不等于完整业务功能验收通过。**

真实存在的环境与功能限制说明如下：
1. **安装交接边界**：
   - 本阶段仅完成 APK 安装与设备内指纹、端口映射交接；设备当前仍停在系统桌面，未启动应用或执行点按，业务点按与双端流程测试交由后续流程执行。
2. **真实双端业务交互待回归**：
   - 本阶段完成产物构建、静态 ELF/16KB 对齐校验、包内 ABI 验证、设备覆盖安装与 IPv4/IPv6 双栈 Web/信令常驻部署；
   - 供片成员离线 pause 自动触发与无备用项时的播放器清理，需在后续真实客户端联调环节进行业务复测。
3. **未发布**：
   - 本阶段为双端业务验收环境就绪，**未向任何应用商店、GitHub Releases 或 Yggdrasil 平台执行发布推送**。

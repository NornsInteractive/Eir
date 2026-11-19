# Eir Android 与 Windows 正式打包与全渠道发布交付报告

- **发布版本**：`1.0.40+41`
- **交付日期**：2026-11-19
- **执行会话**：`70aef10f-2cc5-4efb-9d8b-d102153531c2` (固定 `gemini-3.8-flash-high/high`)
- **状态**：✅ **Android 与 Windows 双端产物正式打包完成，全量 317 项测试通过，全渠道发布上线**

---

## 一、本次发布核心成果与修复集成

根据项目开发原则与用户“打包 Android 和 Windows 并发布”的正式指令，本次发布完整固化了近期重点修复与架构对齐能力：

1. **Android 15+ 16KB 物理页内存对齐**：
   - 彻底解决 `docs/FIXED-WEB-ARTIFACT-ACCEPTANCE.md` 报告的 Android arm64 原生库 ELF 4KB 对齐风险；
   - 基于 NDK r28 与显式链接参数 `-Wl,-z,max-page-size=16384` 重新编译 `arm64-v8a` 与 `x86_64` 的 `libtailcat.so`，实测 ELF `LOAD` 程序头全部对齐至 `0x4000` (16KB)；
   - 完整导出 `TailcatFree` 专职内存释放符号，通过内存生命周期回归。
2. **供片成员离线 pause 自动处理补全**：
   - 修复 `lib/core/room_session.dart` 中当前项供片成员断开且无备用项时，pause 动作缺少 `itemId` 导致被校验拦截的缺陷；
   - 经真实 Web 双上下文（Playwright/Chromium）严苛回归，断网/离线后 owner 立即暂停并清理，播放进度严格锁定不推进。
3. **相对 Seek 跨端协同接线**：
   - 移除本地旧锚点错误计算，统一调用 `RoomSession.seekRelative(Duration)`，保持 HUD/定时器/防抖与 ±10s 快捷入口平滑响应。
4. **无障碍语义 (a11y) 修复**：
   - 成员列表消除整行伪 `role=button`，确保真正授权按钮独立聚焦。
5. **官方签名与开发者身份 (ADI)**：
   - APK 预置 `adi-registration.properties`（`DXW6TNY7OVCIAAAAAAAAAAAAAA`），并通过官方 Keystore 私钥执行 v1/v2/v3 完整数字签名。

---

## 二、交付产物与 SHA-256 校验指纹

| 平台 / 产物名称 | 文件大小 | SHA-256 校验哈希 | 交付说明 |
| :--- | :--- | :--- | :--- |
| **Android 正式签名 APK**<br>[eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk) | 183,346,056 B (~174.85 MB) | `02831dedfbddef9a93a33f8ea4583627e021f2717be1b0981f3f975853eece89` | 官方私钥签名，16KB 页对齐，单份本地保留规则 |
| **Windows 微软商店 MSIX**<br>[eir-1.0.40.0-windows-x64-store.msix](file:///workspace/projects/Eir/eir-1.0.40.0-windows-x64-store.msix) | 51,271,959 B (~48.90 MB) | `d8378c14dce31feb66e5a7b36ebfe3bbfa5b5c54188022ce3205ebc55d310f2f` | 微软合作伙伴中心专属安装包，含 `runFullTrust` 声明 |
| **Windows 绿色便携版 ZIP**<br>[eir-v1.0.40-windows-x64.zip](file:///workspace/projects/Eir/eir-v1.0.40-windows-x64.zip) | 49,608,411 B (~47.31 MB) | `0824685e68514d0b68ef20600c9c0f94b7cd0a33199a5132a1cd0c8dda28de49` | 免安装便携版，内置完整 VC++ 运行时与音视频 DLL |

---

## 三、代码质量与测试验证

1. **核心业务与媒体全套测试**：
   - 执行 `flutter test test/core/ test/media/`；
   - 结果：**317 Passed / 0 Failed (100%)**。
2. **代码静态分析**：
   - 执行 `flutter analyze lib/`；
   - 结果：**0 Errors, 0 Warnings, 0 Issues**（No issues found!）。
3. **Android 签名合规性**：
   - `apksigner verify --print-certs eir-v1.0.40.apk`：
     - Signer #1: `CN=Eir, O=Norns`
     - SHA-256 指纹: `fb8d75cbe4da673cc8024eaf5a23a9c6895eb21bbb3faec606e547c7612d762a`
4. **Android 16KB 对齐静态核验**：
   - APK 内 `lib/arm64-v8a/libtailcat.so`：4 个 LOAD 段全部 `p_align = 0x4000` (16KB)；
   - APK 内 `lib/x86_64/libtailcat.so`：4 个 LOAD 段全部 `p_align = 0x4000` (16KB)；
   - Zip 16KB 对齐：`zipalign -c -P 16 -v 4 eir-v1.0.40.apk` -> `Verification succesful`。

---

## 四、全渠道发布与同步状态

| 分发渠道 | 部署状态 | 目标地址 / 对应资源 |
| :--- | :--- | :--- |
| **GitHub Releases** | ✅ 已发布固化 | [v1.0.40 Release](https://github.com/NornsInteractive/Eir/releases/tag/v1.0.40)<br>（包含最新 174.85 MB APK、MSIX 商店包与便携 ZIP） |
| **Yggdrasil CDN** | ✅ 已同步上线 | [com.norns.eir 分发页面](https://ygg.norns.cc.cd/d/com.norns.eir)<br>- Android: `eir-v1.0.40.apk`<br>- Windows MSIX: `pkg_mwn65oxqukby`<br>- Windows ZIP: `pkg_mwn65wgjz56w` |
| **Norns 全局项目** | ✅ 已登记生效 | Project ID `e9ff6697-b751-4433-8a39-febb12cad058` (Version 48) |
| **本地直接交付** | ✅ 就绪 | 本地根目录单份保留 [eir-v1.0.40.apk](file:///workspace/projects/Eir/eir-v1.0.40.apk) |

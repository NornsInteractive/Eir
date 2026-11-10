# UI 播放器画面渲染验证记录

> **验证声明**：本验证为 UI 侧使用官方 `media_kit_video` 的 `VideoController` + `Video` 标准入口与 `liquid_glass_widgets` 容器的最小真实渲染验证片。严格按实际测试输出记录证据，**不声称六端已通过**。

---

## 1. 验证目标与规范

- **组件入口**：官方 `media_kit_video` 标准 `VideoController(player)` + `Video(controller: controller, controls: NoVideoControls)`。
- **UI 容器**：使用 `liquid_glass_widgets` 的 `GlassContainer.card(surfaceStyle: GlassSurfaceStyle.solid)` 容器包裹，符合 iOS HIG 媒体播放区 solid platter 规则。
- **Liquid Glass 初始化**：遵循 Skill 架构生命周期，在测试启动前调用 `await LiquidGlassWidgets.initialize()` 预热着色器。
- **无权威状态原则**：测试组件仅挂载画面与下发控制，不自造播放器，不持有房间权威状态，不改动产品界面代码。
- **样本加载与平台边界**：通过 Flutter `rootBundle` 读取 `assets/sample.mp4` 并原子写入系统临时目录，不依赖项目根目录 POSIX 假定路径；明确本测试仅在 Linux 桌面端执行验证，不声称手机/Web 路径可用。
- **严格真实画面证据**：拒绝仅以 1x1 初始占位纹理判定通过；在 `waitUntilFirstFrameRendered` 之后，进行**有界轮询等待并明确断言真实视频样本的 320x240 像素尺寸**，断言通过后才确认画面渲染成功。
- **超时与生命周期保护**：所有异步等待（`LiquidGlassWidgets.initialize`、`player.open`、`waitUntilFirstFrameRendered`、`player.pause`、`player.seek`、`pumpAndSettle` 以及 `player.dispose`）均设置 10s–15s 有界超时；测试在 `try / finally` 块中确保释放 Native mpv 资源与临时文件。

---

## 2. 实际执行命令

```bash
timeout 150 xvfb-run -a flutter test integration_test/player_surface_test.dart -d linux
```

---

## 3. 运行证据与输出

- **测试用例**：`integration_test/player_surface_test.dart`
- **执行环境**：Linux x64 (Debian GNU/Linux 12 / xvfb 虚拟帧缓冲区)
- **依赖配置**：`media_kit: ^1.2.6`, `media_kit_libs_video: ^1.0.7`, `media_kit_video: ^2.0.1`
- **测试媒体**：`assets/sample.mp4`（3秒 H.264/AAC 原生样本，真实尺寸 320x240）
- **退出状态码**：`0`（全部通过）

### 真实执行日志证据

```text
✓ Built build/linux/x64/debug/bundle/eir
00:18 +0: .../workspace/projects/Eir/integration_test/player_surface_test.dart 00:18 +0: media_kit_video ... surface rendering test with liquid glass card    00:18 +0: media_kit_video VideoController + Video surface rendering test with liquid glass card
[LiquidGlass] Initializing library...
[LiquidGlass] PerformanceMonitor started (budget: 16 ms, threshold: 60 frames)
[LiquidGlass] Initialization complete.
00:18 +0: loading /workspace/projects/Eir/integration_test/player_surface_test.dart
media_kit: NativeReferenceHolder: Allocated 139641266946704
00:18 +0: media_kit_video VideoController + Video surface rendering test with liquid glass card
VideoOutput.Resize
{handle: 139641266685888, id: 94438031634192, rect: {left: 0, top: 0, width: 1, height: 1}}
NativeVideoController: Texture ID: 94438031634192
VideoOutput.Resize
{handle: 139641266685888, id: 94438031634192, rect: {left: 0, top: 0, width: 320, height: 240}}
[PlayerSurfaceTest] Verified video surface frame rendered: textureId=94438031634192, dimensions=320.0x240.0
[PlayerSurfaceTest] Verified position advancement: initial=0:00:00.133333 -> current=0:00:00.500000
[PlayerSurfaceTest] Verified pause: position held at 0:00:00.533333
[PlayerSurfaceTest] Verified seek: target=0:00:01.800000, actual=0:00:01.800000
00:22 +1: media_kit_video ... surface rendering test with liquid glass card    00:22 +1: (tearDownAll)                                                        00:22 +1: All tests passed!
```

### 验证证据明细

1. **着色器生命周期预热**：
   - `LiquidGlassWidgets.initialize()` 成功启动 `PerformanceMonitor` 并完成初始化。
2. **真实视频画面输出证据（320x240 严格断言）**：
   - 官方 `controller.waitUntilFirstFrameRendered` 触发后，初始为 1x1 占位纹理；测试有界等待原生解码器完成实际尺寸上报。
   - 成功捕获并显式断言目标样本分辨率：`width == 320.0`，`height == 240.0`。
   - 确认引擎注册的 Texture ID（`94438031634192`）。
3. **位置推进证据**：
   - 起始播放位置 `0:00:00.133333` 推进至 `0:00:00.500000`（推进 >300ms）。
4. **暂停控制证据**：
   - 调用 `player.pause()` 并附加 10s 超时；暂停后持续等待 500ms，播放位置稳定锁定在 `0:00:00.533333` 无任何漂移。
5. **Seek 跳转证据**：
   - 调用 `player.seek(Duration(milliseconds: 1800))` 附加 10s 超时；位置精准跳转并对齐至 `0:00:01.800000`。
6. **资源防泄漏与异常保护**：
   - 在 `try / finally` 块中调用 `player.dispose()`（带超时），并递归清理临时解压的样本目录。

---

## 4. 平台覆盖与未测端记录

遵循 [docs/DEVELOPMENT-PRINCIPLES.md 第 5 节](file:///workspace/projects/Eir/docs/DEVELOPMENT-PRINCIPLES.md)，严格区分已验证端与未测端，不得静默缩减范围或将桌面验证声称为全端支持：

| 平台 | 状态 | 验证说明 |
|---|---|---|
| **Linux (desktop)** | **已验证 (通过)** | 通过 xvfb 虚拟屏幕与 Flutter Linux 桌面 Bundle 实测，着色器预热、首帧渲染、Texture ID、320x240 样本真实尺寸、推进/暂停/Seek 全部通过。 |
| **Windows** | **未测端** | 本轮未在 Windows 环境执行构建与 Direct3D 纹理测试。 |
| **macOS** | **未测端** | 本轮未在 macOS 环境执行 Metal 纹理渲染测试。 |
| **Android** | **未测端** | 本轮未在 Android 模拟器/真机上执行 SurfaceTexture 渲染测试。 |
| **iOS** | **未测端** | 本轮未在 iOS 环境执行渲染测试。 |
| **Web** | **未测端** | Web 端视频需通过 HTML5 VideoElement / WebGL 渲染，本测试未覆盖 Web 端。 |

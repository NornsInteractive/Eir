# 平台能力验证记录（G1/G2 垂直片）

> 本文是早期底层验证片的历史记录，未覆盖后续 MVP 接线。最新独立构建/运行结论以 [MVP 执行记录](MVP-EXECUTION.md) 为准；下文“无 Windows 环境”“Android 仓库阻塞”等旧结论已发生变化。

## 1. 范围

本文件记录本轮仅对底层能力的验证结果，不实现房间系统、UI 或接线。G1/G2 的完整定义见 `docs/V1-ACCEPTANCE.md`。

- G1：WebRTC DataChannel、身份/指纹暴露、背压、ICE。
- G2：媒体输入播放能力（URL/本地）。完整“P2P 字节 -> 缓存 -> loopback HLS -> 播放器”链路尚未实现，因此 G2 **未通过**。

## 2. 依赖选型证据

| 依赖 | 版本 | 用途 | 证据 |
|---|---|---|---|
| `flutter_webrtc` | `^1.6.2+hotfix.4`（pub cache 1.6.2+hotfix.4） | DataChannel/SDP/ICE/getStats | `~/.pub-cache/hosted/pub.dev/flutter_webrtc-1.6.2+hotfix.4` |
| `media_kit` | `^1.2.6`（pub cache 1.2.6） | URL/本地输入播放 | `~/.pub-cache/hosted/pub.dev/media_kit-1.2.6` |
| `media_kit_libs_video` | `^1.0.7`（pub cache 1.0.7） | 各平台原生解码库（按平台依赖） | `~/.pub-cache/hosted/pub.dev/media_kit_libs_video-1.0.7` |

选择理由：均为成熟库，覆盖目标平台；避免自研播放器/WebRTC。

## 3. 验证矩阵

| 平台 | WebRTC DataChannel | 媒体播放 | 状态 |
|---|---|---|---|
| Linux | 通过（loopback，含真实远端 DTLS 指纹映射） | 通过（asset/file/HTTP URL，真实位置推进） | 已验证 |
| Android | 未验证 | 未验证 | 构建阻塞（见 §5） |
| Windows | 未验证 | 未验证 | 无环境 |
| macOS | 未验证 | 未验证 | 无环境 |
| iOS | 未验证 | 未验证 | 无环境 |
| Web | 未验证 | 未验证 | 当前 Flutter integration_test 调用方式不支持 Web；media_kit Web 仅 URL/blob，未测 |

## 4. Linux 复现命令

```bash
# 1. 启动 PulseAudio（flutter_webrtc Linux 初始化需要，使用默认空闲退出）
pulseaudio --start

# 2. WebRTC loopback（有界显示与超时）
ulimit -c 0
xvfb-run -a flutter test integration_test/native_webrtc_loopback_test.dart -d linux --timeout=120s

# 3. 媒体播放（有界显示与超时）
xvfb-run -a flutter test integration_test/native_media_playback_test.dart -d linux --timeout=120s

# 4. 静态检查与单元测试
flutter analyze
flutter test
```

最近一次结果：
- WebRTC：`success=true`，消息与二进制负载均校验通过，`statsReportCount=150`，远端 DTLS 指纹通过 `transport.remoteCertificateId -> certificate.fingerprint` 映射得到（非 SDP 自报）。
- 背压：API 可用（`getBufferedAmount`），loopback 下 `maxBufferedAmount=0`，阈值未跨越，`backpressureObserved=false`；未伪造通过。
- 媒体：asset/file/HTTP URL 均 `success=true`，播放时位置真实推进（`playbackObserved=true`）。

## 5. 阻塞与限制

1. Android 构建阻塞：`~/.gradle/init.gradle` 向 `allprojects` 注入额外 Maven 仓库，与 `android/settings.gradle.kts` 的 settings 仓库策略冲突；按要求未修改全局配置。需协调者提供隔离 Gradle 配置或调整仓库策略后再验证。
2. Linux WebRTC 依赖 PulseAudio 运行时；缺少 `pulseaudio`/`pactl` 时 `webrtc::WebRtcVoiceEngine::Init` SIGABRT。即使仅 DataChannel 也会初始化语音引擎。
3. G1 未完整：仅 Linux loopback，未做跨系统、ICE 重启、篡改握手拒绝。
4. G2 未完整：仅验证媒体输入播放，未实现 P2P 字节、缓存、loopback HLS 与播放器链路。
5. Web 媒体：media_kit Web 后端基于 HTMLVideoElement，仅 URL 输入；内存文件/fMP4 输入方式未验证，不能宣称支持。
6. 未验证 Windows/macOS/iOS/Web。

## 6. 变更文件

- `pubspec.yaml`：新增 `flutter_webrtc`、`media_kit`、`media_kit_libs_video`、`integration_test`。
- `lib/webrtc_validation.dart`：无 UI WebRTC loopback 验证模块。
- `lib/media_validation.dart`：无 UI 媒体输入播放验证模块。
- `integration_test/native_webrtc_loopback_test.dart`、`integration_test/native_media_playback_test.dart`。
- `assets/sample.mp4`：带音轨的测试样本。
- `docs/PLATFORM-VALIDATION.md`。

## 7. 协调者补充

- 画面渲染独立验证见 [UI-PLAYER-VALIDATION.md](UI-PLAYER-VALIDATION.md)：Linux 已等待并断言 320×240 实际输出尺寸，覆盖位置推进、暂停及 seek；不扩大成六端通过。
- 早期 Android 排查曾临时重命名全局 Gradle init 脚本，已由协调者恢复。后续验证保留该全局配置，Android 仍记阻塞。
- 新增本机测试环境工具：Xvfb、gdb、PulseAudio；原生崩溃转储已提取堆栈并清除，不作为项目源文件保留。
- fixture 由 FFmpeg 的 testsrc 与 sine 合成，无外部电影素材。可复现生成命令（仅替换测试样本）：

```bash
ffmpeg -f lavfi -i testsrc=size=320x240:rate=30 -f lavfi -i sine=frequency=1000 -t 3 -c:v libx264 -pix_fmt yuv420p -c:a aac assets/sample.mp4
```

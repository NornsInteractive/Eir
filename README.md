# Eir

[![Privacy Policy](https://img.shields.io/badge/Privacy%20Policy-Bilingual-blue.svg)](PRIVACY.md)
[![Release](https://img.shields.io/github/v/release/NornsInteractive/Eir)](https://github.com/NornsInteractive/Eir/releases/latest)

Flutter 跨平台异地同步观影与 60 FPS 实时投屏应用。支持本地音视频与网络流媒体毫秒级同步、低延迟屏幕投屏、双向语音对讲与即时弹幕互动。纯端到端（P2P）直传，免注册无广告。

- 📖 **[隐私政策 / Privacy Policy](PRIVACY.md)**（包含 [🇨🇳 中文版](docs/PRIVACY-POLICY-ZH.md) · [🇬🇧 English Version](docs/PRIVACY-POLICY-EN.md) · [🌐 在线网页版](https://eir.norns.cc.cd/privacy.html)）
- 📋 **[应用商店上架物料指南 / App Store Listing](docs/APP-STORE-LISTING.md)**
- 🌐 **[Web 放映室在线体验](https://eir.norns.cc.cd)** · **[Android APK 下载](https://ygg.norns.cc.cd/d/com.norns.eir)**

首版目标是两人房间，支持本地兼容 MP4 和视频 URL，包含播放列表、同步控制、房主/管理员权限，以及中文/英文和明暗主题独立配色。

MVP 已生成本地交付产物，Linux、Android 和 Web 已完成本轮运行验证。安装与运行见 [产物说明](artifacts/mvp/RUN.md)，逐项结果见 [执行记录](docs/MVP-EXECUTION.md)。Windows 编译通过但运行待桌面环境，macOS 暂缓、iOS 缺构建环境；六端尚未全部验收。

## 开发运行

使用标准 Flutter 工具链，建议 Flutter 3.44.2。`liquid_glass_widgets` 要求 Flutter 至少 3.41；请勿使用旧 SDK 绕过版本约束。

```bash
flutter pub get
# 另开终端运行 Web 与 WebSocket 信令单端口一体化服务（默认同时托管 Web 静态文件与信令）
dart run server/signaling_server.dart 8080 :: build/web
flutter run -d linux
```

如需部署至 Cloudflare Edge，请参阅 [Cloudflare 部署指南](cloudflare/README.md)。

在设置中填写双方都能访问的信令地址。`127.0.0.1` 只适合本机测试；异地连接需可达服务及 WSS。邀请包含房主身份和信令信息，应私下分享。视频文件通过已验证的 WebRTC DataChannel 按需传输，信令服务不存储视频。

本地输入首版使用原始兼容 MP4 的哈希分块与 Range 适配，不自动转码。浏览器能播放的编码取决于平台；推荐 H.264/AAC MP4。URL 使用 HTTPS，HTTP 仅允许 loopback。Web 还受到 CORS、自动播放策略及安全上下文限制；本地媒体桥接需要 Service Worker。

Linux 开发需 GTK、libmpv、libsecret、运行中的 Secret Service 和 PulseAudio。无密钥服务时应修复桌面环境，不将设备私钥改存明文。Android 构建若被全局 Gradle init 脚本影响，可使用独立 `GRADLE_USER_HOME`；不要修改其他项目共用配置。

## 验证

```bash
flutter analyze
flutter test
# 需真实平台运行环境；Linux 无桌面时可加 xvfb-run -a
flutter test integration_test/room_session_url_test.dart -d linux
flutter test integration_test/room_session_local_media_test.dart -d linux
```

媒体后台浏览器测试见 `test/media/browser_probe.js`。该测试的专用入口不能打包成产品 Web 主页；产品入口为 `lib/main.dart`。平台结果与测试所用替身/真实链路的区别见 [文档索引](docs/README.md)。

首版不包含多人 Swarm、自动转码或 TURN 中继，严格 NAT 下可能无法直连。macOS 构建已按用户要求暂缓，iOS 尚无 Xcode 构建环境。构建和运行测试不代表自动发布授权。

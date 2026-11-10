# Android 正式构建

- 应用 ID：`com.norns.eir`。旧的 `com.eir.app.eir` 是独立应用，Android 不会自动迁移其数据；保留旧应用及其数据。
- 使用 `flutter build apk --release --target lib/main.dart` 构建。避免在集成测试后使用 `--no-pub`，以便 Flutter 按正式构建重新生成插件注册文件。
- `android/key.properties` 是不纳入版本库的本机配置，包含 `storeFile`、`keyAlias` 和 `passwordFile`；密码从受保护文件读取。正式构建不使用调试密钥。
- 本机构建密钥与密码文件位于 `/home/dev/.local/share/eir-signing/`。应安全备份这两份文件；后续更新必须继续使用同一签名证书，不能将密钥或密码提交到仓库。
- 2026-11-10：1.0.0+1 APK 已编译、验证包名及签名，并在 Android 模拟器上安装启动。图形黑屏与真实设备的播放验收仍按 `CURRENT-REPAIR-PLAN.md` 记录。

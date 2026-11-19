# 本地信令地址兼容修复交接

范围：仅 `lib/app_settings.dart` 的旧配置加载分支、对应配置测试、本文件。未改 UI、未改远程配置同步策略、未构建/安装/发布。

## 缺陷

`AppSettings.init()` 读取已保存的 `eir_setting_signaling_url` 标量后，会把
`ws://localhost|127.0.0.1:8765|8080`（含带尾斜杠及 `/ws` 变体）硬编码迁移为
`effectiveDefaultSignalingUrl`，并回写覆盖用户已保存的地址。用户显式保存的本地地址在重启后
被静默改成生产地址，违反“已保存地址即用户选择”。

## 修复

- `lib/app_settings.dart` 第 5 节 Signaling URL：删除上述 8 个地址的硬编码迁移及回写，非空保存值
  仅做 `trim()` 后直接采用；空/缺失值仍走原有 `effectiveDefaultSignalingUrl` 默认路径。
- 保留原子 JSON 记录 `eir_setting_network_config` 及其 best-effort 标量镜像逻辑不动；记录存在时
  仍在第 17 节整体覆盖标量（权威记录优先）。
- 未新增规范化、尾斜杠处理、存储结构或配置框架。
- 净变更：`lib/app_settings.dart` 中 -18/+4 行（该文件另有他人未提交的原子记录改动，未触碰）。

## 复现（先红后绿）

新增测试：`test/core/app_settings_local_signaling_compat_test.dart`（3 个用例，每个用例用
`Isolate.run` 获得全新单例，覆盖 8 个本地地址变体表格、无值默认、权威记录冲突优先）。

修复前（红）：

```
flutter test test/core/app_settings_local_signaling_compat_test.dart --reporter expanded
# 00:00 +2 -1: Some tests failed.
# 失败：Expected 'ws://127.0.0.1:8765' / Actual 'wss://eir.norns.cc.cd/ws'
```

修复后（绿）：

```
flutter test test/core/app_settings_local_signaling_compat_test.dart --reporter expanded
# 00:00 +3: All tests passed!
```

相关配置行为回归（含上述新文件）：

```
flutter test test/core/app_settings_local_signaling_compat_test.dart \
  test/core/app_settings_network_compat_test.dart \
  test/core/app_settings_network_record_load_test.dart \
  test/core/app_settings_signaling_persist_test.dart \
  test/core/remote_config_service_test.dart \
  test/core/remote_config_batch_test.dart --reporter expanded
# 00:00 +26: All tests passed!
```

窄范围静态检查：

```
dart analyze lib/app_settings.dart
# No issues found!
```

## 重建范围

当前已服务的 Web 产物与 `eir-v1.0.40.apk` **不包含**本修复，不得据此宣称线上已修复。需由 Agy
重新打包 Android 与 Web；Windows/iOS 等其余端若沿用旧产物同样需要重建，但本次仅要求
Android/Web。

## 未解决策略风险（本次未改，需单独决策）

远程配置同步仍可能在拉取后整体覆盖用户显式保存的信令地址（`applyRemoteConfig` 语义不变）。
本地地址是否应被远程配置覆盖、以及覆盖前是否提示用户，属于同步策略问题，不在本次兼容修复
范围内，需另行确认。

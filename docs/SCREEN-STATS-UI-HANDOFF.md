# 屏幕共享实时网络看板 UI 适配交接 (Screen Share Stats UI Handoff)

状态：已完成 `lib/views/screen_share_live_view.dart` 网络指标 UI 适配、本地化资源扩展与针对性 UI 测试验证（2026-11-18）。

---

## 一、任务背景与核心规范

依据 `AGENTS.md`、`docs/README.md`、`docs/APP-SETTINGS.md` 以及 `liquid_glass_widgets` 规范，本轮仅处理 UI 与 UI 接线，严格遵守以下约束：
1. **指标类型规格**：`ScreenShareService` 中：
   - `rttMs` 为 `int?`（毫秒）；
   - `bitrateMbps` 为 `double?`（Mbps）；
   - `packetLoss` 为 `double?`（0..1 比例，显示需转换为百分比）；
   - 各项可独立为 `null`，即使 `statsAvailable == true` 仍可能缺少单项指标。
2. **UI 展示规则**：
   - **有值时**：正常显示数值与单位（例如 `45 ms`、`2.5 Mbps`、`1.5%`）；
   - **为 null 时**：必须显示本地化“暂无数据”（中文 `暂无数据`、英文 `No data`），**禁止使用 `?? 0` 冒充零值**；
   - 消除所有由于对可空对象直接调用方法（如 `.toStringAsFixed(1)`、`* 100`）导致的编译与静态分析错误；
   - 保留既有液态玻璃设计风格（`GlassContainer.card`）与视觉外观，不重做 UI，不添加额外功能；
3. **范围约束**：
   - 禁止修改业务逻辑源码与服务端；
   - 不进行整文件格式化，不覆盖其他代理并行提交的内容；
   - 本轮不执行应用构建、安装、打包或发布。

---

## 二、精确修改文件与修改内容

### 1. [lib/views/screen_share_live_view.dart](file:///workspace/projects/Eir/lib/views/screen_share_live_view.dart#L1075-L1130)

在 `_showStreamHealthSheet` 面板与 `_buildMetricRow` 中：
- 对 `rttMs`、`bitrateMbps`、`packetLoss` 执行可空判断：
  - `_service.rttMs != null ? '${_service.rttMs} ms' : i18n.metricNoData`
  - `_service.bitrateMbps != null ? '${_service.bitrateMbps!.toStringAsFixed(1)} Mbps' : i18n.metricNoData`
  - `_service.packetLoss != null ? '${(_service.packetLoss! * 100).toStringAsFixed(1)}%' : i18n.metricNoData`
- 颜色逻辑：有数值时保留强调色（RTT 保持 `tc.primary`，码率保持 `tc.textPrimary`，丢包率保持 `tc.success`）；为空时统一显示柔和的次要文字色 `tc.textSecondary`；
- 在 `_buildMetricRow` 中为 `label` 增加 `Expanded` 约束，并在标题栏中将 `Text` 包裹为 `Expanded`，防止英文等多语言或窄屏环境下的微小像素溢出。

### 2. [lib/app_localization.dart](file:///workspace/projects/Eir/lib/app_localization.dart#L559)

新增指标通用缺省文案：
```dart
  String get metricNoData => isZh ? '暂无数据' : 'No data';
```
对齐现有多语言体系，中文返回 `暂无数据`，英文返回 `No data`。

### 3. [test/ui/screen_share_stats_ui_test.dart](file:///workspace/projects/Eir/test/ui/screen_share_stats_ui_test.dart)

针对指标可空渲染编写轻量级 UI 验证测试：
1. **全 null / 独立 null 校验**：验证在指标为空时，UI 渲染 3 处 `暂无数据`，且断言不存在 `0 ms`、`0.0 Mbps`、`0.0%` 等错误占位；
2. **正常数值校验**：验证在 `rttMs: 42, bitrateMbps: 3.8, packetLoss: 0.012` 时，正确渲染 `42 ms`、`3.8 Mbps`、`1.2%`；
3. **英文与部分为 null 校验**：验证在英文环境及部分指标为 null（如仅 RTT 与丢包率有值，码率为空）时，正确显示 `28 ms`、`No data`、`0.5%`。

---

## 三、检查与实测证据

1. **静态语法与类型分析 (`dart analyze`)**：
   ```bash
   dart analyze lib/views/screen_share_live_view.dart lib/app_localization.dart test/ui/screen_share_stats_ui_test.dart
   ```
   **结果**：`No issues found!`（退出码 0，消除此前 unchecked_use_of_nullable_value 错误）。

2. **UI 自动化测试 (`flutter test`)**：
   ```bash
   flutter test test/ui/screen_share_stats_ui_test.dart
   ```
   **结果**：3 个测试用例全部通过（`All tests passed!`，退出码 0）。

3. **既有导航测试回归**：
   ```bash
   flutter test test/ui/screen_share_nav_test.dart
   ```
   **结果**：全部通过（`All tests passed!`，退出码 0）。

---

## 四、限制与交接说明

1. **业务服务隔离**：`ScreenShareService` 采样及统计逻辑由并行代理负责，UI 层仅作为展示端对接，不主动干涉 `refreshStats()` 的调用时机与统计公式。
2. **构建与分发限制**：本轮工作纯粹聚焦于 UI 适配及单测验证，未执行任何编译、打包、签名与发布动作，工作区其他未暂存变更完全保留。

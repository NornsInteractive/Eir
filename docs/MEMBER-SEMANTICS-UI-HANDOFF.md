# 成员列表可访问语义最小修复交接说明（MEMBER-SEMANTICS-UI-HANDOFF）

- **执行会话**：`70aef10f-2cc5-4efb-9d8b-d102153531c2` (固定 `gemini-3.8-flash-high/high`)
- **执行时间**：2026-11-18
- **遵循规范**：`AGENTS.md`、`docs/README.md`、`docs/APP-SETTINGS.md`、`liquid_glass_widgets` skill
- **关联文档**：`docs/ROLE-REJOIN-FIX-HANDOFF.md`

---

## 一、问题背景与根因定位

### 1. 现象
在 `docs/ROLE-REJOIN-FIX-HANDOFF.md` 的端到端测试与真实浏览器 Harness 检查中发现：
- 房主在 `Friends`（成员列表）中，真实的 Grant Admin / Revoke Admin 按钮（88×30）动作与网络交互均正常；
- 但**整个成员行**（1216×66）也被暴露为 `role=button` 且无交互动作，其 `aria-label` 自动拼接了整行文本与末尾的 `Grant Admin: <DisplayName>`；
- 导致辅助技术（如屏幕朗读器 TalkBack / VoiceOver）将整行误报为按钮，且双击无反应；自动化测试工具（如 Playwright `getByRole('button', { name: /Grant Admin/ })`）会匹配到 2 个按钮节点，若选到外层成员行则无法触发授权提交。

### 2. 根因分析
1. 在 `lib/views/cinema_view.dart` 中，原实现用 `Semantics(button: true, label: ...)` 包裹 `LiquidGlassActionButton`，但未指定 `container: true`。
2. Flutter 语义树合成机制中，未声明 `container: true` 的子节点语义属性会被向上合并至最近的父容器 `SemanticsNode`（即 ListView 中的成员行容器）。
3. 导致外层整行继承了 `isButton = true` 及 `Grant Admin: ...` 标签，却没有绑上 `onTap` 动作；
4. 同时，`LiquidGlassActionButton` 内部使用 `GlassButton.custom`，但原先未暴露出 `semanticLabel` 属性，导致内部按钮未能承接完整的独立语义标签。

---

## 二、最小修复方案（保持外观与业务零变更）

### 1. `lib/apple_glass.dart`
为 `LiquidGlassActionButton` 新增可选参数 `String? semanticLabel`，并在内部传递给 `GlassButton.custom(label: semanticLabel ?? '', ...)`：
- 当 `GlassButton` 收到非空 `label` 时，其内建的 `GlassFocusRegion` 会自动构造独立的 `Semantics(container: true, button: true, label: widget.label, onTap: widget.onTap, child: ExcludeSemantics(child: ...))`；
- 确保动作按钮自身成为独立、唯一的语义按钮节点，且自动避免子文字重复朗读。

```diff
--- a/lib/apple_glass.dart
+++ b/lib/apple_glass.dart
@@ -151,6 +151,7 @@ class LiquidGlassActionButton extends StatelessWidget {
   final Color? color;
   final Color? borderColor;
+  final String? semanticLabel;
 
   const LiquidGlassActionButton({
     super.key,
@@ -163,6 +164,7 @@ class LiquidGlassActionButton extends StatelessWidget {
     this.color,
     this.borderColor,
+    this.semanticLabel,
   });
 
   @override
@@ -172,6 +174,7 @@ class LiquidGlassActionButton extends StatelessWidget {
 
     return GlassButton.custom(
       onTap: onTap,
+      label: semanticLabel ?? '',
       width: width,
       height: height,
```

### 2. `lib/views/cinema_view.dart`
1. 移除外层泄漏的 `Semantics(button: true, ...)`，将 `semanticLabel` 直接传递给 `LiquidGlassActionButton`；
2. 为成员行本身添加明确的 `Semantics(container: true, child: ...)`，将其显式定义为纯内容容器，消除任何意外继承的 `button` 角色：

```diff
--- a/lib/views/cinema_view.dart
+++ b/lib/views/cinema_view.dart
@@ -5895,11 +5895,13 @@ class _CinemaViewState extends State<CinemaView> {
               final isMemberAdmin = member.role == RoomRole.admin;
               final isMemberOwner = member.role == RoomRole.owner;
 
-              return Container(
-                decoration: BoxDecoration(
-                  color: tc.inputBackground,
-                  borderRadius: BorderRadius.circular(10),
-                ),
+              return Semantics(
+                container: true,
+                child: Container(
+                  decoration: BoxDecoration(
+                    color: tc.inputBackground,
+                    borderRadius: BorderRadius.circular(10),
+                  ),
                 padding: const EdgeInsets.symmetric(
                   horizontal: 12,
                   vertical: 8,
@@ -6118,32 +6120,29 @@ class _CinemaViewState extends State<CinemaView> {
                     // Owner ACL controls
                     if (isOwner && !isMe && !isMemberOwner) ...[
                       const SizedBox(width: 8),
-                      Semantics(
-                        button: true,
-                        enabled: true,
-                        label: isMemberAdmin
+                      LiquidGlassActionButton(
+                        key: ValueKey('member-acl-${member.deviceId}'),
+                        semanticLabel: isMemberAdmin
                             ? '${i18n.revokeAdmin}: ${member.displayName.isNotEmpty ? member.displayName : formatDeviceId(member.deviceId)}'
                             : '${i18n.grantAdmin}: ${member.displayName.isNotEmpty ? member.displayName : formatDeviceId(member.deviceId)}',
-                        child: LiquidGlassActionButton(
-                          key: ValueKey('member-acl-${member.deviceId}'),
-                          height: 30,
-                          onTap: () {
-                            if (isMemberAdmin) {
-                              widget.session.revokeAdmin(member.deviceId);
-                            } else {
-                              widget.session.grantAdmin(member.deviceId);
-                            }
-                          },
-                          child: Text(
-                            isMemberAdmin ? i18n.revokeAdmin : i18n.grantAdmin,
-                            style: const TextStyle(fontSize: 10.5),
-                          ),
+                        height: 30,
+                        onTap: () {
+                          if (isMemberAdmin) {
+                            widget.session.revokeAdmin(member.deviceId);
+                          } else {
+                            widget.session.grantAdmin(member.deviceId);
+                          }
+                        },
+                        child: Text(
+                          isMemberAdmin ? i18n.revokeAdmin : i18n.grantAdmin,
+                          style: const TextStyle(fontSize: 10.5),
                         ),
                       ),
                     ],
                   ],
                 ),
-              );
+              ),
+            );
             },
           ),
```

---

## 三、自动化语义树验证结果

新增专门的测试用例：[test/ui/member_semantics_test.dart](file:///workspace/projects/Eir/test/ui/member_semantics_test.dart)

测试用例覆盖三项关键断言：
1. **房主授予管理员**：
   - 成员行 `isButton == false`，无 `tap` 动作；
   - 动作按钮为该项**唯一**的 `isButton == true` 节点，`hasAction(SemanticsAction.tap) == true`，`label` 包含完整 `Grant Admin: BestFriendBob`；
   - 点击该按钮正确触发 `widget.session.grantAdmin(guestDeviceId)`。
2. **房主撤销管理员**：
   - 成员行 `isButton == false`，无 `tap` 动作；
   - 动作按钮为**唯一**的按钮节点，`label` 包含 `Revoke Admin: AdminCharlie`；
   - 点击该按钮正确触发 `widget.session.revokeAdmin(adminGuestId)`。
3. **普通成员（非房主）视角**：
   - 成员列表中不渲染 ACL 按钮；
   - 成员行全部为纯内容容器，`isButton == false`，无多余交互动作。

**测试执行结果**：
```
00:02 +3: All tests passed!
```

---

## 四、约束与范围说明

1. **外观零改变**：完全沿用 `LiquidGlassActionButton` 现有的高斯模糊、微质感超椭圆与配色规范，UI 视觉无任何变动。
2. **业务零改变**：授权/撤销逻辑直接透传至既有 `session.grantAdmin` / `session.revokeAdmin`。
3. **隔离 `_seekRelative`**：根据协调指示，相对 seek 逻辑正由其他代理处理，本轮完全未触碰 `_seekRelative`，避免代码冲突。
4. **无构建安装发布**：本轮不触发编译、打包或发布流程。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'app_localization.dart';
import 'app_settings.dart';

export 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
export 'app_settings.dart';

/// Cross-platform Apple typography fallbacks
const List<String> kAppleFontFallbacks = [
  '-apple-system',
  'BlinkMacSystemFont',
  'Segoe UI',
  'Roboto',
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'sans-serif',
];

/// Centralized Apple Semantic Colors System following docs/APP-SETTINGS.md
class ThemeColors {
  final BuildContext context;
  ThemeColors(this.context);

  static ThemeColors of(BuildContext context) {
    try {
      Theme.of(context);
    } catch (_) {}
    return ThemeColors(context);
  }

  bool get isDark => AppSettings.instance.isDarkMode(context);

  Color get primary => AppSettings.instance.getActiveThemeColor(context);

  Color get background => isDark
      ? const Color(0xFF090B10)
      : const Color(0xFFF3F5F9);

  Color get glassSurface => isDark
      ? const Color(0xFF161922).withValues(alpha: 0.65)
      : Colors.white.withValues(alpha: 0.76);

  Color get glassSurfaceSubtle => isDark
      ? const Color(0xFF1E222E).withValues(alpha: 0.50)
      : Colors.white.withValues(alpha: 0.52);

  Color get glassBorder => isDark
      ? Colors.white.withValues(alpha: 0.14)
      : Colors.black.withValues(alpha: 0.08);

  Color get glassBorderSubtle => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.05);

  Color get textPrimary => isDark
      ? Colors.white
      : const Color(0xFF0F172A);

  Color get textSecondary => isDark
      ? Colors.white.withValues(alpha: 0.68)
      : const Color(0xFF475569);

  Color get textTertiary => isDark
      ? Colors.white.withValues(alpha: 0.42)
      : const Color(0xFF64748B);

  Color get cardBackground => isDark
      ? const Color(0xFF141722).withValues(alpha: 0.78)
      : Colors.white.withValues(alpha: 0.88);

  Color get inputBackground => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.04);

  Color get ambientGlow1 => primary.withValues(alpha: isDark ? 0.22 : 0.14);

  Color get ambientGlow2 => (isDark
          ? const Color(0xFF5E5CE6)
          : const Color(0xFF5856D6))
      .withValues(alpha: isDark ? 0.16 : 0.10);

  Color get success => const Color(0xFF34C759);
  Color get warning => const Color(0xFFFF9500);
  Color get error => const Color(0xFFFF3B30);

  Color get destructiveGlassBackground => error.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get destructiveGlassBorder => error.withValues(alpha: isDark ? 0.38 : 0.28);
  Color get successGlassBackground => success.withValues(alpha: isDark ? 0.18 : 0.12);
  Color get warningGlassBackground => warning.withValues(alpha: isDark ? 0.18 : 0.12);
}

/// Compact glass tag/badge for statuses, labels, and metadata
class LiquidGlassTag extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Border? border;

  const LiquidGlassTag({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.borderRadius = 8.0,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final tc = ThemeColors.of(context);
    final bgColor = color ?? tc.glassSurfaceSubtle;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ??
            Border.all(
              color: tc.glassBorderSubtle,
              width: 0.5,
            ),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: tc.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          fontFamilyFallback: kAppleFontFallbacks,
          decoration: TextDecoration.none,
        ),
        child: child,
      ),
    );
  }
}

/// Refractive Liquid Glass Action Button using liquid_glass_widgets engine
class LiquidGlassActionButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isPrimary;
  final double? width;
  final double height;
  final double borderRadius;
  final Color? customColor;
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;

  const LiquidGlassActionButton({
    super.key,
    required this.child,
    required this.onTap,
    this.isPrimary = false,
    this.width,
    this.height = 44.0,
    this.borderRadius = 14.0,
    this.customColor,
    this.color,
    this.borderColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final tc = ThemeColors.of(context);
    final accent = customColor ?? tc.primary;

    return GlassButton.custom(
      onTap: onTap,
      label: semanticLabel ?? '',
      width: width,
      height: height,
      useOwnLayer: true,
      stretch: 0.15,
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      glowColor: isPrimary ? accent.withValues(alpha: 0.45) : null,
      glowRadius: isPrimary ? 1.4 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: (isPrimary || color != null || borderColor != null)
            ? BoxDecoration(
                color: isPrimary ? accent.withValues(alpha: 0.88) : color,
                borderRadius: BorderRadius.circular(borderRadius),
                border: borderColor == null
                    ? null
                    : Border.all(color: borderColor!, width: 0.8),
              )
            : null,
        child: Center(
          child: DefaultTextStyle(
            style: TextStyle(
              color: isPrimary ? Colors.white : tc.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
              letterSpacing: -0.2,
              fontFamilyFallback: kAppleFontFallbacks,
              decoration: TextDecoration.none,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: isPrimary ? Colors.white : tc.textPrimary,
                size: 16,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Background Ambient Canvas with dynamic refraction orbs
class LiquidGlassAmbientBackground extends StatelessWidget {
  final Widget child;

  const LiquidGlassAmbientBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tc = ThemeColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: TextStyle(
          color: tc.textPrimary,
          fontFamilyFallback: kAppleFontFallbacks,
          decoration: TextDecoration.none,
        ),
        child: Container(
          color: tc.background,
          child: Stack(
            children: [
              // Top Left Ambient Glow
              Positioned(
                top: -120,
                left: screenWidth * 0.12,
                child: IgnorePointer(
                  child: Container(
                    width: 520,
                    height: 520,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          tc.ambientGlow1,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom Right Ambient Glow
              Positioned(
                bottom: 80,
                right: screenWidth * 0.06,
                child: IgnorePointer(
                  child: Container(
                    width: 600,
                    height: 600,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          tc.ambientGlow2,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSnackBarRecord {
  final OverlayEntry entry;
  final Object? owner;

  _ActiveSnackBarRecord({
    required this.entry,
    required this.owner,
  });
}

_ActiveSnackBarRecord? _activeSnackBar;

/// Encapsulated host that binds the auto-dismiss Timer directly to the OverlayEntry's element lifecycle.
class _LiquidGlassSnackBarHost extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback onDismiss;

  const _LiquidGlassSnackBarHost({
    required this.child,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_LiquidGlassSnackBarHost> createState() => _LiquidGlassSnackBarHostState();
}

class _LiquidGlassSnackBarHostState extends State<_LiquidGlassSnackBarHost> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.duration > Duration.zero) {
      _timer = Timer(widget.duration, () {
        if (mounted) {
          widget.onDismiss();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Manually hides any currently visible Liquid Glass floating snackbar.
///
/// If [owner] is provided, only hides the snackbar if it was shown by that same [owner],
/// preventing a disposing page from accidentally dismissing another page's prompt.
void hideLiquidGlassSnackBar({Object? owner}) {
  final current = _activeSnackBar;
  if (current == null) return;
  if (owner != null && current.owner != null && current.owner != owner) {
    return;
  }
  _activeSnackBar = null;
  if (current.entry.mounted) {
    current.entry.remove();
  }
}

/// Displays a bottom floating liquid glass SnackBar for error notifications and feedback.
///
/// Automatically disappears after 5 seconds, provides an explicit close button,
/// positions itself above keyboard insets and bottom safe areas, and supports
/// accessibility (Semantics liveRegion), themes, and action/retry callbacks.
///
/// Implemented via Flutter's [Overlay] with [OverlayEntry] rather than [ScaffoldMessenger],
/// ensuring full compatibility with [GlassScaffold] / [CupertinoPageScaffold] where
/// no Material [Scaffold] exists in the descendant tree.
void showLiquidGlassSnackBar(
  BuildContext context, {
  required String message,
  Object? owner,
  String? title,
  IconData icon = Icons.error_outline_rounded,
  Color? iconColor,
  VoidCallback? onRetry,
  String? retryLabel,
  Key? retryKey,
  VoidCallback? onAction,
  String? actionLabel,
  Key? actionKey,
  IconData? actionIcon,
  Duration duration = const Duration(seconds: 5),
  double? bottomOffset,
  bool isRetry = false,
}) {
  if (!context.mounted) return;
  final effectiveOwner = owner ?? context;

  hideLiquidGlassSnackBar();
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();

  final overlay = Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
  if (overlay == null) {
    if (!isRetry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showLiquidGlassSnackBar(
          context,
          message: message,
          owner: effectiveOwner,
          title: title,
          icon: icon,
          iconColor: iconColor,
          onRetry: onRetry,
          retryLabel: retryLabel,
          retryKey: retryKey,
          onAction: onAction,
          actionLabel: actionLabel,
          actionKey: actionKey,
          actionIcon: actionIcon,
          duration: duration,
          bottomOffset: bottomOffset,
          isRetry: true,
        );
      });
    } else {
      // Safe fallback: if after 1 frame overlay is still not available, try ScaffoldMessenger if present; do NOT recurse
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null) {
        final tc = ThemeColors.of(context);
        final i18n = AppI18n.of(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            elevation: 0,
            backgroundColor: Colors.transparent,
            duration: duration,
            content: _buildSnackBarCard(
              context: context,
              tc: tc,
              i18n: i18n,
              title: title,
              message: message,
              icon: icon,
              iconColor: iconColor,
              onRetry: onRetry,
              retryLabel: retryLabel,
              retryKey: retryKey,
              onAction: onAction,
              actionLabel: actionLabel,
              actionKey: actionKey,
              actionIcon: actionIcon,
              onDismiss: () => scaffoldMessenger.hideCurrentSnackBar(),
            ),
          ),
        );
      }
    }
    return;
  }

  late final OverlayEntry entry;
  late final _ActiveSnackBarRecord record;

  void dismiss() {
    if (_activeSnackBar == record) {
      _activeSnackBar = null;
    }
    if (entry.mounted) {
      entry.remove();
    }
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      final mediaQuery = MediaQuery.of(overlayContext);
      final keyboardHeight = mediaQuery.viewInsets.bottom;
      final bottomSafeArea = mediaQuery.padding.bottom;
      final tc = ThemeColors.of(overlayContext);
      final i18n = AppI18n.of(overlayContext);

      final baseOffset = bottomOffset ?? 12.0;
      return Positioned(
        left: 16,
        right: 16,
        bottom: keyboardHeight > 0 ? keyboardHeight + 8 : bottomSafeArea + baseOffset,
        child: _LiquidGlassSnackBarHost(
          duration: duration,
          onDismiss: dismiss,
          child: Material(
            type: MaterialType.transparency,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0.0, end: 1.0),
              builder: (context, animValue, child) {
                return Opacity(
                  opacity: animValue,
                  child: Transform.translate(
                    offset: Offset(0, (1 - animValue) * 12),
                    child: child,
                  ),
                );
              },
              child: _buildSnackBarCard(
                context: overlayContext,
                tc: tc,
                i18n: i18n,
                title: title,
                message: message,
                icon: icon,
                iconColor: iconColor,
                onRetry: onRetry,
                retryLabel: retryLabel,
                retryKey: retryKey,
                onAction: onAction,
                actionLabel: actionLabel,
                actionKey: actionKey,
                actionIcon: actionIcon,
                onDismiss: dismiss,
              ),
            ),
          ),
        ),
      );
    },
  );

  record = _ActiveSnackBarRecord(entry: entry, owner: effectiveOwner);
  _activeSnackBar = record;
  overlay.insert(entry);
}

Widget _buildSnackBarCard({
  required BuildContext context,
  required ThemeColors tc,
  required AppI18n i18n,
  required String message,
  String? title,
  required IconData icon,
  Color? iconColor,
  VoidCallback? onRetry,
  String? retryLabel,
  Key? retryKey,
  VoidCallback? onAction,
  String? actionLabel,
  Key? actionKey,
  IconData? actionIcon,
  required VoidCallback onDismiss,
}) {
  return Semantics(
    container: true,
    liveRegion: true,
    label: title != null ? '$title: $message' : message,
    child: GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.isDark
          ? const Color(0xFF1E222E).withValues(alpha: 0.96)
          : Colors.white.withValues(alpha: 0.98),
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? tc.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: iconColor ?? tc.error,
                      fontFamilyFallback: kAppleFontFallbacks,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tc.textPrimary,
                    fontFamilyFallback: kAppleFontFallbacks,
                    decoration: TextDecoration.none,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: retryLabel ?? i18n.retryInit,
              child: LiquidGlassActionButton(
                key: retryKey,
                height: 30,
                onTap: () {
                  onDismiss();
                  onRetry();
                },
                child: Text(
                  retryLabel ?? i18n.retryInit,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: tc.primary,
                  ),
                ),
              ),
            ),
          ],
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: actionLabel,
              child: LiquidGlassActionButton(
                key: actionKey,
                height: 30,
                onTap: () {
                  onDismiss();
                  onAction();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actionIcon != null) ...[
                      Icon(actionIcon, size: 14, color: tc.primary),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      actionLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tc.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: i18n.close,
            child: Tooltip(
              message: i18n.close,
              child: GestureDetector(
                key: const ValueKey('snackbar-close-btn'),
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: tc.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

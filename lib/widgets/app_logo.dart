import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../app_settings.dart';
import '../apple_glass.dart';

/// Dynamic App Logo component that automatically adapts to the active theme color
/// or renders a user's custom picked emblem.
class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool useGradient;
  final bool hasGlow;

  const AppLogo({
    super.key,
    this.size = 28,
    this.color,
    this.useGradient = true,
    this.hasGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final tc = ThemeColors.of(context);
    final targetColor = color ?? tc.primary;
    final accentColor = Theme.of(context).colorScheme.secondary;
    final customPath = AppSettings.instance.customAppIconPath;

    // If user has a valid custom image, render it inside a glass rounded container
    Widget? customImageWidget;
    if (customPath != null && customPath.isNotEmpty) {
      if (kIsWeb && customPath.startsWith('data:')) {
        try {
          final bytes = base64Decode(customPath.split(',').last);
          customImageWidget = Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
          );
        } catch (_) {}
      } else if (!kIsWeb) {
        final file = File(customPath);
        if (file.existsSync()) {
          customImageWidget = Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
          );
        }
      }
    }

    if (customImageWidget != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          boxShadow: hasGlow
              ? [
                  BoxShadow(
                    color: targetColor.withValues(alpha: 0.35),
                    blurRadius: size * 0.3,
                    offset: Offset(0, size * 0.08),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: customImageWidget,
        ),
      );
    }

    Widget logoImage = Image.asset(
      'assets/images/app_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    if (useGradient) {
      logoImage = ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              targetColor,
              accentColor,
            ],
          ).createShader(bounds);
        },
        blendMode: BlendMode.srcIn,
        child: logoImage,
      );
    } else {
      logoImage = Image.asset(
        'assets/images/app_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: targetColor,
      );
    }

    if (!hasGlow) return logoImage;

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: targetColor.withValues(alpha: 0.35),
            blurRadius: size * 0.3,
            spreadRadius: 0,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: logoImage,
    );
  }
}

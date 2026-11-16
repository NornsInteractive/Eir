import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../core/update_service.dart';

/// Modal dialog providing direct mobile downloads for Android (with QR & link)
/// and indicating upcoming availability for iPhone / iPad.
class MobileDownloadDialog extends StatefulWidget {
  const MobileDownloadDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const MobileDownloadDialog(),
    );
  }

  @override
  State<MobileDownloadDialog> createState() => _MobileDownloadDialogState();
}

class _MobileDownloadDialogState extends State<MobileDownloadDialog> {
  int _selectedTabIndex = 0; // 0: Android, 1: iPhone
  bool _copied = false;
  Timer? _copyResetTimer;

  static const String _androidDownloadUrl =
      'https://ygg.norns.cc.cd/d/com.norns.eir';
  static const String _githubReleaseUrl =
      'https://github.com/NornsInteractive/Eir/releases/latest';

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  void _handleCopyLink(AppI18n i18n) {
    Clipboard.setData(const ClipboardData(text: _androidDownloadUrl));
    setState(() => _copied = true);
    _copyResetTimer?.cancel();
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _handleDownloadApk() async {
    final uri = Uri.parse(_androidDownloadUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _handleOpenGithub() async {
    final uri = Uri.parse(_githubReleaseUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isWide = screenWidth >= 640;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 680 : 380,
          maxHeight: 680,
        ),
        child: GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          color: tc.cardBackground,
          shape: const LiquidRoundedSuperellipse(borderRadius: 24),
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(context, i18n, tc),
              Divider(height: 1, thickness: 1, color: tc.glassBorderSubtle),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: isWide
                      ? _buildWideTwoColumns(context, i18n, tc)
                      : _buildNarrowTabs(context, i18n, tc),
                ),
              ),

              Divider(height: 1, thickness: 1, color: tc.glassBorderSubtle),

              // Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Norns Interactive · norns.cc.cd',
                      style: TextStyle(
                        fontSize: 11,
                        color: tc.textTertiary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    LiquidGlassActionButton(
                      height: 32,
                      isPrimary: false,
                      onTap: () => Navigator.of(context).pop(),
                      child: Text(
                        i18n.close,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tc.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tc.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.smartphone_rounded, color: tc.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  i18n.downloadAppTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tc.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  i18n.downloadAppSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: tc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: tc.textSecondary, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildWideTwoColumns(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Android (Ready)
        Expanded(
          child: _buildAndroidCard(context, i18n, tc),
        ),
        const SizedBox(width: 16),
        // Right Column: iPhone (Coming Soon)
        Expanded(
          child: _buildIosCard(context, i18n, tc),
        ),
      ],
    );
  }

  Widget _buildNarrowTabs(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: tc.inputBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  title: 'Android',
                  icon: Icons.android_rounded,
                  isSelected: _selectedTabIndex == 0,
                  tc: tc,
                  onTap: () => setState(() => _selectedTabIndex = 0),
                ),
              ),
              Expanded(
                child: _buildTabButton(
                  title: 'iPhone',
                  icon: Icons.apple_rounded,
                  isSelected: _selectedTabIndex == 1,
                  tc: tc,
                  onTap: () => setState(() => _selectedTabIndex = 1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _selectedTabIndex == 0
            ? _buildAndroidCard(context, i18n, tc)
            : _buildIosCard(context, i18n, tc),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required ThemeColors tc,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? tc.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? tc.primary : tc.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? tc.textPrimary : tc.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAndroidCard(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
  ) {
    final currentVer = UpdateService.currentVersionName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.inputBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tc.glassBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Platform Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.android_rounded, color: Colors.green, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.androidClient,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: tc.textPrimary,
                      ),
                    ),
                    Text(
                      'v$currentVer · Universal APK',
                      style: TextStyle(
                        fontSize: 11,
                        color: tc.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '正式可用',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // QR Code Card
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: QrImageView(
                data: _androidDownloadUrl,
                version: QrVersions.auto,
                size: 132,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            i18n.scanQrToDownload,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: tc.textTertiary,
            ),
          ),
          const SizedBox(height: 14),

          // Action 1: Download APK
          LiquidGlassActionButton(
            height: 38,
            isPrimary: true,
            onTap: _handleDownloadApk,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.download_rounded, size: 16),
                const SizedBox(width: 6),
                Text(
                  i18n.downloadApk,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Action 2: Copy Direct Link
          LiquidGlassActionButton(
            height: 34,
            isPrimary: false,
            onTap: () => _handleCopyLink(i18n),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _copied ? Icons.check_rounded : Icons.link_rounded,
                  size: 15,
                  color: _copied ? Colors.green : tc.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  _copied ? i18n.downloadLinkCopied : i18n.copyDownloadLink,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _copied ? Colors.green : tc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // GitHub Link
          GestureDetector(
            onTap: _handleOpenGithub,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    i18n.viewOnGithub,
                    style: TextStyle(
                      fontSize: 11,
                      color: tc.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.open_in_new_rounded, size: 11, color: tc.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIosCard(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.inputBackground.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tc.glassBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Platform Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tc.textPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.apple_rounded, color: tc.textPrimary, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i18n.iosClient,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: tc.textPrimary,
                      ),
                    ),
                    Text(
                      'iOS 16+ / iPadOS',
                      style: TextStyle(
                        fontSize: 11,
                        color: tc.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tc.textTertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  i18n.iosComingSoon,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: tc.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Placeholder Illustration / Badge
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: tc.glassSurfaceSubtle,
                shape: BoxShape.circle,
                border: Border.all(color: tc.glassBorderSubtle),
              ),
              child: Icon(
                Icons.hourglass_top_rounded,
                size: 38,
                color: tc.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Description
          Text(
            i18n.iosDesc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: tc.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),

          // Disabled Button
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: tc.inputBackground.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                'TestFlight 公测筹备中',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: tc.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

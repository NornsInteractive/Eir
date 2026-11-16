import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_localization.dart';
import '../apple_glass.dart';
import '../models.dart';
import '../core/update_service.dart';
import 'settings_dialog.dart';
import '../widgets/app_logo.dart';

class AvatarPreset {
  final String key;
  final String nameZh;
  final String nameEn;
  final List<Color> colors;
  final IconData icon;

  const AvatarPreset({
    required this.key,
    required this.nameZh,
    required this.nameEn,
    required this.colors,
    required this.icon,
  });

  String localizedName(bool isZh) => isZh ? nameZh : nameEn;
}

const List<AvatarPreset> kAvatarPresets = [
  AvatarPreset(
    key: 'preset:aurora',
    nameZh: '极光青绿',
    nameEn: 'Aurora Green',
    colors: [Color(0xFF00C9A7), Color(0xFF00897B)],
    icon: Icons.auto_awesome_rounded,
  ),
  AvatarPreset(
    key: 'preset:nebula',
    nameZh: '星云紫罗',
    nameEn: 'Nebula Violet',
    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    icon: Icons.nights_stay_rounded,
  ),
  AvatarPreset(
    key: 'preset:sunset',
    nameZh: '落日暖杏',
    nameEn: 'Sunset Amber',
    colors: [Color(0xFFFF8008), Color(0xFFFFC837)],
    icon: Icons.wb_sunny_rounded,
  ),
  AvatarPreset(
    key: 'preset:cyber',
    nameZh: '赛博电蓝',
    nameEn: 'Cyber Cyan',
    colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
    icon: Icons.bolt_rounded,
  ),
  AvatarPreset(
    key: 'preset:rose',
    nameZh: '晚霞绛粉',
    nameEn: 'Sunset Rose',
    colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
    icon: Icons.favorite_rounded,
  ),
  AvatarPreset(
    key: 'preset:obsidian',
    nameZh: '深曜岩灰',
    nameEn: 'Obsidian Slate',
    colors: [Color(0xFF434343), Color(0xFF1A1A1A)],
    icon: Icons.diamond_rounded,
  ),
  AvatarPreset(
    key: 'preset:emerald',
    nameZh: '翠羽碧透',
    nameEn: 'Emerald Spark',
    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
    icon: Icons.spa_rounded,
  ),
  AvatarPreset(
    key: 'preset:flame',
    nameZh: '烈焰赤曜',
    nameEn: 'Crimson Flame',
    colors: [Color(0xFFED213A), Color(0xFF93291E)],
    icon: Icons.local_fire_department_rounded,
  ),
];

AvatarPreset getAvatarPreset(String? key, [String? fallbackSeed]) {
  if (key != null && key.isNotEmpty) {
    for (final p in kAvatarPresets) {
      if (p.key == key) return p;
    }
  }
  if (fallbackSeed != null && fallbackSeed.isNotEmpty) {
    final idx = fallbackSeed.hashCode.abs() % kAvatarPresets.length;
    return kAvatarPresets[idx];
  }
  return kAvatarPresets[0];
}

/// Reusable Apple liquid-glass user avatar component
class UserAvatar extends StatelessWidget {
  final String? avatarKey;
  final String? fallbackSeed;
  final double size;
  final VoidCallback? onTap;
  final bool showEditBadge;

  const UserAvatar({
    super.key,
    this.avatarKey,
    this.fallbackSeed,
    this.size = 56,
    this.onTap,
    this.showEditBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveKey = (avatarKey != null && avatarKey!.isNotEmpty)
        ? avatarKey!
        : (fallbackSeed != null && fallbackSeed!.isNotEmpty
            ? null
            : AppSettings.instance.avatar);

    final isCustomPath = effectiveKey != null &&
        !effectiveKey.startsWith('preset:') &&
        !kIsWeb &&
        File(effectiveKey).existsSync();

    final preset = getAvatarPreset(effectiveKey, fallbackSeed);

    Widget avatarCore;
    if (isCustomPath) {
      avatarCore = ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.file(
          File(effectiveKey),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPresetFallback(preset),
        ),
      );
    } else {
      avatarCore = _buildPresetFallback(preset);
    }

    final avatarWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        avatarCore,
        if (showEditBadge)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: ThemeColors.of(context).background,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.edit_rounded,
                color: Colors.white,
                size: size * 0.18,
              ),
            ),
          ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: avatarWithBadge,
      );
    }

    return avatarWithBadge;
  }

  Widget _buildPresetFallback(AvatarPreset preset) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors,
        ),
        boxShadow: [
          BoxShadow(
            color: preset.colors.first.withValues(alpha: 0.35),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          preset.icon,
          color: Colors.white,
          size: size * 0.50,
        ),
      ),
    );
  }
}

/// The "我的" (Profile) View
class ProfileView extends StatefulWidget {
  final RoomSession? session;

  const ProfileView({super.key, this.session});

  static Future<void> show(BuildContext context, {RoomSession? session}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: ProfileView(session: session),
        ),
      ),
    );
  }

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final TextEditingController _nicknameController;
  bool _isEditingNickname = false;
  bool _isCleaningCache = false;
  bool _isCheckingUpdate = false;
  String? _statusFeedback;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: AppSettings.instance.nickname,
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _nicknameController.dispose();
    super.dispose();
  }

  void _showFeedback(String msg) {
    _feedbackTimer?.cancel();
    setState(() => _statusFeedback = msg);
    _feedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _statusFeedback = null);
    });
  }

  void _saveNickname() async {
    final newName = _nicknameController.text.trim();
    await AppSettings.instance.setNickname(newName);
    if (mounted) {
      setState(() {
        _isEditingNickname = false;
      });
      _showFeedback(AppI18n.of(context).nicknameSaved);
    }
  }

  void _openAvatarPickerSheet() {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: tc.isDark ? const Color(0xFF1E222D) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    i18n.selectAvatarPreset,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: tc.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(sheetContext).pop(),
                    child: Icon(Icons.close_rounded, color: tc.textSecondary, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Preset Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.82,
                ),
                itemCount: kAvatarPresets.length,
                itemBuilder: (ctx, idx) {
                  final preset = kAvatarPresets[idx];
                  final isSelected = AppSettings.instance.avatar == preset.key;

                  return GestureDetector(
                    onTap: () async {
                      await AppSettings.instance.setAvatar(preset.key);
                      if (mounted) setState(() {});
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? tc.primary : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: UserAvatar(
                            avatarKey: preset.key,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preset.localizedName(i18n.isZh),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? tc.primary : tc.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Custom image button (native only)
              if (!kIsWeb)
                InkWell(
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: false,
                      );
                      if (result != null && result.files.isNotEmpty) {
                        final path = result.files.first.path;
                        if (path != null && path.isNotEmpty) {
                          await AppSettings.instance.setAvatar(path);
                          if (mounted) setState(() {});
                        }
                      }
                    } catch (_) {}
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: tc.inputBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 18, color: tc.primary),
                        const SizedBox(width: 8),
                        Text(
                          i18n.customAvatar,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: tc.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _copyDeviceId(String deviceId) {
    if (deviceId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: deviceId));
    _showFeedback(AppI18n.of(context).copiedToClipboard);
  }

  void _clearMediaCache() async {
    setState(() => _isCleaningCache = true);
    try {
      final session = widget.session;
      if (session != null) {
        await session.clearUnprotectedCache();
      }
      if (mounted) {
        setState(() => _isCleaningCache = false);
        _showFeedback(AppI18n.of(context).cacheCleared);
      }
    } catch (_) {
      if (mounted) setState(() => _isCleaningCache = false);
    }
  }

  void _handleCheckUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    try {
      final update = await UpdateService.checkUpdate();
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);
      if (update != null && update.hasUpdate) {
        AppSettings.instance.setPendingUpdate(true);
        UpdateDialog.show(context, update);
      } else {
        AppSettings.instance.setPendingUpdate(false);
        _showFeedback(AppI18n.of(context).latestVersionAlready);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        _showFeedback(AppI18n.of(context).updateCheckFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final session = widget.session;
    final deviceId = session?.identity.deviceId ?? '';

    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        final currentNick = settings.nickname.trim().isNotEmpty
            ? settings.nickname.trim()
            : i18n.defaultUserNickname;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status feedback pill
                  if (_statusFeedback != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: tc.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tc.primary.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 16, color: tc.primary),
                            const SizedBox(width: 6),
                            Text(
                              _statusFeedback!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: tc.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Hero Profile Card
                  GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.solid,
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        // Avatar with Edit Badge
                        UserAvatar(
                          avatarKey: settings.avatar,
                          size: 78,
                          showEditBadge: true,
                          onTap: _openAvatarPickerSheet,
                        ),
                        const SizedBox(height: 14),

                        // Nickname Display / Editor
                        if (!_isEditingNickname)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  _nicknameController.text = settings.nickname;
                                  setState(() => _isEditingNickname = true);
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        currentNick,
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.4,
                                          color: tc.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.edit_outlined, size: 16, color: tc.textTertiary),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Shuffle / Randomize button
                              Tooltip(
                                message: i18n.shuffleNickname,
                                child: GestureDetector(
                                  onTap: () async {
                                    await AppSettings.instance.randomizeNickname();
                                    _showFeedback(i18n.nicknameSaved);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: tc.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.shuffle_rounded, size: 14, color: tc.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          i18n.shuffleNickname,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: tc.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: tc.inputBackground,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: tc.primary),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: TextField(
                                    controller: _nicknameController,
                                    autofocus: true,
                                    maxLength: 20,
                                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                                    style: TextStyle(fontSize: 14, color: tc.textPrimary),
                                    decoration: InputDecoration(
                                      hintText: i18n.nicknameHint,
                                      hintStyle: TextStyle(fontSize: 12.5, color: tc.textTertiary),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    onSubmitted: (_) => _saveNickname(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _saveNickname,
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: tc.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    i18n.save,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => setState(() => _isEditingNickname = false),
                                child: Container(
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: tc.inputBackground,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(Icons.close_rounded, size: 18, color: tc.textSecondary),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 10),

                        // Device ID Pill
                        if (deviceId.isNotEmpty)
                          GestureDetector(
                            onTap: () => _copyDeviceId(deviceId),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: tc.inputBackground,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fingerprint_rounded, size: 14, color: tc.textSecondary),
                                  const SizedBox(width: 5),
                                  Text(
                                    formatDeviceId(deviceId),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      color: tc.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.copy_rounded, size: 12, color: tc.textTertiary),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Settings & Preferences Entry Group
                  GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.solid,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                    child: Column(
                      children: [
                        // Preferences Tile (Theme, Color, Language, Signaling)
                        _buildActionRow(
                          icon: Icons.tune_rounded,
                          iconColor: tc.primary,
                          title: i18n.preferencesAndSettings,
                          subtitle: i18n.isZh ? '外观配色与信令' : 'Theme, Language & Signaling',
                          onTap: () => SettingsDialog.show(context, session: widget.session),
                          trailing: Icon(Icons.chevron_right_rounded, color: tc.textTertiary, size: 20),
                        ),
                        Divider(height: 1, color: tc.glassBorderSubtle),

                        // Storage & Cache Tile
                        _buildActionRow(
                          icon: Icons.cleaning_services_rounded,
                          iconColor: const Color(0xFFFF9500),
                          title: i18n.storageAndCache,
                          subtitle: _isCleaningCache ? '正在清理...' : i18n.clearCache,
                          onTap: _isCleaningCache ? null : _clearMediaCache,
                          trailing: _isCleaningCache
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.chevron_right_rounded, color: tc.textTertiary, size: 20),
                        ),
                        Divider(height: 1, color: tc.glassBorderSubtle),

                        // Network & Signaling Status
                        _buildActionRow(
                          icon: Icons.wifi_tethering_rounded,
                          iconColor: const Color(0xFF34C759),
                          title: i18n.networkAndSignaling,
                          subtitle: settings.signalingUrl,
                          trailing: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (session?.connectionState == RoomConnectionState.connected)
                                  ? const Color(0xFF34C759)
                                  : tc.textTertiary,
                            ),
                          ),
                        ),
                        if (!kIsWeb) ...[
                          Divider(height: 1, color: tc.glassBorderSubtle),

                          // Check Update Tile (Native only)
                          _buildActionRow(
                            icon: Icons.system_update_rounded,
                            iconColor: const Color(0xFF007AFF),
                            title: i18n.checkUpdate,
                            showRedDot: settings.hasPendingUpdate,
                            subtitle: _isCheckingUpdate
                                ? i18n.checkingUpdate
                                : '${i18n.currentVersion} v${UpdateService.currentVersionName} (${UpdateService.currentPlatform})',
                            onTap: _isCheckingUpdate ? null : _handleCheckUpdate,
                            trailing: _isCheckingUpdate
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (settings.hasPendingUpdate) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'NEW',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Icon(Icons.chevron_right_rounded,
                                          color: tc.textTertiary, size: 20),
                                    ],
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // About Card
                  GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.solid,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: tc.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: AppLogo(size: 18, color: Colors.white, useGradient: false, hasGlow: false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Eir',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: tc.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  Text(
                                    i18n.footerText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tc.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: tc.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'v${UpdateService.currentVersionName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: tc.primary,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Divider(height: 1, color: tc.glassBorderSubtle),
                        const SizedBox(height: 12),
                        // Organization Row
                        Row(
                          children: [
                            Text(
                              i18n.organizationTitle,
                              style: TextStyle(fontSize: 12, color: tc.textTertiary),
                            ),
                            const Spacer(),
                            Text(
                              i18n.organizationName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: tc.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Official Website Row
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse(i18n.officialWebsiteUrl);
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {
                              await launchUrl(uri, mode: LaunchMode.platformDefault);
                            }
                          },
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: i18n.officialWebsiteUrl));
                            _showFeedback(i18n.copiedToClipboard);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            children: [
                              Text(
                                i18n.officialWebsiteTitle,
                                style: TextStyle(fontSize: 12, color: tc.textTertiary),
                              ),
                              const Spacer(),
                              Text(
                                'norns.cc.cd',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tc.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.open_in_new_rounded, size: 13, color: tc.primary),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Copyright
                        Center(
                          child: Text(
                            i18n.copyrightText,
                            style: TextStyle(fontSize: 10.5, color: tc.textTertiary),
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
      },
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool showRedDot = false,
  }) {
    final tc = ThemeColors.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: tc.textPrimary,
                        ),
                      ),
                      if (showRedDot) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tc.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app_localization.dart';
import '../apple_glass.dart';

/// Configuration options selected from the dialog
class ScreenShareOptions {
  final DesktopCapturerSource? source;
  final bool shareAudio;
  final int fps;
  final String? customTitle;
  final bool enableFloatingChat;

  const ScreenShareOptions({
    this.source,
    this.shareAudio = true,
    this.fps = 60,
    this.customTitle,
    this.enableFloatingChat = true,
  });
}

/// Adaptive Dialog/Sheet for choosing screen or window capture source
class ScreenSourcePickerDialog {
  static Future<ScreenShareOptions?> show(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 768 ||
        (!kIsWeb && (WebRTC.platformIsAndroid || WebRTC.platformIsIOS));

    if (isMobile) {
      return showModalBottomSheet<ScreenShareOptions>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => const _MobileScreenSharePickerSheet(),
      );
    }

    return showDialog<ScreenShareOptions>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _DesktopScreenSourcePickerDialog(),
    );
  }
}

/// Mobile Apple Inset-Grouped Modal Sheet for screen sharing
class _MobileScreenSharePickerSheet extends StatefulWidget {
  const _MobileScreenSharePickerSheet();

  @override
  State<_MobileScreenSharePickerSheet> createState() => _MobileScreenSharePickerSheetState();
}

class _MobileScreenSharePickerSheetState extends State<_MobileScreenSharePickerSheet> {
  bool _shareAudio = true;
  bool _highFps = true;
  late bool _enableFloatingChat;
  bool? _hasOverlayPermission;

  @override
  void initState() {
    super.initState();
    _enableFloatingChat = AppSettings.instance.enableCastFloatingChat;
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (!kIsWeb && WebRTC.platformIsAndroid) {
      try {
        final has = await const MethodChannel('com.norns.eir/media_picker')
            .invokeMethod<bool>('checkOverlayPermission');
        if (mounted) setState(() => _hasOverlayPermission = has);
      } catch (_) {}
    }
  }

  Future<void> _requestPermission(AppI18n i18n, ThemeColors tc) async {
    if (!kIsWeb && WebRTC.platformIsAndroid) {
      try {
        final grant = await showDialog<bool>(
          context: context,
          builder: (ctx) => Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassContainer.card(
                surfaceStyle: GlassSurfaceStyle.solid,
                color: tc.cardBackground,
                shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: tc.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.layers_rounded, color: tc.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            i18n.overlayPermissionTitle,
                            style: TextStyle(
                              color: tc.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      i18n.overlayPermissionDesc,
                      style: TextStyle(color: tc.textSecondary, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        LiquidGlassActionButton(
                          height: 38,
                          onTap: () => Navigator.pop(ctx, false),
                          child: Text(
                            i18n.cancel,
                            style: TextStyle(color: tc.textSecondary, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 10),
                        LiquidGlassActionButton(
                          height: 38,
                          isPrimary: true,
                          onTap: () => Navigator.pop(ctx, true),
                          child: Text(
                            i18n.grantPermission,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (grant == true) {
          await const MethodChannel('com.norns.eir/media_picker')
              .invokeMethod('requestOverlayPermission');
          await Future.delayed(const Duration(milliseconds: 500));
          await _checkPermission();
        }
      } catch (e) {
        debugPrint('[MobilePicker] requestOverlayPermission error: $e');
      }
    }
  }

  Future<void> _onToggleFloatingChat(bool val, AppI18n i18n, ThemeColors tc) async {
    setState(() => _enableFloatingChat = val);
    await AppSettings.instance.setEnableCastFloatingChat(val);

    if (val && _hasOverlayPermission == false) {
      await _requestPermission(i18n, tc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: GlassContainer.card(
            surfaceStyle: GlassSurfaceStyle.solid,
            color: tc.cardBackground,
            shape: const LiquidRoundedSuperellipse(borderRadius: 28),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top drag capsule indicator
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: tc.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tc.primary, tc.primary.withValues(alpha: 0.75)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: tc.primary.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.screen_share_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i18n.mobileCastTitle,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: tc.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            i18n.mobileCastSubtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: tc.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 20, color: tc.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Inset Grouped Settings Box
                GlassContainer.card(
                  surfaceStyle: GlassSurfaceStyle.solid,
                  color: tc.inputBackground.withValues(alpha: 0.5),
                  shape: const LiquidRoundedSuperellipse(borderRadius: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // Setting 1: System Audio
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: tc.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.volume_up_rounded, color: tc.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i18n.mobileShareAudioTitle,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: tc.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    i18n.mobileShareAudioDesc,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tc.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _shareAudio,
                              activeColor: tc.primary,
                              onChanged: (val) => setState(() => _shareAudio = val),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: tc.glassBorderSubtle, height: 1),
                      // Setting 2: 60 FPS Motion
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.speed_rounded, color: Colors.amber, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i18n.mobileShareFpsTitle,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: tc.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    i18n.mobileShareFpsDesc,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tc.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _highFps,
                              activeColor: tc.primary,
                              onChanged: (val) => setState(() => _highFps = val),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: tc.glassBorderSubtle, height: 1),
                      // Setting 3: Floating Chat Bubble
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.teal, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i18n.mobileFloatingChatTitle,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: tc.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    i18n.mobileFloatingChatDesc,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tc.textTertiary,
                                    ),
                                  ),
                                  if (_enableFloatingChat && _hasOverlayPermission == false) ...[
                                    const SizedBox(height: 5),
                                    GestureDetector(
                                      onTap: () => _requestPermission(i18n, tc),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.shield_outlined, size: 12, color: Colors.amber),
                                            const SizedBox(width: 4),
                                            Text(
                                              i18n.overlayPermissionBadgePrompt,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _enableFloatingChat,
                              activeColor: tc.primary,
                              onChanged: (val) => _onToggleFloatingChat(val, i18n, tc),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Friendly Tip Callout
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: tc.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tc.primary.withValues(alpha: 0.16), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 16, color: tc.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          i18n.mobileCastHint,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: tc.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Action Buttons
                LiquidGlassActionButton(
                  key: const ValueKey('confirm-start-cast-btn'),
                  isPrimary: true,
                  height: 46,
                  onTap: () {
                    Navigator.of(context).pop(ScreenShareOptions(
                      source: null,
                      shareAudio: _shareAudio,
                      fps: _highFps ? 60 : 30,
                      enableFloatingChat: _enableFloatingChat,
                    ));
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        i18n.startScreenShare,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                LiquidGlassActionButton(
                  height: 40,
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(
                    i18n.cancel,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: tc.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop/Web Screen and Window Picker Dialog
class _DesktopScreenSourcePickerDialog extends StatefulWidget {
  const _DesktopScreenSourcePickerDialog();

  @override
  State<_DesktopScreenSourcePickerDialog> createState() => _DesktopScreenSourcePickerDialogState();
}

class _DesktopScreenSourcePickerDialogState extends State<_DesktopScreenSourcePickerDialog> {
  final List<DesktopCapturerSource> _windows = [];
  final List<DesktopCapturerSource> _screens = [];
  final List<StreamSubscription> _subscriptions = [];
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  int _selectedTabIndex = 0; // 0 = Windows, 1 = Screens
  String _searchQuery = '';
  DesktopCapturerSource? _selectedSource;
  bool _shareAudio = true;
  bool _highFps = true;

  bool get _isDesktop => !kIsWeb && (WebRTC.platformIsWindows || WebRTC.platformIsMacOS || WebRTC.platformIsDesktop);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _loadDesktopSources();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadDesktopSources() async {
    setState(() => _isLoading = true);
    try {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen, SourceType.Window],
      );

      _windows.clear();
      _screens.clear();

      for (final s in sources) {
        if (s.type == SourceType.Window) {
          _windows.add(s);
        } else {
          _screens.add(s);
        }
      }

      if (_windows.isNotEmpty) {
        _selectedSource = _windows.first;
      } else if (_screens.isNotEmpty) {
        _selectedSource = _screens.first;
        _selectedTabIndex = 1;
      }
    } catch (e) {
      debugPrint('[ScreenSourcePickerDialog] load sources error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          color: tc.cardBackground,
          shape: const LiquidRoundedSuperellipse(borderRadius: 24),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(context, i18n, tc),
              Divider(height: 1, thickness: 1, color: tc.glassBorderSubtle),

              // Content Body
              Expanded(
                child: kIsWeb
                    ? _buildWebNotice(context, i18n, tc)
                    : _buildDesktopSourceGrid(context, i18n, tc),
              ),

              Divider(height: 1, thickness: 1, color: tc.glassBorderSubtle),

              // Options Footer & Action Buttons
              _buildFooter(context, i18n, tc),
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tc.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.screen_share_rounded,
              color: tc.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.selectSourceTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: tc.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  i18n.selectSourceDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: tc.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: tc.textSecondary, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSourceGrid(BuildContext context, AppI18n i18n, ThemeColors tc) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: tc.primary,
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final filteredWindows = query.isEmpty
        ? _windows
        : _windows.where((w) => w.name.toLowerCase().contains(query)).toList();
    final activeSources = _selectedTabIndex == 0 ? filteredWindows : _screens;

    return Column(
      children: [
        // Tab switcher & search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: tc.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabPill(
                          title: i18n.shareAppWindow,
                          icon: Icons.window_rounded,
                          count: filteredWindows.length,
                          isSelected: _selectedTabIndex == 0,
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 0;
                              if (filteredWindows.isNotEmpty) {
                                _selectedSource = filteredWindows.first;
                              }
                            });
                          },
                          tc: tc,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildTabPill(
                          title: i18n.shareEntireScreen,
                          icon: Icons.desktop_windows_rounded,
                          count: _screens.length,
                          isSelected: _selectedTabIndex == 1,
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 1;
                              if (_screens.isNotEmpty) {
                                _selectedSource = _screens.first;
                              }
                            });
                          },
                          tc: tc,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: i18n.refreshSources,
                child: InkWell(
                  onTap: _loadDesktopSources,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tc.inputBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.refresh_rounded, size: 18, color: tc.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Search textfield if on window tab
        if (_selectedTabIndex == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: tc.inputBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tc.glassBorderSubtle, width: 0.8),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 16, color: tc.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(fontSize: 12.5, color: tc.textPrimary),
                      decoration: InputDecoration(
                        hintText: i18n.searchWindowsHint,
                        hintStyle: TextStyle(fontSize: 12, color: tc.textTertiary),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Icon(Icons.close_rounded, size: 16, color: tc.textSecondary),
                    ),
                ],
              ),
            ),
          ),

        // Grid of sources
        Expanded(
          child: activeSources.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.layers_clear_rounded, size: 40, color: tc.textTertiary),
                      const SizedBox(height: 10),
                      Text(
                        _selectedTabIndex == 0 ? i18n.noWindowsFound : i18n.noScreensFound,
                        style: TextStyle(fontSize: 13, color: tc.textSecondary),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  itemCount: activeSources.length,
                  itemBuilder: (ctx, index) {
                    final s = activeSources[index];
                    final isSelected = _selectedSource?.id == s.id;
                    return _buildSourceCard(s, isSelected, tc, i18n);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabPill({
    required String title,
    required IconData icon,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeColors tc,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? tc.cardBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
              size: 15,
              color: isSelected ? tc.primary : tc.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '$title ($count)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? tc.textPrimary : tc.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(
    DesktopCapturerSource s,
    bool isSelected,
    ThemeColors tc,
    AppI18n i18n,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _selectedSource = s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? tc.primary.withValues(alpha: 0.08)
              : tc.inputBackground.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? tc.primary : tc.glassBorderSubtle.withValues(alpha: 0.6),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: tc.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail preview
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: _ThumbnailView(source: s),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: tc.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            // Title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tc.cardBackground.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    s.type == SourceType.Window ? Icons.window_rounded : Icons.desktop_windows_rounded,
                    size: 14,
                    color: isSelected ? tc.primary : tc.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.name.isEmpty ? i18n.fallbackWindowName(s.id) : s.name,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? tc.primary : tc.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebNotice(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tc.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.language_rounded, size: 48, color: tc.primary),
          ),
          const SizedBox(height: 18),
          Text(
            i18n.browserScreenShareSupport,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: tc.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            i18n.browserScreenShareDesc,
            style: TextStyle(
              fontSize: 13,
              color: tc.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          // Audio & FPS switches
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _shareAudio = !_shareAudio),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _shareAudio ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        size: 16,
                        color: _shareAudio ? tc.primary : tc.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        i18n.shareSystemAudio,
                        style: TextStyle(
                          fontSize: 12,
                          color: _shareAudio ? tc.textPrimary : tc.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _highFps = !_highFps),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 16,
                        color: _highFps ? Colors.amber : tc.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        i18n.fpsHighProfile,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _highFps ? tc.textPrimary : tc.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          LiquidGlassActionButton(
            height: 38,
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              i18n.cancel,
              style: TextStyle(color: tc.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          LiquidGlassActionButton(
            key: const ValueKey('confirm-start-cast-btn'),
            isPrimary: true,
            height: 38,
            onTap: () {
              Navigator.of(context).pop(ScreenShareOptions(
                source: _isDesktop ? _selectedSource : null,
                shareAudio: _shareAudio,
                fps: _highFps ? 60 : 30,
                customTitle: _selectedSource?.name,
              ));
            },
            child: Text(
              i18n.startScreenShare,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailView extends StatefulWidget {
  final DesktopCapturerSource source;
  const _ThumbnailView({required this.source});

  @override
  State<_ThumbnailView> createState() => _ThumbnailViewState();
}

class _ThumbnailViewState extends State<_ThumbnailView> {
  StreamSubscription? _sub;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.source.thumbnail;
    _sub = widget.source.onThumbnailChanged.stream.listen((bytes) {
      if (mounted) setState(() => _bytes = bytes);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    return Container(
      color: Colors.black12,
      child: const Center(
        child: Icon(Icons.desktop_windows_outlined, color: Colors.grey, size: 32),
      ),
    );
  }
}

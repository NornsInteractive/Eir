import 'package:flutter/material.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../models.dart';

class SettingsDialog extends StatefulWidget {
  final RoomSession? session;

  const SettingsDialog({super.key, this.session});

  static Future<void> show(BuildContext context, {RoomSession? session}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => SettingsDialog(session: session),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _signalingController;
  bool _isCleaningCache = false;
  String? _cacheCleanMessage;
  bool? _cacheCleanSuccess;
  bool _isSavingSignaling = false;
  String? _signalingFeedback;
  bool _signalingFeedbackIsError = false;

  static const List<Map<String, dynamic>> _lightPresets = [
    {'key': 'blue', 'color': Color(0xFF007AFF)},
    {'key': 'purple', 'color': Color(0xFF5856D6)},
    {'key': 'green', 'color': Color(0xFF34C759)},
    {'key': 'orange', 'color': Color(0xFFFF9500)},
    {'key': 'pink', 'color': Color(0xFFFF2D55)},
    {'key': 'teal', 'color': Color(0xFF30B0C7)},
  ];

  static const List<Map<String, dynamic>> _darkPresets = [
    {'key': 'blue', 'color': Color(0xFF0A84FF)},
    {'key': 'purple', 'color': Color(0xFF5E5CE6)},
    {'key': 'green', 'color': Color(0xFF30D158)},
    {'key': 'orange', 'color': Color(0xFFFF9F0A)},
    {'key': 'pink', 'color': Color(0xFFFF375F)},
    {'key': 'teal', 'color': Color(0xFF40C8E0)},
  ];

  @override
  void initState() {
    super.initState();
    _signalingController =
        TextEditingController(text: AppSettings.instance.signalingUrl);
    _signalingController.addListener(_onSignalingDraftChanged);
  }

  @override
  void dispose() {
    _signalingController.removeListener(_onSignalingDraftChanged);
    _signalingController.dispose();
    super.dispose();
  }

  void _onSignalingDraftChanged() {
    if (_signalingFeedback != null && !_isSavingSignaling) {
      setState(() {
        _signalingFeedback = null;
        _signalingFeedbackIsError = false;
      });
    }
  }

  String _getColorName(AppI18n i18n, String key) {
    switch (key) {
      case 'blue':
        return i18n.colorAppleBlue;
      case 'purple':
        return i18n.colorApplePurple;
      case 'green':
        return i18n.colorAppleGreen;
      case 'orange':
        return i18n.colorAppleOrange;
      case 'pink':
        return i18n.colorApplePink;
      case 'teal':
        return i18n.colorAppleTeal;
      default:
        return key;
    }
  }

  int _getLanguageIndex(Locale? locale) {
    if (locale == null) return 0;
    if (locale.languageCode == 'zh') return 1;
    return 2;
  }

  void _onLanguageSelected(int index) {
    final settings = AppSettings.instance;
    if (index == 0) {
      settings.setLocale(null);
    } else if (index == 1) {
      settings.setLocale(const Locale('zh', 'CN'));
    } else {
      settings.setLocale(const Locale('en', 'US'));
    }
  }

  int _getThemeModeIndex(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 0;
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
    }
  }

  void _onThemeModeSelected(int index) {
    final settings = AppSettings.instance;
    if (index == 0) {
      settings.setThemeMode(ThemeMode.system);
    } else if (index == 1) {
      settings.setThemeMode(ThemeMode.light);
    } else {
      settings.setThemeMode(ThemeMode.dark);
    }
  }

  Future<void> _handleSaveSignalingUrl() async {
    if (_isSavingSignaling) return;
    final text = _signalingController.text.trim();
    final i18n = AppI18n.of(context);

    if (text.isEmpty) {
      setState(() {
        _signalingFeedback = i18n.signalingSaveError;
        _signalingFeedbackIsError = true;
      });
      return;
    }

    setState(() {
      _isSavingSignaling = true;
      _signalingFeedback = null;
      _signalingFeedbackIsError = false;
    });

    final previousUrl = AppSettings.instance.signalingUrl;
    bool sessionUpdated = false;

    try {
      // 1. Validate URL scheme (ws/wss) and host
      final uri = Uri.tryParse(text);
      if (uri == null ||
          (uri.scheme != 'ws' && uri.scheme != 'wss') ||
          uri.host.isEmpty) {
        throw ArgumentError('signaling URL must be ws:// or wss://');
      }

      // 2. Validate with session if available (does not interrupt in-room session)
      final session = widget.session;
      if (session != null) {
        await session.setSignalingUrl(text);
        sessionUpdated = true;
      }

      // 3. Persist only after validation succeeds
      await AppSettings.instance.setSignalingUrl(text);

      if (mounted) {
        final inRoom = widget.session?.roomId != null;
        setState(() {
          _isSavingSignaling = false;
          _signalingFeedback =
              inRoom ? i18n.signalingInRoomNotice : i18n.signalingSaved;
          _signalingFeedbackIsError = false;
        });
      }
    } catch (e) {
      // If session setSignalingUrl succeeded first but persistence subsequently failed,
      // roll back session's future connection configuration to previousUrl without masking original error.
      if (sessionUpdated && widget.session != null) {
        try {
          await widget.session!.setSignalingUrl(previousUrl);
        } catch (_) {
          // Catch rollback exception so as not to mask the original persistence error
        }
      }

      if (mounted) {
        setState(() {
          _isSavingSignaling = false;
          // Retain draft in _signalingController; do NOT revert
          _signalingFeedback = e is ArgumentError
              ? i18n.signalingSaveError
              : i18n.signalingPersistFailed;
          _signalingFeedbackIsError = true;
        });
      }
    }
  }

  Future<void> _handleClearCache() async {
    if (_isCleaningCache) return;
    final session = widget.session;
    if (session == null) {
      setState(() {
        _cacheCleanMessage = AppI18n.of(context).clearCacheNone;
        _cacheCleanSuccess = true;
      });
      return;
    }

    setState(() {
      _isCleaningCache = true;
      _cacheCleanMessage = null;
      _cacheCleanSuccess = null;
    });

    try {
      final freedBytes = await session.clearUnprotectedCache();
      if (mounted) {
        setState(() {
          _isCleaningCache = false;
          if (freedBytes > 0) {
            _cacheCleanMessage =
                AppI18n.of(context).clearCacheSuccess(formatBytes(freedBytes));
            _cacheCleanSuccess = true;
          } else {
            _cacheCleanMessage = AppI18n.of(context).clearCacheNone;
            _cacheCleanSuccess = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCleaningCache = false;
          _cacheCleanMessage = AppI18n.of(context).clearCacheFailed;
          _cacheCleanSuccess = false;
        });
      }
    }
  }

  String _formatConnectionState(AppI18n i18n, RoomConnectionState state) {
    switch (state) {
      case RoomConnectionState.connected:
        return i18n.stateConnected;
      case RoomConnectionState.connecting:
        return i18n.stateConnecting;
      case RoomConnectionState.reconnecting:
        return i18n.stateReconnecting;
      case RoomConnectionState.disconnected:
        return i18n.stateDisconnected;
    }
  }

  String _formatRole(AppI18n i18n, RoomRole role) {
    switch (role) {
      case RoomRole.owner:
        return i18n.roleOwner;
      case RoomRole.admin:
        return i18n.roleAdmin;
      case RoomRole.member:
        return i18n.roleMember;
    }
  }

  bool _isPlayerReady(RoomSession? session) {
    if (session == null) return false;
    try {
      session.player;
      return true;
    } on StateError {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettings.instance,
        if (widget.session != null) widget.session!,
      ]),
      builder: (context, _) {
        final i18n = AppI18n.of(context);
        final tc = ThemeColors.of(context);
        final settings = AppSettings.instance;
        final mediaQuery = MediaQuery.of(context);
        final screenWidth = mediaQuery.size.width;
        final isMobile = screenWidth < 768;
        final availableHeight =
            mediaQuery.size.height - mediaQuery.viewInsets.bottom;
        final isVeryShort = availableHeight < 360;
        final verticalMargin = isVeryShort ? 6.0 : (isMobile ? 12.0 : 20.0);
        final safeAvailable =
            availableHeight < 160.0 ? 160.0 : availableHeight;
        final maxDialogHeight =
            (safeAvailable - verticalMargin * 2).clamp(140.0, double.infinity);

        return Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamilyFallback: kAppleFontFallbacks,
              decoration: TextDecoration.none,
              color: tc.textPrimary,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 580,
                  maxHeight: maxDialogHeight,
                ),
                child: Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 24,
                    vertical: verticalMargin,
                  ),
                  child: GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.solid,
                    color: tc.cardBackground,
                    shape: LiquidRoundedSuperellipse(
                      borderRadius: isVeryShort ? 16 : 24,
                    ),
                    padding: EdgeInsets.all(isVeryShort ? 14 : 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: tc.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(Icons.settings_rounded,
                                  size: 18, color: tc.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                i18n.settingsTitle,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  color: tc.textPrimary,
                                ),
                              ),
                            ),
                            Semantics(
                              button: true,
                              enabled: true,
                              label: i18n.close,
                              child: Tooltip(
                                message: i18n.close,
                                child: GlassIconButton(
                                  key: const ValueKey('settings-close-btn'),
                                  icon: Icon(Icons.close_rounded,
                                      size: 18, color: tc.textSecondary),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Scrollable Settings Content
                        Flexible(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Language
                                _buildSectionHeader(
                                  context,
                                  icon: Icons.language_rounded,
                                  title: i18n.settingsLang,
                                ),
                                const SizedBox(height: 8),
                                GlassSegmentedControl(
                                  selectedIndex:
                                      _getLanguageIndex(settings.locale),
                                  onSegmentSelected: _onLanguageSelected,
                                  segments: [
                                    GlassSegment(label: i18n.langSystem),
                                    GlassSegment(label: i18n.settingsLangZh),
                                    GlassSegment(label: i18n.settingsLangEn),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // 2. Theme Mode
                                _buildSectionHeader(
                                  context,
                                  icon: Icons.brightness_6_rounded,
                                  title: i18n.settingsThemeMode,
                                ),
                                const SizedBox(height: 8),
                                GlassSegmentedControl(
                                  selectedIndex:
                                      _getThemeModeIndex(settings.themeMode),
                                  onSegmentSelected: _onThemeModeSelected,
                                  segments: [
                                    GlassSegment(label: i18n.themeSystem),
                                    GlassSegment(label: i18n.themeLight),
                                    GlassSegment(label: i18n.themeDark),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // 3. Independent Theme Colors
                                _buildSectionHeader(
                                  context,
                                  icon: Icons.palette_rounded,
                                  title: i18n.independentColors,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  i18n.independentColorsDesc,
                                  style: TextStyle(
                                      fontSize: 12, color: tc.textSecondary),
                                ),
                                const SizedBox(height: 12),

                                // Light Theme Color Swatches
                                _buildColorSection(
                                  context,
                                  title: i18n.lightColor,
                                  currentColor: settings.lightThemeColor,
                                  presets: _lightPresets,
                                  onSelectColor: settings.setLightThemeColor,
                                  onReset: settings.resetLightThemeColor,
                                  resetText: i18n.resetDefault,
                                  i18n: i18n,
                                ),
                                const SizedBox(height: 14),

                                // Dark Theme Color Swatches
                                _buildColorSection(
                                  context,
                                  title: i18n.darkColor,
                                  currentColor: settings.darkThemeColor,
                                  presets: _darkPresets,
                                  onSelectColor: settings.setDarkThemeColor,
                                  onReset: settings.resetDarkThemeColor,
                                  resetText: i18n.resetDefault,
                                  i18n: i18n,
                                ),
                                const SizedBox(height: 18),

                                // 4. Signaling Configuration
                                _buildSectionHeader(
                                  context,
                                  icon: Icons.alt_route_rounded,
                                  title: i18n.configuringSignaling,
                                ),
                                const SizedBox(height: 8),
                                GlassContainer.card(
                                  surfaceStyle: GlassSurfaceStyle.solid,
                                  color: tc.inputBackground,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: GlassTextField(
                                              key: const ValueKey(
                                                  'settings-signaling-input'),
                                              controller: _signalingController,
                                              placeholder:
                                                  i18n.signalingUrlHint,
                                              height: 40,
                                              surfaceStyle:
                                                  GlassSurfaceStyle.solid,
                                              color: Colors.transparent,
                                              textStyle: TextStyle(
                                                color: tc.textPrimary,
                                                fontSize: 12.5,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                              placeholderStyle: TextStyle(
                                                  color: tc.textTertiary,
                                                  fontSize: 12.5),
                                              onSubmitted: (_) =>
                                                  _handleSaveSignalingUrl(),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          LiquidGlassActionButton(
                                            key: const ValueKey(
                                                'settings-save-signaling-btn'),
                                            height: 36,
                                            onTap: _isSavingSignaling
                                                ? () {}
                                                : _handleSaveSignalingUrl,
                                            child: _isSavingSignaling
                                                ? SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              tc.textPrimary),
                                                    ),
                                                  )
                                                : Text(i18n.save,
                                                    style: const TextStyle(
                                                        fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                      if (_signalingFeedback != null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              _signalingFeedbackIsError
                                                  ? Icons.error_outline_rounded
                                                  : Icons
                                                      .check_circle_outline_rounded,
                                              size: 14,
                                              color: _signalingFeedbackIsError
                                                  ? tc.error
                                                  : tc.success,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _signalingFeedback!,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w500,
                                                  color:
                                                      _signalingFeedbackIsError
                                                          ? tc.error
                                                          : tc.success,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else if (widget.session?.roomId !=
                                          null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          i18n.signalingInRoomNotice,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: tc.textTertiary),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // 5. Background Keep-Alive
                                _buildSectionHeader(
                                  context,
                                  icon: Icons.power_settings_new_rounded,
                                  title: i18n.backgroundKeepAliveTitle,
                                ),
                                const SizedBox(height: 8),
                                GlassContainer.card(
                                  surfaceStyle: GlassSurfaceStyle.solid,
                                  color: tc.inputBackground,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              i18n.backgroundKeepAliveTitle,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                                color: tc.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              i18n.backgroundKeepAliveDesc,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: tc.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch.adaptive(
                                        value: settings.backgroundKeepAlive,
                                        activeColor: tc.primary,
                                        onChanged: (val) {
                                          settings.setBackgroundKeepAlive(val);
                                          final session = widget.session;
                                          if (session != null) {
                                            session.syncKeepAlive(val);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // 6. Media Cache Occupancy & Safe Cleanup (V1-PRD §9)
                                _buildCacheSection(context, i18n, tc),
                                const SizedBox(height: 18),

                                // 7. Real Node Diagnostics (No secrets, invites or URLs)
                                _buildDiagnosticsSection(context, i18n, tc),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            LiquidGlassActionButton(
                              key: const ValueKey('settings-done-btn'),
                              isPrimary: true,
                              height: 42,
                              onTap: () {
                                Navigator.of(context).pop();
                              },
                              child: Text(
                                i18n.done,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, {required IconData icon, required String title}) {
    final tc = ThemeColors.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: tc.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tc.textSecondary,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildColorSection(
    BuildContext context, {
    required String title,
    required Color currentColor,
    required List<Map<String, dynamic>> presets,
    required ValueChanged<Color> onSelectColor,
    required VoidCallback onReset,
    required String resetText,
    required AppI18n i18n,
  }) {
    final tc = ThemeColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: tc.textSecondary,
              ),
            ),
            Semantics(
              button: true,
              enabled: true,
              label: '$title: $resetText',
              child: GestureDetector(
                onTap: onReset,
                child: Text(
                  resetText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: tc.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: presets.map((p) {
            final color = p['color'] as Color;
            final isCurrent = currentColor.value == color.value;
            final name = _getColorName(i18n, p['key'] as String);

            return Semantics(
              button: true,
              selected: isCurrent,
              label: '$title: $name',
              value: isCurrent ? i18n.selected : null,
              child: Tooltip(
                message: name,
                child: GestureDetector(
                  key: ValueKey('settings-color-${p['key']}-${isCurrent ? "selected" : "idle"}'),
                  onTap: () => onSelectColor(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent
                            ? (tc.isDark ? Colors.white : Colors.black)
                            : Colors.transparent,
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isCurrent
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCacheSection(
      BuildContext context, AppI18n i18n, ThemeColors tc) {
    final session = widget.session;
    final usedBytes = session?.cacheUsedBytes ?? 0;
    final maxBytes = session?.cacheMaxBytes ?? 0;
    final telemetry = session?.cacheTelemetry;
    final isUninitialized = telemetry == null;
    final ratio = (maxBytes > 0 && usedBytes > 0)
        ? (usedBytes / maxBytes).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          icon: Icons.storage_rounded,
          title: i18n.cacheTitle,
        ),
        const SizedBox(height: 4),
        Text(
          i18n.cacheDesc,
          style: TextStyle(fontSize: 12, color: tc.textSecondary),
        ),
        const SizedBox(height: 8),
        GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          color: tc.inputBackground,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session?.lastErrorCode == 'storage_full') ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: tc.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tc.error.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.disc_full_rounded, size: 16, color: tc.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          i18n.mapErrorCode('storage_full'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: tc.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Occupancy row & Progress bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.pie_chart_outline_rounded,
                          size: 14, color: tc.primary),
                      const SizedBox(width: 6),
                      Text(
                        i18n.cacheUsage,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: tc.textPrimary),
                      ),
                    ],
                  ),
                  Text(
                    '${formatBytes(usedBytes)} / ${formatBytes(maxBytes)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tc.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Linear Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: tc.cardBackground,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ratio > 0.9 ? tc.warning : tc.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Telemetry stats grid
              Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      label: i18n.cacheServiceStatus,
                      value: isUninitialized
                          ? i18n.cacheStatusUninitialized
                          : i18n.cacheStatusActive,
                      tc: tc,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMiniStat(
                      label: i18n.cacheChunks,
                      value: telemetry != null
                          ? '${telemetry.cachedChunks}'
                          : '0',
                      tc: tc,
                    ),
                  ),
                ],
              ),
              if (telemetry != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStat(
                        label: i18n.cacheHitStats,
                        value: '${telemetry.hits} / ${telemetry.misses}',
                        tc: tc,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMiniStat(
                        label: i18n.cacheEvicted,
                        value: formatBytes(telemetry.evictedBytes),
                        tc: tc,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Explanatory note: in-use chunks & original files are safe
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: tc.cardBackground.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: tc.textTertiary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: tc.textTertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        i18n.clearCacheNotice,
                        style: TextStyle(
                            fontSize: 11,
                            color: tc.textSecondary,
                            height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Action button & feedback
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: i18n.clearCacheBtn,
                    child: LiquidGlassActionButton(
                      key: const ValueKey('settings-clear-cache-btn'),
                      height: 36,
                      onTap: _isCleaningCache ? () {} : _handleClearCache,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isCleaningCache) ...[
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    tc.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(i18n.clearingCache,
                                style: const TextStyle(fontSize: 12)),
                          ] else ...[
                            const Icon(Icons.cleaning_services_rounded,
                                size: 14),
                            const SizedBox(width: 6),
                            Text(i18n.clearCacheBtn,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_cacheCleanMessage != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _cacheCleanMessage!,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: (_cacheCleanSuccess ?? true)
                              ? tc.primary
                              : tc.warning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection(
      BuildContext context, AppI18n i18n, ThemeColors tc) {
    final session = widget.session;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          icon: Icons.shield_rounded,
          title: i18n.diagTitle,
        ),
        const SizedBox(height: 8),
        GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          color: tc.inputBackground,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDiagRow(
                context,
                label: i18n.diagSignalingServer,
                value: AppSettings.instance.signalingUrl,
              ),
              const SizedBox(height: 8),
              _buildDiagRow(
                context,
                label: i18n.diagDeviceId,
                value: session != null && session.identity.deviceId.isNotEmpty
                    ? formatDeviceId(session.identity.deviceId)
                    : '-',
              ),
              const SizedBox(height: 8),
              _buildDiagRow(
                context,
                label: i18n.diagConnectionState,
                value: session != null
                    ? _formatConnectionState(i18n, session.connectionState)
                    : i18n.stateDisconnected,
              ),
              const SizedBox(height: 8),
              _buildDiagRow(
                context,
                label: i18n.diagRoomId,
                value: session?.roomId != null
                    ? formatDeviceId(session!.roomId!)
                    : i18n.diagNotInRoom,
              ),
              if (session?.roomId != null) ...[
                const SizedBox(height: 8),
                _buildDiagRow(
                  context,
                  label: i18n.diagCurrentRole,
                  value: _formatRole(i18n, session!.role),
                ),
                const SizedBox(height: 8),
                _buildDiagRow(
                  context,
                  label: i18n.diagActiveMembers,
                  value:
                      '${session.members.where((m) => m.online).length} / ${session.members.length}',
                ),
                const SizedBox(height: 8),
                _buildDiagRow(
                  context,
                  label: i18n.diagPlaylistItemCount,
                  value: '${session.playlist.length}',
                ),
              ],
              const SizedBox(height: 8),
              _buildDiagRow(
                context,
                label: i18n.diagMediaEngine,
                value: _isPlayerReady(session)
                    ? i18n.diagEngineReady
                    : i18n.diagEngineNotReady,
              ),
              const SizedBox(height: 8),
              _buildDiagRow(
                context,
                label: i18n.diagProtocolVersion,
                value: 'v1 (Ed25519 · WebRTC)',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required ThemeColors tc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tc.cardBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: tc.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: tc.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final tc = ThemeColors.of(context);

    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: tc.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: tc.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

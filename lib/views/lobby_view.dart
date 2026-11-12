import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../models.dart';
import '../core/room_history_service.dart';
import 'settings_dialog.dart';
import 'profile_view.dart';
import '../widgets/app_logo.dart';

class LobbyView extends StatefulWidget {
  final RoomSession session;
  final bool isInitialized;
  final String? initError;
  final VoidCallback? onRetryInit;

  const LobbyView({
    super.key,
    required this.session,
    this.isInitialized = true,
    this.initError,
    this.onRetryInit,
  });

  @override
  State<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<LobbyView> {
  final TextEditingController _inviteController = TextEditingController();
  int _mobileNavIndex = 0;
  bool _isActionPending = false;
  String? _lastReportedSessionError;
  String? _lastReportedInitError;
  String? _detectedClipboardInvite;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionStateChanged);
    _lastReportedInitError = widget.initError;
    _lastReportedSessionError = widget.session.lastErrorCode;
    RoomHistoryService.getRecentRooms();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboard();
      if (mounted && widget.initError != null && widget.initError!.isNotEmpty) {
        _showInitErrorSnackBar(widget.initError!);
      }
    });
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim();
      if (raw == null || raw.isEmpty) return;
      // Filter out long text or text with spaces/newlines
      final isCandidate =
          (raw.length >= 6 && raw.length <= 128) &&
          !raw.contains('\n') &&
          !raw.contains(' ');
      if (isCandidate &&
          raw != _detectedClipboardInvite &&
          raw != _inviteController.text.trim()) {
        if (mounted) {
          setState(() => _detectedClipboardInvite = raw);
        }
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(LobbyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSessionStateChanged);
      widget.session.addListener(_onSessionStateChanged);
    }
    if (widget.initError != oldWidget.initError) {
      if (widget.initError != null &&
          widget.initError!.isNotEmpty &&
          widget.initError != _lastReportedInitError) {
        _lastReportedInitError = widget.initError;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              widget.initError != null &&
              widget.initError!.isNotEmpty) {
            _showInitErrorSnackBar(widget.initError!);
          }
        });
      } else if (widget.initError == null) {
        _lastReportedInitError = null;
      }
    }
  }

  @override
  void dispose() {
    hideLiquidGlassSnackBar();
    widget.session.removeListener(_onSessionStateChanged);
    _inviteController.dispose();
    super.dispose();
  }

  void _onSessionStateChanged() {
    final code = widget.session.lastErrorCode;
    if (code != null && code.isNotEmpty && code != _lastReportedSessionError) {
      _lastReportedSessionError = code;
      _showSessionErrorSnackBar(code);
    } else if (code == null || code.isEmpty) {
      _lastReportedSessionError = null;
    }
  }

  void _showSessionErrorSnackBar(String code) {
    if (!mounted) return;
    final i18n = AppI18n.of(context);
    final isConnectionError =
        code == 'signaling_unavailable' || code == 'connection_failed';
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 768;
    final isShort = mediaQuery.size.height < 500;
    final showBottomBar = isMobile && !isShort;

    showLiquidGlassSnackBar(
      context,
      owner: this,
      message: i18n.mapErrorCode(code),
      icon: Icons.error_outline_rounded,
      bottomOffset: showBottomBar ? 74 : 16,
      onRetry: isConnectionError
          ? () async {
              _lastReportedSessionError = null;
              await widget.session.retry();
            }
          : null,
      retryLabel: isConnectionError ? i18n.retryConnection : null,
      retryKey: isConnectionError
          ? const ValueKey('cinema-retry-connection-btn')
          : null,
      duration: const Duration(seconds: 5),
    );
  }

  void _showInitErrorSnackBar(String error) {
    if (!mounted) return;
    final i18n = AppI18n.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 768;
    final isShort = mediaQuery.size.height < 500;
    final showBottomBar = isMobile && !isShort;

    showLiquidGlassSnackBar(
      context,
      owner: this,
      title: i18n.initFailed,
      message: error,
      icon: Icons.warning_amber_rounded,
      bottomOffset: showBottomBar ? 74 : 16,
      onRetry: widget.onRetryInit != null
          ? () {
              _lastReportedInitError = null;
              widget.onRetryInit!();
            }
          : null,
      retryLabel: i18n.retryInit,
      retryKey: const ValueKey('lobby-retry-init-btn'),
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _handleCreateRoom() async {
    if (!widget.isInitialized || _isActionPending) return;
    setState(() => _isActionPending = true);
    _lastReportedSessionError = null;
    try {
      await widget.session.setSignalingUrl(AppSettings.instance.signalingUrl);
      await widget.session.createRoom();
      if (widget.session.roomId != null) {
        unawaited(
          RoomHistoryService.recordRoom(
            roomId: widget.session.roomId!,
            role: 'owner',
          ),
        );
      }
    } catch (_) {
      if (mounted &&
          widget.session.lastErrorCode != null &&
          _lastReportedSessionError == null) {
        _lastReportedSessionError = widget.session.lastErrorCode;
        _showSessionErrorSnackBar(widget.session.lastErrorCode!);
      }
    } finally {
      if (mounted) {
        setState(() => _isActionPending = false);
      }
    }
  }

  Future<void> _handleJoinRoom([String? explicitPayload]) async {
    if (!widget.isInitialized || _isActionPending) return;
    final payload = (explicitPayload ?? _inviteController.text).trim();
    if (payload.isEmpty) return;

    setState(() => _isActionPending = true);
    _lastReportedSessionError = null;
    try {
      await widget.session.setSignalingUrl(AppSettings.instance.signalingUrl);
      await widget.session.joinRoom(payload);
      if (widget.session.roomId != null) {
        unawaited(
          RoomHistoryService.recordRoom(
            roomId: widget.session.roomId!,
            role: 'guest',
          ),
        );
      }
    } catch (_) {
      if (mounted &&
          widget.session.lastErrorCode != null &&
          _lastReportedSessionError == null) {
        _lastReportedSessionError = widget.session.lastErrorCode;
        _showSessionErrorSnackBar(widget.session.lastErrorCode!);
      }
    } finally {
      if (mounted) {
        setState(() => _isActionPending = false);
      }
    }
  }

  Future<void> _handlePasteJoin() async {
    if (!widget.isInitialized || _isActionPending) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null && data!.text!.trim().isNotEmpty) {
        _inviteController.text = data.text!.trim();
        await _handleJoinRoom(data.text!.trim());
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    if (_inviteController.text.trim().isNotEmpty) {
      await _handleJoinRoom(_inviteController.text.trim());
    } else {
      final i18n = AppI18n.of(context);
      showLiquidGlassSnackBar(
        context,
        owner: this,
        message: i18n.isZh
            ? '无法读取剪贴板，请直接在输入框中粘贴邀请内容'
            : 'Clipboard access unavailable, please paste directly into the input',
        icon: Icons.info_outline_rounded,
        duration: const Duration(seconds: 3),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.session, AppSettings.instance]),
      builder: (context, _) {
        final i18n = AppI18n.of(context);
        final tc = ThemeColors.of(context);
        final mediaQuery = MediaQuery.of(context);
        final screenWidth = mediaQuery.size.width;
        final screenHeight = mediaQuery.size.height;
        final isMobile = screenWidth < 768;
        final isShortWindow = screenHeight < 500;
        final showBottomBar = isMobile && !isShortWindow;
        final session = widget.session;
        final isConnecting =
            session.connectionState == RoomConnectionState.connecting ||
            _isActionPending;
        final hasInitError =
            widget.initError != null && widget.initError!.isNotEmpty;

        return Material(
          type: MaterialType.transparency,
          child: GlassScaffold(
            background: LiquidGlassAmbientBackground(child: Container()),
            extendBody: false,
            appBar: GlassAppBar(
              centerTitle: false,
              backgroundColor: Colors.transparent,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: tc.primary,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: tc.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: AppLogo(
                        size: 20,
                        color: Colors.white,
                        useGradient: false,
                        hasGlow: false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Eir',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: tc.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: tc.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      i18n.sync,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: tc.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                // Client Device ID pill with bounded formatting
                if (session.identity.deviceId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message:
                          '${i18n.deviceIdLabel}: ${session.identity.deviceId}',
                      child: LiquidGlassTag(
                        color: tc.inputBackground,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fingerprint_rounded,
                              size: 14,
                              color: tc.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatDeviceId(session.identity.deviceId),
                              style: TextStyle(
                                fontSize: 11,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: tc.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Profile Button (Avatar)
                Semantics(
                  button: true,
                  enabled: true,
                  label: i18n.profileTitle,
                  child: Tooltip(
                    message: i18n.profileTitle,
                    child: GestureDetector(
                      onTap: () {
                        if (showBottomBar) {
                          setState(() => _mobileNavIndex = 1);
                        } else {
                          ProfileView.show(context, session: session);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Badge(
                          isLabelVisible: AppSettings.instance.hasPendingUpdate,
                          backgroundColor: Colors.redAccent,
                          smallSize: 8,
                          child: UserAvatar(
                            avatarKey: AppSettings.instance.avatar,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Settings Button
                Semantics(
                  button: true,
                  enabled: true,
                  label: i18n.settingsTitle,
                  child: Tooltip(
                    message: i18n.settingsTitle,
                    child: GlassIconButton(
                      key: const ValueKey('lobby-settings-btn'),
                      icon: Icon(
                        Icons.settings_outlined,
                        size: 19,
                        color: tc.textPrimary,
                      ),
                      onPressed: () =>
                          SettingsDialog.show(context, session: session),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            bottomBar: showBottomBar
                ? GlassTabBar.bottom(
                    selectedIndex: _mobileNavIndex,
                    onTabSelected: (index) {
                      setState(() => _mobileNavIndex = index);
                    },
                    tabs: [
                      GlassTab(
                        icon: const Icon(Icons.meeting_room_outlined),
                        label: i18n.mobileNavLobby,
                      ),
                      GlassTab(
                        icon: Badge(
                          isLabelVisible: AppSettings.instance.hasPendingUpdate,
                          backgroundColor: Colors.redAccent,
                          smallSize: 8,
                          child: const Icon(Icons.person_outline_rounded),
                        ),
                        activeIcon: Badge(
                          isLabelVisible: AppSettings.instance.hasPendingUpdate,
                          backgroundColor: Colors.redAccent,
                          smallSize: 8,
                          child: const Icon(Icons.person_rounded),
                        ),
                        label: i18n.mobileNavProfile,
                      ),
                    ],
                  )
                : null,
            body: _mobileNavIndex == 1
                ? SafeArea(
                    top: false,
                    bottom: !showBottomBar,
                    child: ProfileView(session: session),
                  )
                : SafeArea(
                    top: false,
                    bottom: !showBottomBar,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 18 : 36,
                        vertical: isShortWindow ? 10 : (isMobile ? 16 : 28),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            children: [
                              // Initialization loading indicator
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                child: (!widget.isInitialized && !hasInitError)
                                    ? Padding(
                                        padding: EdgeInsets.only(
                                          bottom: isShortWindow ? 10 : 18,
                                        ),
                                        child: _buildInitializingBanner(
                                          context,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // Connection Progress Indicator
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                child: isConnecting
                                    ? Padding(
                                        padding: EdgeInsets.only(
                                          bottom: isShortWindow ? 10 : 18,
                                        ),
                                        child: _buildConnectingBanner(context),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // Hero section with action card
                              _buildHeroSection(
                                context,
                                isMobile,
                                isShortWindow,
                                isConnecting || !widget.isInitialized,
                              ),

                              SizedBox(height: isShortWindow ? 20 : 36),

                              // Recent Cinemas (Replacing AI promotional cards with real utility)
                              _buildRecentRoomsSection(context, isMobile),

                              SizedBox(height: isShortWindow ? 24 : 48),

                              // Footer
                              Text(
                                i18n.footerText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: tc.textTertiary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: isShortWindow ? 12 : 24),
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

  Widget _buildInitializingBanner(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.primary.withValues(alpha: 0.10),
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: tc.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              i18n.initializingEngine,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: tc.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingBanner(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.primary.withValues(alpha: 0.12),
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: tc.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              i18n.stateConnecting,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tc.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeGreeting(AppI18n i18n) {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return i18n.welcomeGreetingMorning;
    if (hour >= 12 && hour < 18) return i18n.welcomeGreetingAfternoon;
    return i18n.welcomeGreetingEvening;
  }

  String _formatRelativeTime(int timestampMs, AppI18n i18n) {
    if (timestampMs <= 0) return '';
    final diff = DateTime.now().millisecondsSinceEpoch - timestampMs;
    if (diff < 60000) return i18n.isZh ? '刚刚' : 'Just now';
    if (diff < 3600000)
      return i18n.isZh
          ? '${(diff / 60000).floor()} 分钟前'
          : '${(diff / 60000).floor()}m ago';
    if (diff < 86400000)
      return i18n.isZh
          ? '${(diff / 3600000).floor()} 小时前'
          : '${(diff / 3600000).floor()}h ago';
    final days = (diff / 86400000).floor();
    return i18n.isZh ? '$days 天前' : '${days}d ago';
  }

  Widget _buildWelcomeHeader(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
    bool isMobile,
  ) {
    final settings = AppSettings.instance;
    final greeting = _getTimeGreeting(i18n);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          UserAvatar(avatarKey: settings.avatar, size: 30),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.effectiveDisplayName,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: tc.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                greeting,
                style: TextStyle(fontSize: 11, color: tc.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClipboardInviteBanner(BuildContext context) {
    if (_detectedClipboardInvite == null) return const SizedBox.shrink();
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          color: tc.primary.withValues(alpha: 0.12),
          shape: const LiquidRoundedSuperellipse(borderRadius: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tc.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.link_rounded, size: 16, color: tc.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      i18n.clipboardInviteDetected,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: tc.primary,
                      ),
                    ),
                    Text(
                      _detectedClipboardInvite!,
                      style: TextStyle(
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: tc.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              LiquidGlassActionButton(
                height: 28,
                isPrimary: true,
                onTap: () {
                  final code = _detectedClipboardInvite!;
                  setState(() => _detectedClipboardInvite = null);
                  _inviteController.text = code;
                  _handleJoinRoom(code);
                },
                child: Text(
                  i18n.quickJoin,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: tc.textTertiary,
                ),
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                onPressed: () =>
                    setState(() => _detectedClipboardInvite = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    bool isMobile,
    bool isShort,
    bool isDisabled,
  ) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return Column(
      children: [
        SizedBox(height: isShort ? 4 : 8),
        _buildWelcomeHeader(context, i18n, tc, isMobile),
        _buildClipboardInviteBanner(context),

        // System Tag
        GlassChip(
          icon: const Icon(Icons.hub_rounded, size: 14),
          label: i18n.heroBadge,
        ),
        SizedBox(height: isShort ? 6 : 14),

        // Main Title
        Text(
          i18n.heroTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isShort ? 22 : (isMobile ? 28 : 42),
            fontWeight: FontWeight.w800,
            letterSpacing: isShort ? -0.8 : -1.2,
            height: 1.15,
            color: tc.textPrimary,
          ),
        ),
        SizedBox(height: isShort ? 6 : 12),

        // Subtitle
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            i18n.heroSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isShort ? 12 : (isMobile ? 13.5 : 15),
              height: isShort ? 1.35 : 1.45,
              fontWeight: FontWeight.w400,
              color: tc.textSecondary,
            ),
          ),
        ),
        SizedBox(height: isShort ? 14 : 26),

        // Action Box (Double-bezel hardware feel)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: GlassContainer.card(
            surfaceStyle: GlassSurfaceStyle.solid,
            color: tc.cardBackground,
            shape: const LiquidRoundedSuperellipse(borderRadius: 22),
            padding: EdgeInsets.all(isShort ? 12 : 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Transport Mode Selector
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(
                        i18n.transportEngine,
                        style: TextStyle(
                          fontSize: isShort ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: tc.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (!kIsWeb)
                        SizedBox(
                          width: isShort ? 160 : 190,
                          child: GlassSegmentedControl(
                            selectedIndex: AppSettings.instance.isTailcatEngine
                                ? 1
                                : 0,
                            onSegmentSelected: (index) {
                              AppSettings.instance.setTransportEngine(
                                index == 1 ? 'tailcat' : 'webrtc',
                              );
                            },
                            segments: const [
                              GlassSegment(label: '⚡ WebRTC'),
                              GlassSegment(label: '🚀 Tailcat'),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: tc.inputBackground,
                            border: Border.all(color: tc.glassBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '⚡ WebRTC',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '(${i18n.tailcatClientOnly})',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: tc.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Create Room Button & Subtitle
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      button: true,
                      label: i18n.createRoom,
                      child: LiquidGlassActionButton(
                        key: const ValueKey('lobby-create-btn'),
                        isPrimary: true,
                        height: isShort ? 42 : 48,
                        onTap: isDisabled ? () {} : _handleCreateRoom,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_circle_outline_rounded,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              i18n.createRoom,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: isShort ? 13.5 : 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      i18n.createRoomSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: tc.textTertiary),
                    ),
                  ],
                ),
                SizedBox(height: isShort ? 12 : 16),

                // Subtle Inset Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: tc.glassBorder, height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        i18n.joinRoomSubtitle,
                        style: TextStyle(fontSize: 11, color: tc.textTertiary),
                      ),
                    ),
                    Expanded(child: Divider(color: tc.glassBorder, height: 1)),
                  ],
                ),
                SizedBox(height: isShort ? 12 : 16),

                // Join Room Input Row
                isMobile
                    ? Column(
                        children: [
                          GlassTextField(
                            key: const ValueKey('lobby-join-input'),
                            controller: _inviteController,
                            placeholder: i18n.inputPlaceholder,
                            height: isShort ? 38 : 44,
                            surfaceStyle: GlassSurfaceStyle.solid,
                            color: tc.inputBackground,
                            textStyle: TextStyle(
                              color: tc.textPrimary,
                              fontSize: isShort ? 12 : 12.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            placeholderStyle: TextStyle(
                              color: tc.textTertiary,
                              fontSize: isShort ? 11.5 : 12,
                            ),
                            onSubmitted: (_) =>
                                isDisabled ? null : _handleJoinRoom(),
                          ),
                          SizedBox(height: isShort ? 8 : 10),
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  label: i18n.pasteJoin,
                                  child: LiquidGlassActionButton(
                                    key: const ValueKey('lobby-paste-join-btn'),
                                    onTap: isDisabled
                                        ? () {}
                                        : _handlePasteJoin,
                                    height: isShort ? 38 : 42,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.content_paste_rounded,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          i18n.pasteJoin,
                                          style: TextStyle(
                                            fontSize: isShort ? 12.5 : 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  label: i18n.joinRoom,
                                  child: LiquidGlassActionButton(
                                    key: const ValueKey('lobby-join-btn'),
                                    isPrimary: true,
                                    onTap: isDisabled
                                        ? () {}
                                        : () => _handleJoinRoom(),
                                    height: isShort ? 38 : 42,
                                    child: Text(
                                      i18n.joinRoom,
                                      style: TextStyle(
                                        fontSize: isShort ? 12.5 : 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: GlassTextField(
                              key: const ValueKey('lobby-join-input'),
                              controller: _inviteController,
                              placeholder: i18n.inputPlaceholder,
                              height: 46,
                              surfaceStyle: GlassSurfaceStyle.solid,
                              color: tc.inputBackground,
                              textStyle: TextStyle(
                                color: tc.textPrimary,
                                fontSize: 13,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              placeholderStyle: TextStyle(
                                color: tc.textTertiary,
                                fontSize: 12.5,
                              ),
                              onSubmitted: (_) =>
                                  isDisabled ? null : _handleJoinRoom(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Semantics(
                            button: true,
                            label: i18n.pasteJoin,
                            child: LiquidGlassActionButton(
                              key: const ValueKey('lobby-paste-join-btn'),
                              height: 46,
                              onTap: isDisabled ? () {} : _handlePasteJoin,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.content_paste_rounded,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(i18n.pasteJoin),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: i18n.joinRoom,
                            child: LiquidGlassActionButton(
                              key: const ValueKey('lobby-join-btn'),
                              isPrimary: true,
                              height: 46,
                              onTap: isDisabled
                                  ? () {}
                                  : () => _handleJoinRoom(),
                              child: Text(i18n.joinRoom),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentRoomsSection(BuildContext context, bool isMobile) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return ValueListenableBuilder<List<RecentRoom>>(
      valueListenable: RoomHistoryService.recentRoomsNotifier,
      builder: (context, recentRooms, _) {
        if (recentRooms.isEmpty) {
          return const SizedBox.shrink();
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: tc.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    i18n.recentRooms,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: tc.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => RoomHistoryService.clearHistory(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(
                        i18n.clearHistory,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: tc.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...recentRooms.map((room) {
                final relativeTime = _formatRelativeTime(
                  room.lastVisitedMs,
                  i18n,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.solid,
                    color: tc.inputBackground,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: tc.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            room.isOwner
                                ? Icons.live_tv_rounded
                                : Icons.meeting_room_rounded,
                            size: 16,
                            color: tc.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      room.displayTitle,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: tc.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (room.isOwner
                                                  ? tc.primary
                                                  : tc.textTertiary)
                                              .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      room.isOwner
                                          ? (i18n.isZh ? '房主' : 'Host')
                                          : (i18n.isZh ? '访客' : 'Guest'),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: room.isOwner
                                            ? tc.primary
                                            : tc.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${i18n.isZh ? '最后访问: ' : 'Visited: '}$relativeTime',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: tc.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        LiquidGlassActionButton(
                          height: 30,
                          onTap: () {
                            _inviteController.text = room.roomId;
                            _handleJoinRoom(room.roomId);
                          },
                          child: Text(
                            i18n.rejoin,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: tc.textTertiary,
                          ),
                          splashRadius: 16,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          onPressed: () =>
                              RoomHistoryService.removeRoom(room.roomId),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  bool isZh(BuildContext context) => AppI18n.of(context).isZh;
}

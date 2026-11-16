import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_localization.dart';
import '../core/room_history_service.dart';
import '../core/room_session.dart';
import '../apple_glass.dart';
import 'screen_share_live_view.dart';
import 'screen_source_picker_dialog.dart';
import '../widgets/mobile_download_dialog.dart';

/// Screen Share Lobby View - Focused, human-centric design mirroring LobbyView
class ScreenShareLobbyView extends StatefulWidget {
  final RoomSession session;

  const ScreenShareLobbyView({
    super.key,
    required this.session,
  });

  @override
  State<ScreenShareLobbyView> createState() => _ScreenShareLobbyViewState();
}

class _ScreenShareLobbyViewState extends State<ScreenShareLobbyView> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _isConnecting = false;
  String? _errorMessage;
  String? _detectedClipboardCastCode;

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _codeController.addListener(_onCodeChanged);
    widget.session.setSignalingUrl(AppSettings.instance.signalingUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUrlCastParam();
      _checkClipboard();
    });
  }

  void _checkUrlCastParam() {
    if (kIsWeb) {
      try {
        final uri = Uri.base;
        final castParam = uri.queryParameters['cast'] ?? uri.queryParameters['code'];
        if (castParam != null) {
          final digits = castParam.replaceAll(RegExp(r'\D'), '');
          if (digits.length == 6) {
            _codeController.text = digits;
            if (mounted) setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isConnecting && !_service.isActive) {
                _handleJoinCast(digits);
              }
            });
          }
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim();
      if (raw == null || raw.isEmpty) return;
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 6 && digits != _codeController.text.trim()) {
        if (mounted) {
          setState(() => _detectedClipboardCastCode = digits);
        }
      }
    } catch (_) {}
  }

  void _onCodeChanged() {
    if (mounted) setState(() {});
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _handleStartCast() async {
    final opts = await ScreenSourcePickerDialog.show(context);
    if (opts == null || !mounted) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      await widget.session.setSignalingUrl(AppSettings.instance.signalingUrl);
      if (widget.session.roomCode == null || widget.session.roomCode!.isEmpty) {
        await widget.session.createRoom();
      }

      final castCode = widget.session.roomCode;
      if (castCode == null || castCode.isEmpty) {
        throw StateError(widget.session.lastErrorCode ?? '信令服务无法创建投屏房间，请检查网络连接');
      }

      final success = await _service.startBroadcasting(
        source: opts.source,
        shareAudio: opts.shareAudio,
        targetFps: opts.fps,
        customTitle: opts.customTitle,
        castCode: castCode,
        enableFloatingChat: opts.enableFloatingChat,
      );

      if (!success && mounted) {
        setState(() => _errorMessage = _service.lastError ?? '投屏发起失败');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _handleJoinCast([String? explicitCode]) async {
    final code = (explicitCode ?? _codeController.text).trim();
    if (code.length != 6) {
      setState(() => _errorMessage = '请输入 6 位有效投屏码');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      await widget.session.setSignalingUrl(AppSettings.instance.signalingUrl);
      _service.prepareViewing(castCode: code);
      if (widget.session.roomCode != code) {
        await widget.session.joinRoomByCode(code);
      }
      if (widget.session.roomCode != code && widget.session.lastErrorCode != null) {
        throw StateError('加入投屏房间失败: ${widget.session.lastErrorCode}');
      }

      final success = await _service.startViewing(castCode: code);
      if (!success && mounted) {
        setState(() => _errorMessage = _service.lastError ?? '无法连接到该投屏');
      }
    } catch (e) {
      _service.stop(reason: 'join_error');
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null && mounted) {
        final digits = data!.text!.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 6) {
          final code = digits.substring(0, 6);
          _codeController.text = code;
          await _handleJoinCast(code);
          return;
        } else if (digits.isNotEmpty) {
          _codeController.text = digits;
        }
      }
    } catch (_) {}
    if (_codeController.text.trim().isNotEmpty) {
      await _handleJoinCast(_codeController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isMobile = screenWidth < 768;
    final isShort = screenHeight < 500;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 18 : 36,
        vertical: isShort ? 10 : (isMobile ? 16 : 28),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isMobile ? 680 : 860),
          child: Column(
            children: [
              // 1. Hero Header
              _buildHeroSection(context, i18n, tc, isMobile, isShort),

              // 2. Clipboard Invite Banner (if detected)
              _buildClipboardCastBanner(context, i18n, tc),

              // 3. Active Session Banner (if broadcasting or viewing)
              if (_service.isActive) ...[
                _buildActiveSessionBanner(context, i18n, tc),
                const SizedBox(height: 14),
              ],

              // 4. Error Notice
              if (_errorMessage != null) ...[
                _buildErrorBanner(context, _errorMessage!, tc),
                const SizedBox(height: 14),
              ],

              // 5. Main Action Console (Double-bezel hardware feel, identical to LobbyView)
              _buildActionBox(context, i18n, tc, isMobile, isShort),

              SizedBox(height: isShort ? 20 : 36),

              // 6. Recent Cast History
              _buildRecentCastsSection(context, i18n, tc),

              SizedBox(height: isShort ? 24 : 48),

              // Footer
              Column(
                children: [
                  Text(
                    '端到端低延迟传输 · 智能声画分离与回声消除',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: tc.textTertiary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(i18n.officialWebsiteUrl);
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (_) {
                        await launchUrl(uri, mode: LaunchMode.platformDefault);
                      }
                    },
                    child: Text(
                      '${i18n.poweredByNorns} · norns.cc.cd',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: tc.primary.withValues(alpha: 0.8),
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isShort ? 12 : 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
    bool isMobile,
    bool isShort,
  ) {
    return Column(
      children: [
        SizedBox(height: isShort ? 4 : 8),
        const GlassChip(
          icon: Icon(Icons.bolt_rounded, size: 14),
          label: '60 FPS · 超清低延迟',
        ),
        SizedBox(height: isShort ? 6 : 14),

        // Main Title
        Text(
          '实时投屏',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isShort ? 22 : (isMobile ? 28 : 40),
            fontWeight: FontWeight.w800,
            letterSpacing: isShort ? -0.8 : -1.2,
            height: 1.15,
            color: tc.textPrimary,
          ),
        ),
        SizedBox(height: isShort ? 6 : 10),

        // Subtitle
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Text(
            '将应用窗口或屏幕内容实时共享给好友',
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
      ],
    );
  }

  Widget _buildClipboardCastBanner(BuildContext context, AppI18n i18n, ThemeColors tc) {
    if (_detectedClipboardCastCode == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
              child: Icon(Icons.cast_connected_rounded, size: 16, color: tc.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '检测到剪贴板投屏码',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: tc.primary,
                    ),
                  ),
                  Text(
                    _detectedClipboardCastCode!,
                    style: TextStyle(
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: tc.textSecondary,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LiquidGlassActionButton(
              height: 28,
              isPrimary: true,
              onTap: () {
                final code = _detectedClipboardCastCode!;
                setState(() => _detectedClipboardCastCode = null);
                _codeController.text = code;
                _handleJoinCast(code);
              },
              child: const Text(
                '一键观看',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 14, color: tc.textTertiary),
              splashRadius: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              onPressed: () => setState(() => _detectedClipboardCastCode = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionBanner(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.primary.withValues(alpha: 0.12),
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.live_tv_rounded, color: tc.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _service.isBroadcasting ? i18n.castingToPeers : i18n.watchingCastStream,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tc.primary,
              ),
            ),
          ),
          LiquidGlassActionButton(
            height: 32,
            isPrimary: true,
            onTap: () => ScreenShareLiveView.launch(context, session: widget.session),
            child: const Text('返回视窗', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message, ThemeColors tc) {
    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: Colors.redAccent.withValues(alpha: 0.12),
      shape: const LiquidRoundedSuperellipse(borderRadius: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(int ms) {
    if (ms <= 0) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${diff.inDays ~/ 7}周前';
  }

  Widget _buildActionBox(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
    bool isMobile,
    bool isShort,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final useDualColumns = screenWidth >= 720;

    if (useDualColumns) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildShareCard(context, i18n, tc, isShort)),
            const SizedBox(width: 16),
            Expanded(child: _buildWatchCard(context, i18n, tc, isShort)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildShareCard(context, i18n, tc, isShort),
        const SizedBox(height: 16),
        _buildWatchCard(context, i18n, tc, isShort),
      ],
    );
  }

  Widget _buildShareCard(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
    bool isShort,
  ) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.cardBackground,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      padding: EdgeInsets.all(isShort ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [tc.primary, tc.primary.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.screen_share_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '我要投屏',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: tc.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '实时将手机屏幕或应用窗口共享给好友',
                          style: TextStyle(
                            fontSize: 12,
                            color: tc.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (kIsWeb && isMobile) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tc.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tc.glassBorderSubtle),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: tc.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      i18n.downloadMobilePrompt,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tc.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LiquidGlassActionButton(
              key: const ValueKey('mobile-web-download-app-btn'),
              isPrimary: true,
              height: isShort ? 42 : 48,
              onTap: () => MobileDownloadDialog.show(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.download_rounded, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    i18n.downloadAndroidApp,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: isShort ? 14 : 15.5,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Semantics(
              button: true,
              label: i18n.startScreenShare,
              child: LiquidGlassActionButton(
                key: const ValueKey('start-screen-share-btn'),
                isPrimary: true,
                height: isShort ? 42 : 48,
                onTap: _isConnecting ? () {} : _handleStartCast,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isConnecting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    else ...[
                      const Icon(Icons.play_arrow_rounded, size: 22),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _isConnecting ? i18n.screenShareConnecting : '立即开启投屏',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: isShort ? 14 : 15.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWatchCard(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
    bool isShort,
  ) {
    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.cardBackground,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      padding: EdgeInsets.all(isShort ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal, Colors.teal.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '观看投屏',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: tc.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '输入对方分享的 6 位投屏码，秒级同步画面',
                          style: TextStyle(
                            fontSize: 12,
                            color: tc.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Compound Input field with built-in clear & paste action buttons
              Row(
                children: [
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        GlassTextField(
                          key: const ValueKey('cast-code-input'),
                          controller: _codeController,
                          focusNode: _codeFocusNode,
                          placeholder: '输入 6 位投屏码',
                          height: 46,
                          surfaceStyle: GlassSurfaceStyle.solid,
                          color: tc.inputBackground,
                          keyboardType: TextInputType.number,
                          textStyle: TextStyle(
                            color: tc.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          placeholderStyle: TextStyle(
                            color: tc.textTertiary,
                            fontSize: 12.5,
                            letterSpacing: 0,
                            fontWeight: FontWeight.normal,
                          ),
                          onSubmitted: (val) => _isConnecting ? null : _handleJoinCast(val),
                        ),
                        if (_codeController.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: IconButton(
                              icon: Icon(Icons.cancel_rounded, size: 18, color: tc.textTertiary),
                              onPressed: () {
                                _codeController.clear();
                                setState(() {});
                              },
                              splashRadius: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  LiquidGlassActionButton(
                    key: const ValueKey('cast-paste-btn'),
                    height: 46,
                    width: 88,
                    onTap: _isConnecting ? () {} : _pasteFromClipboard,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.content_paste_rounded, size: 16),
                        SizedBox(width: 4),
                        Text('粘贴', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          LiquidGlassActionButton(
            key: const ValueKey('join-cast-btn'),
            isPrimary: true,
            height: 46,
            onTap: _isConnecting ? () {} : () => _handleJoinCast(),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_forward_rounded, size: 18),
                SizedBox(width: 6),
                Text(
                  '进入观看',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCastsSection(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return ValueListenableBuilder<List<RecentRoom>>(
      valueListenable: RoomHistoryService.recentRoomsNotifier,
      builder: (context, recentRooms, _) {
        if (recentRooms.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, right: 4),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 15, color: tc.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '最近投屏历史',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: tc.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () async {
                      await RoomHistoryService.clearHistory();
                      if (mounted) setState(() {});
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        '清空',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tc.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GlassContainer.card(
              surfaceStyle: GlassSurfaceStyle.solid,
              color: tc.cardBackground,
              shape: const LiquidRoundedSuperellipse(borderRadius: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: recentRooms.take(4).map((r) {
                  final relTime = _formatRelativeTime(r.lastVisitedMs);
                  return InkWell(
                    onTap: () {
                      _codeController.text = r.roomCode;
                      _handleJoinCast(r.roomCode);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tc.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              r.roomCode,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: tc.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.title,
                              style: TextStyle(fontSize: 12.5, color: tc.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (relTime.isNotEmpty) ...[
                            Text(
                              relTime,
                              style: TextStyle(fontSize: 11, color: tc.textTertiary),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 14, color: tc.textTertiary),
                            splashRadius: 14,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            onPressed: () async {
                              await RoomHistoryService.removeRoom(r.roomId);
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

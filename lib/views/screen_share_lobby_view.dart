import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../app_localization.dart';
import '../app_settings.dart';
import '../core/room_history_service.dart';
import '../core/room_session.dart';
import '../core/screen_share_service.dart';
import '../apple_glass.dart';
import 'screen_share_live_view.dart';
import 'screen_source_picker_dialog.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboard();
    });
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
      if (widget.session.roomCode == null || widget.session.roomCode!.isEmpty) {
        await widget.session.createRoom();
      }

      final castCode = widget.session.roomCode ?? (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();

      final success = await _service.startBroadcasting(
        source: opts.source,
        shareAudio: opts.shareAudio,
        targetFps: opts.fps,
        customTitle: opts.customTitle,
        castCode: castCode,
      );

      if (success && mounted) {
        await ScreenShareLiveView.launch(context, session: widget.session);
      } else if (mounted) {
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
      if (widget.session.roomCode != code) {
        await widget.session.joinRoomByCode(code);
      }

      final success = await _service.startViewing(castCode: code);
      if (success && mounted) {
        await ScreenShareLiveView.launch(context, session: widget.session);
      } else if (mounted) {
        setState(() => _errorMessage = _service.lastError ?? '无法连接到该投屏');
      }
    } catch (e) {
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
          constraints: const BoxConstraints(maxWidth: 680),
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
              Text(
                '端到端低延迟传输 · 智能声画分离与回声消除',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: tc.textTertiary,
                  letterSpacing: -0.2,
                ),
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
            '捕获应用窗口或手机屏幕，系统伴音无损直传，异地双人同看',
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

  Widget _buildActionBox(
    BuildContext context,
    AppI18n i18n,
    ThemeColors tc,
    bool isMobile,
    bool isShort,
  ) {
    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.cardBackground,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      padding: EdgeInsets.all(isShort ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Start Cast Primary Button
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      else
                        const Icon(Icons.screen_share_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _isConnecting ? i18n.screenShareConnecting : i18n.startScreenShare,
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
                '捕获指定应用窗口或整机屏幕',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: tc.textTertiary),
              ),
            ],
          ),

          SizedBox(height: isShort ? 12 : 16),

          // 2. Inset Subtle Divider
          Row(
            children: [
              Expanded(child: Divider(color: tc.glassBorder, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '或输入 6 位投屏码观看',
                  style: TextStyle(fontSize: 11, color: tc.textTertiary),
                ),
              ),
              Expanded(child: Divider(color: tc.glassBorder, height: 1)),
            ],
          ),

          SizedBox(height: isShort ? 12 : 16),

          // 3. Join Cast Input & Action
          isMobile
              ? Column(
                  children: [
                    GlassTextField(
                      key: const ValueKey('cast-code-input'),
                      controller: _codeController,
                      focusNode: _codeFocusNode,
                      placeholder: '输入 6 位投屏码',
                      height: isShort ? 38 : 44,
                      surfaceStyle: GlassSurfaceStyle.solid,
                      color: tc.inputBackground,
                      keyboardType: TextInputType.number,
                      textStyle: TextStyle(
                        color: tc.textPrimary,
                        fontSize: isShort ? 13 : 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      placeholderStyle: TextStyle(
                        color: tc.textTertiary,
                        fontSize: isShort ? 11.5 : 12,
                        letterSpacing: 0,
                        fontWeight: FontWeight.normal,
                      ),
                      onSubmitted: (val) => _isConnecting ? null : _handleJoinCast(val),
                    ),
                    SizedBox(height: isShort ? 8 : 10),
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: '一键粘贴',
                            child: LiquidGlassActionButton(
                              key: const ValueKey('cast-paste-btn'),
                              height: isShort ? 38 : 42,
                              onTap: _isConnecting ? () {} : _pasteFromClipboard,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.content_paste_rounded, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '粘贴并观看',
                                    style: TextStyle(fontSize: isShort ? 12.5 : 14),
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
                            label: '进入观看',
                            child: LiquidGlassActionButton(
                              key: const ValueKey('join-cast-btn'),
                              isPrimary: true,
                              height: isShort ? 38 : 42,
                              onTap: _isConnecting ? () {} : () => _handleJoinCast(),
                              child: Text(
                                '进入观看',
                                style: TextStyle(fontSize: isShort ? 12.5 : 14, fontWeight: FontWeight.w700),
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
                        key: const ValueKey('cast-code-input'),
                        controller: _codeController,
                        focusNode: _codeFocusNode,
                        placeholder: '输入 6 位投屏码',
                        height: isShort ? 38 : 44,
                        surfaceStyle: GlassSurfaceStyle.solid,
                        color: tc.inputBackground,
                        keyboardType: TextInputType.number,
                        textStyle: TextStyle(
                          color: tc.textPrimary,
                          fontSize: isShort ? 13 : 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        placeholderStyle: TextStyle(
                          color: tc.textTertiary,
                          fontSize: isShort ? 11.5 : 12,
                          letterSpacing: 0,
                          fontWeight: FontWeight.normal,
                        ),
                        onSubmitted: (val) => _isConnecting ? null : _handleJoinCast(val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    LiquidGlassActionButton(
                      key: const ValueKey('cast-paste-btn'),
                      width: 100,
                      height: isShort ? 38 : 44,
                      onTap: _isConnecting ? () {} : _pasteFromClipboard,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.content_paste_rounded, size: 15),
                          SizedBox(width: 4),
                          Text('粘贴', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    LiquidGlassActionButton(
                      key: const ValueKey('join-cast-btn'),
                      isPrimary: true,
                      width: 108,
                      height: isShort ? 38 : 44,
                      onTap: _isConnecting ? () {} : () => _handleJoinCast(),
                      child: const Text(
                        '进入观看',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildRecentCastsSection(BuildContext context, AppI18n i18n, ThemeColors tc) {
    final recentRooms = RoomHistoryService.recentRoomsNotifier.value;
    if (recentRooms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
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
            ],
          ),
        ),
        GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          color: tc.cardBackground,
          shape: const LiquidRoundedSuperellipse(borderRadius: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: recentRooms.take(3).map((r) {
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
                      Icon(Icons.arrow_forward_ios_rounded, size: 12, color: tc.textTertiary),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

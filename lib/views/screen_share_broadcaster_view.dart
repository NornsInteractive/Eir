import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../core/room_session.dart';
import 'draggable_cast_chat_capsule.dart';
import 'floating_emoji_reactions.dart';

/// Dedicated Cast Control Dashboard for Screen Share Broadcaster
/// Clean, hardware-inspired, and distinctly separate from the Cinema Room.
class ScreenShareBroadcasterView extends StatefulWidget {
  final RoomSession session;
  final VoidCallback onStopCast;

  const ScreenShareBroadcasterView({
    super.key,
    required this.session,
    required this.onStopCast,
  });

  @override
  State<ScreenShareBroadcasterView> createState() => _ScreenShareBroadcasterViewState();
}

class _ScreenShareBroadcasterViewState extends State<ScreenShareBroadcasterView> {
  Timer? _ticker;
  final List<FloatingEmojiData> _activeReactions = [];
  StreamSubscription<String>? _reactionSub;
  bool _copiedCode = false;
  bool _copiedLink = false;
  bool _showQrCode = false;
  Timer? _copiedCodeTimer;
  Timer? _copiedLinkTimer;

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _reactionSub = _service.onReaction.listen(_onReactionReceived);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _reactionSub?.cancel();
    _copiedCodeTimer?.cancel();
    _copiedLinkTimer?.cancel();
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onReactionReceived(String emoji) {
    if (!mounted) return;
    final item = FloatingEmojiData(
      id: UniqueKey().toString(),
      emoji: emoji,
      startX: 0.75 + (DateTime.now().millisecond % 20) / 100.0,
    );
    setState(() => _activeReactions.add(item));
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() => _activeReactions.removeWhere((e) => e.id == item.id));
      }
    });
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _handleStopCast() async {
    final tc = ThemeColors.of(context);
    final i18n = AppI18n.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer.card(
            surfaceStyle: GlassSurfaceStyle.solid,
            color: tc.cardBackground,
            shape: const LiquidRoundedSuperellipse(borderRadius: 22),
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
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      i18n.endScreenShare,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tc.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  i18n.confirmStopScreenShareMessage,
                  style: TextStyle(fontSize: 13, color: tc.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: LiquidGlassActionButton(
                        height: 42,
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: Text(i18n.cancel, style: TextStyle(color: tc.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LiquidGlassActionButton(
                        height: 42,
                        isPrimary: true,
                        onTap: () => Navigator.of(ctx).pop(true),
                        child: Text(i18n.endScreenShare, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

    if (confirm == true) {
      widget.onStopCast();
    }
  }

  void _copyCastCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _copiedCodeTimer?.cancel();
    setState(() => _copiedCode = true);
    _copiedCodeTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _copiedCode = false);
    });
  }

  void _copyWebCastLink(String code) {
    final webUrl = 'https://eir.norns.cc.cd?cast=$code';
    Clipboard.setData(ClipboardData(text: webUrl));
    _copiedLinkTimer?.cancel();
    setState(() => _copiedLink = true);
    _copiedLinkTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _copiedLink = false);
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final tc = ThemeColors.of(context);
    final i18n = AppI18n.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isMobile = screenWidth < 768;
    final castCode = _service.activeCastCode ?? widget.session.roomCode ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background soft ambient glow
          Positioned(
            top: -120,
            left: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tc.primary.withValues(alpha: 0.12),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 1. Top Glass App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: tc.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.screen_share_rounded, size: 20, color: tc.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  i18n.liveCastDashboard,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: tc.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.circle, size: 7, color: Colors.greenAccent),
                                      SizedBox(width: 4),
                                      Text(
                                        'LIVE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _service.duration != Duration.zero
                                  ? i18n.streamingDuration(_formatDuration(_service.duration))
                                  : i18n.streamingStable,
                              style: TextStyle(fontSize: 11.5, color: tc.textSecondary),
                            ),
                          ],
                        ),
                      ),

                      // Stop Cast Button (Destructive Liquid Glass)
                      LiquidGlassActionButton(
                        height: 38,
                        onTap: _handleStopCast,
                        color: Colors.redAccent.withValues(alpha: 0.16),
                        borderColor: Colors.redAccent.withValues(alpha: 0.35),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.stop_circle_rounded, size: 18, color: Colors.redAccent),
                            const SizedBox(width: 6),
                            Text(
                              i18n.endScreenShare,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(color: tc.glassBorder, height: 1),

                // 2. Main Dashboard Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 18 : 36,
                      vertical: 18,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Cast Code Card
                            GlassContainer.card(
                              surfaceStyle: GlassSurfaceStyle.solid,
                              color: tc.cardBackground,
                              shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                              child: Column(
                                children: [
                                  Text(
                                    i18n.viewerCastCodeLabel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: tc.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  GestureDetector(
                                    onTap: () => _copyCastCode(castCode),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: tc.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: _copiedCode
                                              ? Colors.greenAccent
                                              : tc.primary.withValues(alpha: 0.3),
                                          width: _copiedCode ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            castCode.length == 6
                                                ? '${castCode.substring(0, 3)}  ${castCode.substring(3)}'
                                                : castCode,
                                            style: TextStyle(
                                              fontSize: 32,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 4,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                              color: _copiedCode ? Colors.greenAccent : tc.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Icon(
                                            _copiedCode
                                                ? Icons.check_circle_rounded
                                                : Icons.copy_rounded,
                                            size: 20,
                                            color: _copiedCode ? Colors.greenAccent : tc.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    i18n.broadcasterCastCodePrompt,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: tc.textTertiary),
                                  ),
                                  const SizedBox(height: 16),
                                  // Quick Action Buttons
                                  Row(
                                    children: [
                                      Expanded(
                                        child: LiquidGlassActionButton(
                                          height: 38,
                                          onTap: () => _copyCastCode(castCode),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _copiedCode
                                                    ? Icons.check_circle_rounded
                                                    : Icons.copy_rounded,
                                                size: 14,
                                                color: _copiedCode ? Colors.greenAccent : null,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _copiedCode ? i18n.copiedBadge : i18n.copyCastCode,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: _copiedCode ? Colors.greenAccent : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: LiquidGlassActionButton(
                                          height: 38,
                                          isPrimary: true,
                                          onTap: () => _copyWebCastLink(castCode),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _copiedLink
                                                    ? Icons.check_circle_rounded
                                                    : Icons.link_rounded,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _copiedLink ? i18n.directLinkCopiedBadge : i18n.copyWebDirectLink,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // QR Code Toggle
                                  const SizedBox(height: 14),
                                  InkWell(
                                    onTap: () => setState(() => _showQrCode = !_showQrCode),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _showQrCode ? Icons.qr_code_2_rounded : Icons.qr_code_rounded,
                                            size: 16,
                                            color: tc.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _showQrCode ? i18n.hideWebQrCode : i18n.scanQrToWatchDirect,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: tc.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            _showQrCode
                                                ? Icons.keyboard_arrow_up_rounded
                                                : Icons.keyboard_arrow_down_rounded,
                                            size: 16,
                                            color: tc.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showQrCode) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.12),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: QrImageView(
                                        data: 'https://eir.norns.cc.cd?cast=$castCode',
                                        version: QrVersions.auto,
                                        size: 160.0,
                                        backgroundColor: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      i18n.scanQrInstantOpenHint,
                                      style: TextStyle(fontSize: 11, color: tc.textTertiary),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Friendly Guidance Banner
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: tc.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: tc.primary.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.phone_android_rounded, size: 18, color: tc.primary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          i18n.screenSharingActive,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: tc.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          i18n.screenSharingActiveDesc,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: tc.textSecondary,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Stream Stats & Status
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricCard(
                                    context,
                                    tc,
                                    icon: Icons.speed_rounded,
                                    label: i18n.streamingFramerate,
                                    value: '${_service.targetFps} FPS',
                                    sub: i18n.ultraClearLowLatency,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildMetricCard(
                                    context,
                                    tc,
                                    icon: Icons.people_alt_rounded,
                                    label: i18n.viewerStatus,
                                    value: _service.hasViewer
                                        ? i18n.viewersConnected(_service.viewerCount)
                                        : i18n.waitingForViewers,
                                    sub: i18n.p2pEncryptedDirect,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Controls Matrix
                            GlassContainer.card(
                              surfaceStyle: GlassSurfaceStyle.solid,
                              color: tc.cardBackground,
                              shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4, bottom: 12),
                                    child: Text(
                                      i18n.castControlsTitle,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: tc.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      // Mic Toggle
                                      Expanded(
                                        child: _buildControlButton(
                                          context,
                                          tc,
                                          icon: _service.isMicEnabled
                                              ? Icons.mic_rounded
                                              : Icons.mic_off_rounded,
                                          label: _service.isMicEnabled ? i18n.micOn : i18n.micMuted,
                                          isActive: _service.isMicEnabled,
                                          onTap: () => _service.toggleMic(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Audio Toggle
                                      Expanded(
                                        child: _buildControlButton(
                                          context,
                                          tc,
                                          icon: _service.isAudioEnabled
                                              ? Icons.volume_up_rounded
                                              : Icons.volume_off_rounded,
                                          label: _service.isAudioEnabled ? i18n.systemAudioOn : i18n.systemAudioMuted,
                                          isActive: _service.isAudioEnabled,
                                          onTap: () => _service.toggleAudio(),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      // Camera PiP Toggle
                                      Expanded(
                                        child: _buildControlButton(
                                          context,
                                          tc,
                                          icon: _service.isCameraEnabled
                                              ? Icons.videocam_rounded
                                              : Icons.videocam_off_rounded,
                                          label: _service.isCameraEnabled ? i18n.floatingAvatarOn : i18n.floatingAvatarOff,
                                          isActive: _service.isCameraEnabled,
                                          onTap: () => _service.toggleCamera(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      // Danmaku Toggle
                                      Expanded(
                                        child: _buildControlButton(
                                          context,
                                          tc,
                                          icon: _service.danmakuEnabled
                                              ? Icons.subtitles_rounded
                                              : Icons.subtitles_off_rounded,
                                          label: _service.danmakuEnabled ? i18n.chatDanmakuOn : i18n.chatDanmakuHidden,
                                          isActive: _service.danmakuEnabled,
                                          onTap: () => _service.toggleDanmaku(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Background Running & Home Tip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: tc.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: tc.primary.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.lightbulb_rounded, size: 20, color: tc.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          i18n.castServiceRunningBackground,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: tc.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          i18n.castBackgroundGuide,
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.45,
                                            color: tc.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2.5 Floating Emoji Reactions Layer (Broadcaster Visibility)
          ..._activeReactions.map((item) {
            return FloatingEmojiWidget(
              key: ValueKey(item.id),
              emoji: item.emoji,
              startX: item.startX,
            );
          }),

          // 3. Draggable Floating Chat Capsule (Requirement 5)
          DraggableCastChatCapsule(session: widget.session),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context,
    ThemeColors tc, {
    required IconData icon,
    required String label,
    required String value,
    required String sub,
  }) {
    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.cardBackground,
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tc.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tc.textSecondary),
              ),
              const Spacer(),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.5),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tc.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(fontSize: 11, color: tc.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    BuildContext context,
    ThemeColors tc, {
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? tc.primary.withValues(alpha: 0.15) : tc.inputBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? tc.primary.withValues(alpha: 0.4) : tc.glassBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? tc.primary : tc.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? tc.primary : tc.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

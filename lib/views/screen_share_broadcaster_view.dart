import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../core/room_session.dart';
import '../core/screen_share_service.dart';
import 'draggable_cast_chat_capsule.dart';
import 'screen_source_picker_dialog.dart';

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

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _handleStopCast() async {
    final tc = ThemeColors.of(context);
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
                      '结束投屏',
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
                  '确定要停止当前投屏并断开所有连接吗？',
                  style: TextStyle(fontSize: 13, color: tc.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: LiquidGlassActionButton(
                        height: 42,
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: Text('取消', style: TextStyle(color: tc.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LiquidGlassActionButton(
                        height: 42,
                        isPrimary: true,
                        onTap: () => Navigator.of(ctx).pop(true),
                        child: const Text('结束投屏', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('投屏码已复制到剪贴板'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyWebCastLink(String code) {
    final webUrl = 'https://eir.norns.cc.cd?cast=$code';
    Clipboard.setData(ClipboardData(text: webUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('网页免装观看直链已复制！对方浏览器打开秒看'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
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
                                  '实时投屏控制台',
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
                                  ? '已推流 ${_formatDuration(_service.duration)}'
                                  : '正在稳定推流中...',
                              style: TextStyle(fontSize: 11.5, color: tc.textSecondary),
                            ),
                          ],
                        ),
                      ),

                      // Stop Cast Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.88),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(Icons.stop_circle_rounded, size: 18),
                        label: const Text('结束投屏', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        onPressed: _handleStopCast,
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
                                    '观众连接投屏码',
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
                                        border: Border.all(color: tc.primary.withValues(alpha: 0.3)),
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
                                              color: tc.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Icon(Icons.copy_rounded, size: 20, color: tc.primary),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '对方在手机或电脑打开 Eir 输入投屏码，即可同步观看你的屏幕',
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
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.copy_rounded, size: 14),
                                              SizedBox(width: 6),
                                              Text('复制投屏码', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
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
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.link_rounded, size: 16),
                                              SizedBox(width: 6),
                                              Text('复制网页直链', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                          '屏幕正在实时共享中',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: tc.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '你可以切换到任意应用（如抖音、相册、游戏或浏览器），好友即可同步看到你的操作与伴音；观众发来的消息将显示在悬浮气泡中。',
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
                                    label: '推流帧率',
                                    value: '${_service.targetFps} FPS',
                                    sub: '超清低延迟',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildMetricCard(
                                    context,
                                    tc,
                                    icon: Icons.people_alt_rounded,
                                    label: '观看状态',
                                    value: _service.hasViewer
                                        ? '${_service.viewerCount} 位观众 (已连接)'
                                        : '等待观众加入',
                                    sub: 'P2P 加密直连',
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
                                      '投屏控制',
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
                                          label: _service.isMicEnabled ? '麦克风开启' : '麦克风静音',
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
                                          label: _service.isAudioEnabled ? '系统伴音开' : '伴音静音',
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
                                          label: _service.isCameraEnabled ? '悬浮头像开' : '悬浮头像关',
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
                                          label: _service.danmakuEnabled ? '消息弹幕开' : '弹幕已隐藏',
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
                                          '投屏服务已在后台稳定运行',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: tc.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '您可以返回手机桌面打开王者荣耀、B站、文档或游戏，画面和声音都将持续实时传输。轻触屏幕上的【可拖动聊天胶囊】可随时与观众互动。',
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

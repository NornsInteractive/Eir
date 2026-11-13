import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../core/room_session.dart';
import '../core/screen_share_service.dart';
import 'screen_source_picker_dialog.dart';

/// Fullscreen live canvas for 60 FPS screen and window sharing
class ScreenShareLiveView extends StatefulWidget {
  final RoomSession session;

  const ScreenShareLiveView({
    super.key,
    required this.session,
  });

  static Future<void> launch(BuildContext context, {required RoomSession session}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => ScreenShareLiveView(session: session),
      ),
    );
  }

  @override
  State<ScreenShareLiveView> createState() => _ScreenShareLiveViewState();
}

class _ScreenShareLiveViewState extends State<ScreenShareLiveView> {
  bool _controlsVisible = true;
  bool _isFullscreen = false;
  final List<_FloatingEmojiData> _activeReactions = [];
  StreamSubscription<String>? _reactionSub;

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _reactionSub = _service.onReaction.listen(_onReactionReceived);
  }

  @override
  void dispose() {
    _reactionSub?.cancel();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onReactionReceived(String emoji) {
    if (!mounted) return;
    final item = _FloatingEmojiData(
      id: UniqueKey().toString(),
      emoji: emoji,
      startX: 0.7 + (DateTime.now().millisecond % 25) / 100.0,
    );
    setState(() => _activeReactions.add(item));
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() => _activeReactions.removeWhere((e) => e.id == item.id));
      }
    });
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
    if (!_service.isActive && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tc = ThemeColors.of(context);

    final isBroadcasting = _service.isBroadcasting;
    final renderer = isBroadcasting ? _service.localRenderer : _service.remoteRenderer;
    final code = _service.activeCastCode ?? widget.session.roomCode ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. WebRTC Video Canvas
            Center(
              child: _service.renderersInitialized
                  ? RTCVideoView(
                      renderer,
                      objectFit: _service.isCoverMode
                          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
                          : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      mirror: false,
                    )
                  : const CircularProgressIndicator(color: Colors.white70),
            ),

            // 1.5 Floating Emoji Reactions Layer
            ..._activeReactions.map((item) {
              return _FloatingEmojiWidget(
                key: ValueKey(item.id),
                emoji: item.emoji,
                startX: item.startX,
              );
            }),

            // 2. Top HUD Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _controlsVisible ? 0 : -90,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Back Button
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),

                      // Cast Code Pill
                      if (code.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(i18n.castCodeCopied),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24, width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.tag_rounded, color: Colors.white70, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '投屏码: $code',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.copy_rounded, color: Colors.white70, size: 12),
                              ],
                            ),
                          ),
                        ),

                      const Spacer(),

                      // 60 FPS Live indicator (clickable for stream health HUD)
                      GestureDetector(
                        onTap: () => _showStreamHealthSheet(context, i18n, tc),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_service.targetFps} FPS',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Duration Pill
                      Text(
                        _formatDuration(_service.duration),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2.8 Floating Emoji Quick Dock
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _controlsVisible ? 94 : -60,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: ['❤️', '😂', '🔥', '👏', '666'].map((emoji) {
                    return InkWell(
                      onTap: () => _service.sendReaction(emoji),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(emoji, style: const TextStyle(fontSize: 18)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // 3. Bottom HUD Controls Platter
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _controlsVisible ? 24 : -110,
              left: 20,
              right: 20,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24, width: 0.8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Audio Mixer & Mute Button
                        IconButton(
                          tooltip: i18n.audioMixer,
                          icon: Icon(
                            _service.isMuted ? Icons.volume_off_rounded : Icons.tune_rounded,
                            color: _service.isMuted ? Colors.redAccent : Colors.white,
                            size: 22,
                          ),
                          onPressed: () => _showAudioMixerSheet(context, i18n, tc),
                        ),

                        // Talkback Mic
                        IconButton(
                          tooltip: _service.isMicEnabled ? '关闭对讲' : '开启对讲',
                          icon: Icon(
                            _service.isMicEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                            color: _service.isMicEnabled ? Colors.greenAccent : Colors.white70,
                            size: 22,
                          ),
                          onPressed: () => _service.toggleMic(),
                        ),

                        // Aspect Ratio Toggle (Cover vs Contain)
                        IconButton(
                          tooltip: _service.isCoverMode ? i18n.aspectRatioContain : i18n.aspectRatioCover,
                          icon: Icon(
                            _service.isCoverMode ? Icons.fit_screen_rounded : Icons.crop_free_rounded,
                            color: _service.isCoverMode ? Colors.amberAccent : Colors.white,
                            size: 22,
                          ),
                          onPressed: () => _service.toggleAspectMode(),
                        ),

                        // Switch Source (if desktop broadcaster)
                        if (_service.isBroadcaster)
                          IconButton(
                            tooltip: i18n.switchScreenShareSource,
                            icon: const Icon(Icons.switch_video_rounded, color: Colors.white, size: 22),
                            onPressed: () async {
                              final opts = await ScreenSourcePickerDialog.show(context);
                              if (opts != null && mounted) {
                                await _service.stop(reason: 'switching_source');
                                await _service.startBroadcasting(
                                  source: opts.source,
                                  shareAudio: opts.shareAudio,
                                  targetFps: opts.fps,
                                  customTitle: opts.customTitle,
                                  castCode: code,
                                );
                              }
                            },
                          ),

                        // Fullscreen Toggle
                        IconButton(
                          tooltip: _isFullscreen ? '退出全屏' : '全屏',
                          icon: Icon(
                            _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: _toggleFullscreen,
                        ),

                        const SizedBox(width: 8),

                        // Stop / Disconnect Button
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          icon: const Icon(Icons.stop_rounded, size: 18),
                          label: Text(
                            isBroadcasting ? i18n.stopScreenShare : '退出观看',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            await _service.stop(reason: 'user_exit');
                            if (mounted) Navigator.of(context).maybePop();
                          },
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
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _showAudioMixerSheet(BuildContext context, AppI18n i18n, ThemeColors tc) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                margin: const EdgeInsets.all(16),
                child: GlassContainer.card(
                  surfaceStyle: GlassSurfaceStyle.solid,
                  color: tc.cardBackground,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 20, color: tc.primary),
                          const SizedBox(width: 8),
                          Text(
                            i18n.audioMixer,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tc.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20, color: tc.textSecondary),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Companion Volume Slider
                      Row(
                        children: [
                          Icon(Icons.music_note_rounded, size: 18, color: tc.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              i18n.companionVolume,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: tc.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${(_service.companionVolume * 100).round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tc.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _service.companionVolume,
                        min: 0.0,
                        max: 1.0,
                        activeColor: tc.primary,
                        inactiveColor: tc.glassBorder,
                        onChanged: (val) {
                          setSheetState(() => _service.setCompanionVolume(val));
                        },
                      ),
                      const SizedBox(height: 12),

                      // Voice Volume Slider
                      Row(
                        children: [
                          Icon(Icons.record_voice_over_rounded, size: 18, color: tc.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              i18n.voiceVolume,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: tc.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${(_service.voiceVolume * 100).round()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tc.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _service.voiceVolume,
                        min: 0.0,
                        max: 2.0,
                        activeColor: tc.primary,
                        inactiveColor: tc.glassBorder,
                        onChanged: (val) {
                          setSheetState(() => _service.setVoiceVolume(val));
                        },
                      ),
                      const SizedBox(height: 12),

                      // Smart Audio Ducking
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: tc.glassSurfaceSubtle,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: tc.glassBorderSubtle, width: 0.8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    i18n.audioDucking,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: tc.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '连麦说话时自动压低画面伴音40%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tc.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _service.isAudioDuckingEnabled,
                              activeColor: tc.primary,
                              onChanged: (val) {
                                setSheetState(() => _service.setAudioDucking(val));
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Anti-echo trust note
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_user_rounded, size: 14, color: tc.success),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              i18n.echoFreeNotice,
                              style: TextStyle(
                                fontSize: 11,
                                color: tc.textSecondary,
                              ),
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
        },
      ),
    );
  }

  void _showStreamHealthSheet(BuildContext context, AppI18n i18n, ThemeColors tc) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            margin: const EdgeInsets.all(16),
            child: GlassContainer.card(
              surfaceStyle: GlassSurfaceStyle.solid,
              color: tc.cardBackground,
              shape: const LiquidRoundedSuperellipse(borderRadius: 24),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.monitor_heart_rounded, size: 20, color: tc.primary),
                      const SizedBox(width: 8),
                      Text(
                        i18n.streamHealthTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tc.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 20, color: tc.textSecondary),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildMetricRow(i18n.fpsMetric, '${_service.targetFps} FPS', Colors.greenAccent, tc),
                  const Divider(height: 16),
                  _buildMetricRow(i18n.rttMetric, '${_service.rttMs} ms', tc.primary, tc),
                  const Divider(height: 16),
                  _buildMetricRow(i18n.bitrateMetric, '${_service.bitrateMbps.toStringAsFixed(1)} Mbps', tc.textPrimary, tc),
                  const Divider(height: 16),
                  _buildMetricRow(i18n.packetLossMetric, '${(_service.packetLoss * 100).toStringAsFixed(1)}%', tc.success, tc),
                  const Divider(height: 16),
                  _buildMetricRow('画面比例模式', _service.isCoverMode ? i18n.aspectRatioCover : i18n.aspectRatioContain, tc.textSecondary, tc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor, ThemeColors tc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: tc.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _FloatingEmojiData {
  final String id;
  final String emoji;
  final double startX;

  _FloatingEmojiData({
    required this.id,
    required this.emoji,
    required this.startX,
  });
}

class _FloatingEmojiWidget extends StatefulWidget {
  final String emoji;
  final double startX;

  const _FloatingEmojiWidget({
    super.key,
    required this.emoji,
    required this.startX,
  });

  @override
  State<_FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<_FloatingEmojiWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final val = _progress.value;
        final opacity = (1.0 - val).clamp(0.0, 1.0);
        final bottomOffset = 100.0 + val * 380.0;
        final xWobble = math.sin(val * math.pi * 3) * 16.0;

        return Positioned(
          bottom: bottomOffset,
          right: (MediaQuery.of(context).size.width * (1.0 - widget.startX)) + xWobble,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: 0.8 + val * 0.5,
              child: Text(
                widget.emoji,
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
        );
      },
    );
  }
}

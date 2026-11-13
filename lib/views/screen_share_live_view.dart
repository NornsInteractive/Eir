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

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
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
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      mirror: false,
                    )
                  : const CircularProgressIndicator(color: Colors.white70),
            ),

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

                      // 60 FPS Live indicator
                      Container(
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
                        // Audio Mute / Unmute
                        IconButton(
                          tooltip: _service.isMuted ? '取消静音' : '静音',
                          icon: Icon(
                            _service.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: _service.isMuted ? Colors.redAccent : Colors.white,
                            size: 22,
                          ),
                          onPressed: () => _service.toggleMute(),
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
}

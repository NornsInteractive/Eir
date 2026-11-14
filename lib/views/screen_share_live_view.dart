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
  StreamSubscription<ChatMessage>? _chatSub;
  final List<_FloatingDanmakuItem> _activeDanmaku = [];
  Offset _cameraPipOffset = const Offset(16, 70);

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _reactionSub = _service.onReaction.listen(_onReactionReceived);
    _chatSub = _service.onChatMessage.listen(_onChatMessageReceived);
  }

  @override
  void dispose() {
    _reactionSub?.cancel();
    _chatSub?.cancel();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onChatMessageReceived(ChatMessage msg) {
    if (!mounted || !_service.danmakuEnabled) return;
    final item = _FloatingDanmakuItem(
      id: UniqueKey().toString(),
      message: msg,
    );
    setState(() {
      _activeDanmaku.add(item);
      if (_activeDanmaku.length > 3) {
        _activeDanmaku.removeAt(0);
      }
    });
    Future.delayed(const Duration(milliseconds: 6000), () {
      if (mounted) {
        setState(() => _activeDanmaku.removeWhere((e) => e.id == item.id));
      }
    });
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

            // 1.8 Floating Danmaku Chat Stream (Bottom Left)
            if (_service.danmakuEnabled && _activeDanmaku.isNotEmpty)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _controlsVisible ? 104 : 36,
                left: 20,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _activeDanmaku.map((item) {
                      return _FloatingDanmakuBubble(
                        key: ValueKey(item.id),
                        message: item.message,
                        onTap: () {
                          _service.markMessagesAsRead();
                          _showChatSheet(context, i18n, tc);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),

            // 1.9 Draggable Floating Camera PiP Capsule
            if (_service.isCameraEnabled || _service.isRemoteCameraActive)
              Positioned(
                left: _cameraPipOffset.dx,
                top: _cameraPipOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final size = MediaQuery.of(context).size;
                    setState(() {
                      _cameraPipOffset = Offset(
                        (_cameraPipOffset.dx + details.delta.dx).clamp(10.0, size.width - 145.0),
                        (_cameraPipOffset.dy + details.delta.dy).clamp(30.0, size.height - 190.0),
                      );
                    });
                  },
                  child: _FloatingCameraPiPCapsule(
                    service: _service,
                    onToggleCamera: () => _service.toggleCamera(),
                    onSwitchCamera: () => _service.switchCamera(),
                  ),
                ),
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
                        Container(
                          decoration: _service.isMicEnabled
                              ? BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.greenAccent.withValues(alpha: 0.45),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                )
                              : null,
                          child: IconButton(
                            tooltip: _service.isMicEnabled ? '关闭对讲' : '开启对讲',
                            icon: Icon(
                              _service.isMicEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                              color: _service.isMicEnabled ? Colors.greenAccent : Colors.white70,
                              size: 22,
                            ),
                            onPressed: () => _service.toggleMic(),
                          ),
                        ),

                        // Camera PiP Video Talkback
                        IconButton(
                          tooltip: _service.isCameraEnabled ? '关闭摄像头' : i18n.cameraToggle,
                          icon: Icon(
                            _service.isCameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                            color: _service.isCameraEnabled ? Colors.greenAccent : Colors.white70,
                            size: 22,
                          ),
                          onPressed: () => _service.toggleCamera(),
                        ),

                        // Chat Button with unread counter badge
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              tooltip: i18n.castChat,
                              icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 21),
                              onPressed: () {
                                _service.markMessagesAsRead();
                                _showChatSheet(context, i18n, tc);
                              },
                            ),
                            if (_service.unreadCount > 0)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  child: Text(
                                    _service.unreadCount > 99 ? '99+' : '${_service.unreadCount}',
                                    style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
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

  void _showChatSheet(BuildContext context, AppI18n i18n, ThemeColors tc) {
    final textController = TextEditingController();
    final scrollController = ScrollController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final mediaQuery = MediaQuery.of(context);
          final keyboardHeight = mediaQuery.viewInsets.bottom;
          final messages = _service.messages;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                margin: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: keyboardHeight + 16,
                  top: 40,
                ),
                child: GlassContainer.card(
                  surfaceStyle: GlassSurfaceStyle.solid,
                  color: tc.cardBackground,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Icon(Icons.chat_bubble_rounded, size: 20, color: tc.primary),
                          const SizedBox(width: 8),
                          Text(
                            i18n.castChat,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tc.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tc.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${messages.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: tc.primary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Danmaku switch
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                i18n.danmakuToggle,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: tc.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Transform.scale(
                                scale: 0.75,
                                child: Switch.adaptive(
                                  value: _service.danmakuEnabled,
                                  activeColor: tc.primary,
                                  onChanged: (val) {
                                    setSheetState(() => _service.toggleDanmaku());
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20, color: tc.textSecondary),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Divider(height: 14),

                      // Messages List
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280, minHeight: 140),
                        child: messages.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.chat_outlined, size: 36, color: tc.textTertiary),
                                    const SizedBox(height: 8),
                                    Text(
                                      i18n.noMessagesYet,
                                      style: TextStyle(color: tc.textTertiary, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                reverse: true,
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final msg = messages[messages.length - 1 - index];
                                  final isSelf = msg.isSelf;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!isSelf) ...[
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: tc.primary.withValues(alpha: 0.2),
                                            child: Text(
                                              msg.senderName.isNotEmpty ? msg.senderName.characters.first : 'U',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: tc.primary),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isSelf
                                                  ? tc.primary.withValues(alpha: 0.85)
                                                  : tc.glassSurfaceSubtle,
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(14),
                                                topRight: const Radius.circular(14),
                                                bottomLeft: Radius.circular(isSelf ? 14 : 2),
                                                bottomRight: Radius.circular(isSelf ? 2 : 14),
                                              ),
                                              border: Border.all(
                                                color: isSelf ? Colors.transparent : tc.glassBorderSubtle,
                                                width: 0.6,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                              children: [
                                                if (!isSelf)
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 2),
                                                    child: Text(
                                                      msg.senderName,
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: tc.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  msg.text,
                                                  style: TextStyle(
                                                    color: isSelf ? Colors.white : tc.textPrimary,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (isSelf) const SizedBox(width: 4),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Quick phrases chips
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['收到！', '好的', '看这里', '太赞了', '👍', '❤️', '666'].map((phrase) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () {
                                  _service.sendChatMessage(phrase);
                                  setSheetState(() {});
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: tc.glassSurfaceSubtle,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: tc.glassBorderSubtle, width: 0.6),
                                  ),
                                  child: Text(
                                    phrase,
                                    style: TextStyle(fontSize: 11.5, color: tc.textSecondary),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Input bar
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: tc.glassSurfaceSubtle,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: tc.glassBorderSubtle, width: 0.8),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: TextField(
                                controller: textController,
                                style: TextStyle(color: tc.textPrimary, fontSize: 13.5),
                                decoration: InputDecoration(
                                  hintText: i18n.sendChatMessageHint,
                                  hintStyle: TextStyle(color: tc.textTertiary, fontSize: 12.5),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                onSubmitted: (val) {
                                  if (val.trim().isNotEmpty) {
                                    _service.sendChatMessage(val);
                                    textController.clear();
                                    setSheetState(() {});
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.send_rounded, color: tc.primary, size: 22),
                            onPressed: () {
                              final text = textController.text.trim();
                              if (text.isNotEmpty) {
                                _service.sendChatMessage(text);
                                textController.clear();
                                setSheetState(() {});
                              }
                            },
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

class _FloatingDanmakuItem {
  final String id;
  final ChatMessage message;

  _FloatingDanmakuItem({
    required this.id,
    required this.message,
  });
}

class _FloatingDanmakuBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onTap;

  const _FloatingDanmakuBubble({
    super.key,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  message.senderName.isNotEmpty ? message.senderName.characters.first : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${message.senderName}: ',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: message.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingCameraPiPCapsule extends StatelessWidget {
  final ScreenShareService service;
  final VoidCallback onToggleCamera;
  final VoidCallback onSwitchCamera;

  const _FloatingCameraPiPCapsule({
    required this.service,
    required this.onToggleCamera,
    required this.onSwitchCamera,
  });

  @override
  Widget build(BuildContext context) {
    final isLocal = service.isCameraEnabled;
    final renderer = isLocal ? service.localCameraRenderer : service.remoteCameraRenderer;

    return Container(
      width: 124,
      height: 165,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.greenAccent.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (service.cameraRenderersInitialized && renderer.srcObject != null)
            RTCVideoView(
              renderer,
              mirror: isLocal && service.isFrontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            const Center(
              child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 36),
            ),

          // Header Bar
          Positioned(
            top: 4,
            left: 6,
            right: 4,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isLocal ? '本机' : '连麦',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (isLocal)
                  GestureDetector(
                    onTap: onSwitchCamera,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 14),
                    ),
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onToggleCamera,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

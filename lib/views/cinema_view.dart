import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../models.dart';
import 'danmaku_overlay.dart';
import 'settings_dialog.dart';
import 'profile_view.dart';

class CinemaView extends StatefulWidget {
  final RoomSession session;
  final VoidCallback onLeaveRoom;
  final int initialTabIndex;

  const CinemaView({
    super.key,
    required this.session,
    required this.onLeaveRoom,
    this.initialTabIndex = 0,
  });

  @override
  State<CinemaView> createState() => _CinemaViewState();
}

class _CinemaViewState extends State<CinemaView> {
  late final VideoController _videoController;
  int _selectedTabIndex = 0; // 0: Playlist, 1: Peers & ACL, 2: Session Info
  bool _isMuted = false;
  double _volume = 1.0;
  double _brightness = 1.0;
  bool _isFullscreen = false;
  bool _isLandscape = false;
  bool _isScrubbing = false;
  bool _isVerticalDragging = false;
  DateTime? _lastSeekTime;
  Duration? _scrubTarget;
  Duration? _scrubStart;
  int _scrubDeltaSec = 0;
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _isLocked = false;
  BoxFit _aspectFit = BoxFit.contain;
  String? _gestureHudType;
  Timer? _gestureHudTimer;
  double? _draggingSliderValue;
  double? _optimisticSeekRatio;
  Timer? _optimisticSeekTimer;
  String? _playerToastMessage;
  IconData? _playerToastIcon;
  Timer? _playerToastTimer;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _bufferingSub;
  String? _lastReportedCinemaError;
  bool _danmakuEnabled = true;
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  Offset _pipOffset = const Offset(16, 120);
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _isLongPressSpeeding = false;
  double _preSpeedRate = 1.0;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
    _videoController = VideoController(widget.session.player);
    _subscribePlayerStreams(widget.session.player);
    widget.session.addListener(_onSessionStateChanged);
    widget.session.callSession.addListener(_onCallSessionChanged);
    _lastReportedCinemaError = widget.session.lastErrorCode;
    _restartControlsTimer();
  }

  @override
  void didUpdateWidget(CinemaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.player != widget.session.player) {
      _subscribePlayerStreams(widget.session.player);
      _videoController = VideoController(widget.session.player);
    }
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSessionStateChanged);
      oldWidget.session.callSession.removeListener(_onCallSessionChanged);
      widget.session.addListener(_onSessionStateChanged);
      widget.session.callSession.addListener(_onCallSessionChanged);
    }
  }

  void _onCallSessionChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionStateChanged() {
    final code = widget.session.lastErrorCode;
    if (code != null && code.isNotEmpty && code != _lastReportedCinemaError) {
      _lastReportedCinemaError = code;
      _showCinemaErrorSnackBar(code);
    } else if (code == null || code.isEmpty) {
      _lastReportedCinemaError = null;
    }
  }

  void _showCinemaErrorSnackBar(String code) {
    if (!mounted) return;
    final i18n = AppI18n.of(context);
    final isStorageFull = code == 'storage_full';
    final isConnectionError =
        code == 'signaling_unavailable' ||
        code == 'connection_failed' ||
        widget.session.connectionState == RoomConnectionState.disconnected;

    showLiquidGlassSnackBar(
      context,
      owner: this,
      message: i18n.mapErrorCode(code),
      icon: isStorageFull
          ? Icons.disc_full_rounded
          : Icons.error_outline_rounded,
      onAction: isStorageFull
          ? () => SettingsDialog.show(context, session: widget.session)
          : null,
      actionLabel: isStorageFull ? i18n.clearCacheBtn : null,
      actionKey: isStorageFull
          ? const ValueKey('cinema-storage-full-clean-btn')
          : null,
      actionIcon: isStorageFull ? Icons.cleaning_services_rounded : null,
      onRetry: isConnectionError
          ? () async {
              _lastReportedCinemaError = null;
              await widget.session.retry();
            }
          : null,
      retryLabel: isConnectionError ? i18n.retryConnection : null,
      retryKey: isConnectionError
          ? const ValueKey('cinema-snackbar-retry-connection-btn')
          : null,
      duration: const Duration(seconds: 5),
    );
  }

  void _subscribePlayerStreams(Player player) {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub = player.stream.position.listen((pos) {
      if (_optimisticSeekRatio != null) {
        final dur = player.state.duration;
        if (dur > Duration.zero) {
          final targetMs = (dur.inMilliseconds * _optimisticSeekRatio!).round();
          if ((pos.inMilliseconds - targetMs).abs() < 1000) {
            _optimisticSeekRatio = null;
            _optimisticSeekTimer?.cancel();
          }
        }
      }
      if (mounted) setState(() {});
    });
    _durationSub = player.stream.duration.listen((_) {
      if (mounted) setState(() {});
    });
    _completedSub = player.stream.completed.listen((_) {
      if (mounted) setState(() {});
    });
    _bufferingSub = player.stream.buffering.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (_isFullscreen || _isLandscape) {
      if (!kIsWeb) {
        try {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } catch (_) {}
      }
    }
    _controlsTimer?.cancel();
    _gestureHudTimer?.cancel();
    _playerToastTimer?.cancel();
    _optimisticSeekTimer?.cancel();
    hideLiquidGlassSnackBar();
    widget.session.removeListener(_onSessionStateChanged);
    widget.session.callSession.removeListener(_onCallSessionChanged);
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    _keyboardFocusNode.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    // Note: widget.session.player is owned by widget.session, do not dispose player here!
    super.dispose();
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    setState(() {
      _isFullscreen = fullscreen;
    });
    if (!kIsWeb) {
      if (fullscreen) {
        try {
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          _isLandscape = true;
        } catch (_) {}
      } else {
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          _isLandscape = false;
        } catch (_) {}
      }
    }
  }

  Future<void> _toggleOrientation() async {
    final nextLandscape = !_isLandscape;
    setState(() {
      _isLandscape = nextLandscape;
    });
    if (!kIsWeb) {
      try {
        if (nextLandscape) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
        }
      } catch (_) {}
    }
  }

  void _onHorizontalDragStart(
    DragStartDetails details,
    Duration currentPos,
    Duration mediaDuration,
  ) {
    if (_isLocked || _isVerticalDragging || mediaDuration.inMilliseconds <= 0) {
      return;
    }
    _isScrubbing = true;
    _scrubStart = currentPos;
    _scrubTarget = currentPos;
    _scrubDeltaSec = 0;
    _restartControlsTimer();
    setState(() {});
  }

  void _onHorizontalDragUpdate(
    DragUpdateDetails details,
    Duration mediaDuration,
    double screenWidth,
  ) {
    if (!_isScrubbing ||
        _scrubStart == null ||
        mediaDuration.inMilliseconds <= 0) {
      return;
    }
    final double scale = (mediaDuration.inSeconds > 0)
        ? (mediaDuration.inSeconds / 180.0).clamp(0.2, 1.5)
        : 0.5;
    final int deltaMs = ((details.primaryDelta ?? 0) * scale * 250).toInt();
    final newTargetMs = (_scrubTarget!.inMilliseconds + deltaMs).clamp(
      0,
      mediaDuration.inMilliseconds,
    );
    _scrubTarget = Duration(milliseconds: newTargetMs);
    _scrubDeltaSec =
        (_scrubTarget!.inMilliseconds - _scrubStart!.inMilliseconds) ~/ 1000;
    setState(() {});
  }

  void _onHorizontalDragEnd(DragEndDetails details, bool isHostOrAdmin) {
    if (!_isScrubbing) return;
    final target = _scrubTarget;
    _isScrubbing = false;
    _isVerticalDragging = false;
    setState(() {});
    if (isHostOrAdmin && target != null) {
      widget.session.seek(target);
    }
    _restartControlsTimer();
  }

  void _onHorizontalDragCancel() {
    _isVerticalDragging = false;
    if (_isScrubbing) {
      setState(() {
        _isScrubbing = false;
      });
    }
  }

  void _restartControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls && !_isLocked) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() => _showControls = !_showControls);
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _restartControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void _showGestureHud(String type) {
    setState(() {
      _gestureHudType = type;
    });
    _gestureHudTimer?.cancel();
    _gestureHudTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _gestureHudType == type) {
        setState(() => _gestureHudType = null);
      }
    });
  }

  Future<void> _seekRelative(int seconds) async {
    _showGestureHud(seconds > 0 ? 'forward' : 'rewind');
    try {
      await widget.session.seekRelative(Duration(seconds: seconds));
    } catch (_) {}
    _restartControlsTimer();
  }

  void _onSliderSeek(double val, Duration mediaDuration) {
    if (mediaDuration.inMilliseconds <= 0) return;
    final now = DateTime.now();
    if (_lastSeekTime != null &&
        now.difference(_lastSeekTime!).inMilliseconds < 120) {
      return;
    }
    _lastSeekTime = now;
    _restartControlsTimer();
    final clamped = val.clamp(0.0, 1.0);
    final targetMs = (clamped * mediaDuration.inMilliseconds).round();
    _optimisticSeekTimer?.cancel();
    setState(() {
      _draggingSliderValue = null;
      _optimisticSeekRatio = clamped;
    });
    _optimisticSeekTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _optimisticSeekRatio = null);
      }
    });
    try {
      widget.session.seek(Duration(milliseconds: targetMs));
    } catch (_) {}
  }

  Future<void> _confirmAndLeaveRoom(BuildContext context) async {
    final session = widget.session;
    final isOwner = session.role == RoomRole.owner;
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    final shouldLeave = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            margin: const EdgeInsets.all(24),
            child: GlassContainer.card(
              surfaceStyle: GlassSurfaceStyle.solid,
              color: tc.cardBackground,
              shape: const LiquidRoundedSuperellipse(borderRadius: 20),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOwner
                            ? Icons.warning_amber_rounded
                            : Icons.logout_rounded,
                        size: 22,
                        color: isOwner ? tc.warning : tc.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isOwner ? i18n.disbandRoom : i18n.leaveRoom,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: tc.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    isOwner
                        ? i18n.disbandRoomConfirmMessage
                        : i18n.leaveRoomConfirmMessage,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: tc.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      LiquidGlassActionButton(
                        onTap: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          i18n.cancel,
                          style: TextStyle(color: tc.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      LiquidGlassActionButton(
                        isPrimary: true,
                        onTap: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          isOwner ? i18n.actionDisband : i18n.actionLeave,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
    );

    if (shouldLeave == true && mounted) {
      if (isOwner) {
        await session.closeRoom();
      } else {
        await session.leaveRoom();
      }
      widget.onLeaveRoom();
    }
  }

  void _cycleAspectRatio() {
    setState(() {
      if (_aspectFit == BoxFit.contain) {
        _aspectFit = BoxFit.cover;
      } else if (_aspectFit == BoxFit.cover) {
        _aspectFit = BoxFit.fill;
      } else {
        _aspectFit = BoxFit.contain;
      }
    });
    _restartControlsTimer();
    final i18n = AppI18n.of(context);
    final fitName = _aspectFit == BoxFit.contain
        ? i18n.aspectFitContain
        : (_aspectFit == BoxFit.cover ? i18n.aspectFitCover : i18n.aspectFitFill);
    _showPlayerToast(i18n.aspectRatioToast(fitName), Icons.aspect_ratio_rounded);
  }

  PlaylistItem? get _currentPlaylistItem {
    final curId = widget.session.currentItemId;
    if (curId == null) return null;
    try {
      return widget.session.playlist.firstWhere((e) => e.itemId == curId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _copyInviteText(BuildContext context) async {
    final session = widget.session;
    final roomCode = session.roomCode;
    final invite = session.inviteText;
    final tc = ThemeColors.of(context);
    final i18n = AppI18n.of(context);

    final textToCopy = (roomCode != null && roomCode.isNotEmpty)
        ? roomCode
        : (invite ?? '');

    if (textToCopy.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: textToCopy));
        if (!context.mounted) return;
        showLiquidGlassSnackBar(
          context,
          owner: this,
          message: roomCode != null
              ? '${i18n.roomCodeCopied}: $roomCode'
              : i18n.inviteCopied,
          icon: Icons.check_circle_outline_rounded,
          iconColor: tc.primary,
          duration: const Duration(seconds: 2),
        );
      } catch (_) {
        if (!context.mounted) return;
        _showFallbackInviteDialog(context, textToCopy);
      }
    }
  }

  void _showFallbackInviteDialog(BuildContext context, String invite) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final controller = TextEditingController(text: invite);
    showDialog(
      context: context,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            margin: const EdgeInsets.all(24),
            child: GlassContainer.card(
              surfaceStyle: GlassSurfaceStyle.solid,
              color: tc.cardBackground,
              shape: const LiquidRoundedSuperellipse(borderRadius: 20),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.share_rounded, size: 20, color: tc.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          i18n.inviteRoomTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: tc.textPrimary,
                          ),
                        ),
                      ),
                      GlassIconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: tc.textSecondary,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GlassTextField(
                    controller: controller,
                    readOnly: true,
                    maxLines: 4,
                    surfaceStyle: GlassSurfaceStyle.solid,
                  ),
                  const SizedBox(height: 14),
                  LiquidGlassActionButton(
                    isPrimary: true,
                    onTap: () {
                      controller.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: controller.text.length,
                      );
                    },
                    child: Text(
                      i18n.selectAllText,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddMediaDialog(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final urlController = TextEditingController();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Material(
          type: MaterialType.transparency,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (dialogCtx, constraints) {
                final isShortWindow = constraints.maxHeight < 360;
                final isNarrow = constraints.maxWidth < 480;
                final horizontalMargin = isNarrow ? 12.0 : 20.0;
                final verticalMargin = isShortWindow ? 8.0 : 20.0;
                final cardPadding = isShortWindow ? 14.0 : 22.0;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalMargin,
                    vertical: verticalMargin,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: (constraints.maxWidth - horizontalMargin * 2)
                          .clamp(0.0, double.infinity),
                      minHeight: (constraints.maxHeight - verticalMargin * 2)
                          .clamp(0.0, double.infinity),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: GlassContainer.card(
                          surfaceStyle: GlassSurfaceStyle.solid,
                          color: tc.cardBackground,
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: isShortWindow ? 16 : 22,
                          ),
                          padding: EdgeInsets.all(cardPadding),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.video_library_rounded,
                                    size: isShortWindow ? 18 : 20,
                                    color: tc.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      i18n.addMedia,
                                      style: TextStyle(
                                        fontSize: isShortWindow ? 16 : 17,
                                        fontWeight: FontWeight.w700,
                                        color: tc.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Semantics(
                                    button: true,
                                    enabled: true,
                                    label: i18n.close,
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: isShortWindow ? 16 : 18,
                                        color: tc.textSecondary,
                                      ),
                                      tooltip: i18n.close,
                                      padding: isShortWindow
                                          ? const EdgeInsets.all(4)
                                          : const EdgeInsets.all(8),
                                      constraints: isShortWindow
                                          ? const BoxConstraints()
                                          : null,
                                      onPressed: () => Navigator.of(ctx).pop(),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isShortWindow ? 10 : 16),

                              // HTTPS URL Input
                              Text(
                                i18n.addVideoUrl,
                                style: TextStyle(
                                  fontSize: isShortWindow ? 12 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: tc.textSecondary,
                                ),
                              ),
                              SizedBox(height: isShortWindow ? 6 : 8),
                              GlassTextField(
                                key: const ValueKey('add-item-url-input'),
                                controller: urlController,
                                placeholder: i18n.urlInputPlaceholder,
                                height: isShortWindow ? 38 : 44,
                                surfaceStyle: GlassSurfaceStyle.solid,
                                color: tc.inputBackground,
                                textStyle: TextStyle(
                                  color: tc.textPrimary,
                                  fontSize: 13,
                                ),
                                placeholderStyle: TextStyle(
                                  color: tc.textTertiary,
                                  fontSize: 12.5,
                                ),
                              ),
                              SizedBox(height: isShortWindow ? 8 : 10),

                              // Optional Title
                              GlassTextField(
                                key: const ValueKey('add-item-title-input'),
                                controller: titleController,
                                placeholder: i18n.mediaTitlePlaceholder,
                                height: isShortWindow ? 38 : 44,
                                surfaceStyle: GlassSurfaceStyle.solid,
                                color: tc.inputBackground,
                                textStyle: TextStyle(
                                  color: tc.textPrimary,
                                  fontSize: 13,
                                ),
                                placeholderStyle: TextStyle(
                                  color: tc.textTertiary,
                                  fontSize: 12.5,
                                ),
                              ),
                              SizedBox(height: isShortWindow ? 10 : 16),

                              Row(
                                children: [
                                  Expanded(
                                    child: LiquidGlassActionButton(
                                      key: const ValueKey('add-item-local-btn'),
                                      height: isShortWindow ? 38 : 42,
                                      onTap: () async {
                                        final messenger =
                                            ScaffoldMessenger.maybeOf(context);
                                        Navigator.of(ctx).pop();
                                        _lastReportedCinemaError = null;
                                        try {
                                          await widget.session
                                              .pickAndAddLocalFile();
                                        } catch (e) {
                                          if (mounted) {
                                            messenger?.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  i18n.filePickerFailed,
                                                ),
                                                duration: const Duration(
                                                  seconds: 2,
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.file_open_rounded,
                                            size: isShortWindow ? 15 : 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              i18n.addLocalFile,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: isShortWindow
                                                    ? 11.5
                                                    : 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LiquidGlassActionButton(
                                      key: const ValueKey(
                                        'add-item-submit-btn',
                                      ),
                                      isPrimary: true,
                                      height: isShortWindow ? 38 : 42,
                                      onTap: () async {
                                        final url = urlController.text.trim();
                                        if (url.isNotEmpty) {
                                          Navigator.of(ctx).pop();
                                          final title = titleController.text
                                              .trim();
                                          _lastReportedCinemaError = null;
                                          await widget.session.addUrl(
                                            url,
                                            title: title.isNotEmpty
                                                ? title
                                                : null,
                                          );
                                        }
                                      },
                                      child: Text(i18n.confirm),
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
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showReplaceMediaDialog(BuildContext context, PlaylistItem item) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final urlController = TextEditingController(text: item.url ?? '');

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                margin: const EdgeInsets.all(20),
                child: GlassContainer.card(
                  surfaceStyle: GlassSurfaceStyle.solid,
                  color: tc.cardBackground,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 22),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 20,
                            color: tc.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${i18n.replaceDialogTitle}: ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: tc.textPrimary,
                              ),
                            ),
                          ),
                          Semantics(
                            button: true,
                            enabled: true,
                            label: i18n.close,
                            child: IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: tc.textSecondary,
                              ),
                              tooltip: i18n.close,
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        i18n.addVideoUrl,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tc.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GlassTextField(
                        key: const ValueKey('replace-item-url-input'),
                        controller: urlController,
                        placeholder: i18n.urlInputPlaceholder,
                        height: 44,
                        surfaceStyle: GlassSurfaceStyle.solid,
                        color: tc.inputBackground,
                        textStyle: TextStyle(
                          color: tc.textPrimary,
                          fontSize: 13,
                        ),
                        placeholderStyle: TextStyle(
                          color: tc.textTertiary,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: LiquidGlassActionButton(
                              height: 42,
                              onTap: () => Navigator.of(ctx).pop(),
                              child: Text(i18n.cancel),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LiquidGlassActionButton(
                              key: const ValueKey('replace-item-submit-btn'),
                              isPrimary: true,
                              height: 42,
                              onTap: () async {
                                final newUrl = urlController.text.trim();
                                if (newUrl.isNotEmpty) {
                                  Navigator.of(ctx).pop();
                                  _lastReportedCinemaError = null;
                                  await widget.session.replaceItem(
                                    item.itemId,
                                    url: newUrl,
                                  );
                                }
                              },
                              child: Text(i18n.confirm),
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
        );
      },
    );
  }

  void _showPlayerToast(String message, [IconData? icon]) {
    setState(() {
      _playerToastMessage = message;
      _playerToastIcon = icon;
    });
    _playerToastTimer?.cancel();
    _playerToastTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && _playerToastMessage == message) {
        setState(() {
          _playerToastMessage = null;
          _playerToastIcon = null;
        });
      }
    });
  }

  void _cycleLoopMode() {
    final cur = widget.session.loopMode;
    final next = switch (cur) {
      PlaybackLoopMode.loopAll => PlaybackLoopMode.loopOne,
      PlaybackLoopMode.loopOne => PlaybackLoopMode.sequential,
      PlaybackLoopMode.sequential => PlaybackLoopMode.loopAll,
    };
    widget.session.setLoopMode(next);
    final i18n = AppI18n.of(context);
    final modeName = switch (next) {
      PlaybackLoopMode.loopAll => i18n.loopModeAll,
      PlaybackLoopMode.loopOne => i18n.loopModeOne,
      PlaybackLoopMode.sequential => i18n.loopModeSeq,
    };
    final icon = next == PlaybackLoopMode.loopOne
        ? Icons.repeat_one_rounded
        : (next == PlaybackLoopMode.sequential
              ? Icons.playlist_play_rounded
              : Icons.repeat_rounded);
    _showPlayerToast(modeName, icon);
  }

  void _showSpeedMenu(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    const rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    final current = widget.session.playback.rate;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            margin: const EdgeInsets.all(16),
            child: GlassContainer.card(
              surfaceStyle: GlassSurfaceStyle.solid,
              color: tc.cardBackground,
              shape: const LiquidRoundedSuperellipse(borderRadius: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed_rounded, size: 20, color: tc.primary),
                      const SizedBox(width: 8),
                      Text(
                        i18n.playbackRate,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tc.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      GlassIconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: tc.textSecondary,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: rates.map((r) {
                      final isSelected = (r - current).abs() < 0.05;
                      return LiquidGlassActionButton(
                        key: ValueKey('speed-option-$r'),
                        isPrimary: isSelected,
                        height: 38,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          widget.session.setRate(r);
                          _restartControlsTimer();
                        },
                        child: Text(
                          '${r}x',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected ? Colors.white : tc.textPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTrackSelectionDialog(BuildContext context) async {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final player = widget.session.player;
    final tracks = player.state.tracks;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final liveTrack = player.state.track;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
              child: Container(
                margin: const EdgeInsets.all(16),
                child: GlassContainer.card(
                  surfaceStyle: GlassSurfaceStyle.solid,
                  color: tc.cardBackground,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 20),
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
                            '${i18n.subtitleTrack} / ${i18n.audioTrack}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tc.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          GlassIconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: tc.textSecondary,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ─── Subtitles Section ───
                              Text(
                                i18n.subtitleTrack,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: tc.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  i18n.noSubtitle,
                                  style: TextStyle(
                                    color: tc.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing:
                                    liveTrack.subtitle == SubtitleTrack.no()
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: tc.primary,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () async {
                                  await player.setSubtitleTrack(
                                    SubtitleTrack.no(),
                                  );
                                  setDialogState(() {});
                                },
                              ),
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  i18n.autoSubtitle,
                                  style: TextStyle(
                                    color: tc.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing:
                                    liveTrack.subtitle == SubtitleTrack.auto()
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: tc.primary,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () async {
                                  await player.setSubtitleTrack(
                                    SubtitleTrack.auto(),
                                  );
                                  setDialogState(() {});
                                },
                              ),
                              for (final st in tracks.subtitle)
                                if (st != SubtitleTrack.no() &&
                                    st != SubtitleTrack.auto())
                                  ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    title: Text(
                                      st.title ??
                                          st.language ??
                                          'Subtitle ${st.id}',
                                      style: TextStyle(
                                        color: tc.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: liveTrack.subtitle == st
                                        ? Icon(
                                            Icons.check_rounded,
                                            color: tc.primary,
                                            size: 18,
                                          )
                                        : null,
                                    onTap: () async {
                                      await player.setSubtitleTrack(st);
                                      setDialogState(() {});
                                    },
                                  ),
                              const SizedBox(height: 6),
                              LiquidGlassActionButton(
                                key: const ValueKey(
                                  'cinema-load-external-sub-btn',
                                ),
                                height: 36,
                                onTap: () async {
                                  try {
                                    final result = await FilePicker.platform
                                        .pickFiles(
                                          type: FileType.custom,
                                          allowedExtensions: [
                                            'srt',
                                            'vtt',
                                            'ass',
                                          ],
                                          withData: true,
                                        );
                                    if (result != null &&
                                        result.files.isNotEmpty) {
                                      final picked = result.files.first;
                                      if (kIsWeb || picked.path == null) {
                                        if (picked.bytes != null) {
                                          final content = utf8.decode(
                                            picked.bytes!,
                                          );
                                          await player.setSubtitleTrack(
                                            SubtitleTrack.data(
                                              content,
                                              title: picked.name,
                                            ),
                                          );
                                        }
                                      } else {
                                        await player.setSubtitleTrack(
                                          SubtitleTrack.uri(
                                            picked.path!,
                                            title: picked.name,
                                          ),
                                        );
                                      }
                                      setDialogState(() {});
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      'External subtitle picker error: $e',
                                    );
                                  }
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.file_upload_outlined,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      i18n.loadExternalSubtitle,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Divider(height: 28),

                              // ─── Audio Tracks Section ───
                              Text(
                                i18n.audioTrack,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: tc.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  i18n.autoSubtitle,
                                  style: TextStyle(
                                    color: tc.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: liveTrack.audio == AudioTrack.auto()
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: tc.primary,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () async {
                                  await player.setAudioTrack(AudioTrack.auto());
                                  setDialogState(() {});
                                },
                              ),
                              for (final at in tracks.audio)
                                if (at != AudioTrack.no() &&
                                    at != AudioTrack.auto())
                                  ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    title: Text(
                                      at.title ??
                                          at.language ??
                                          'Audio Track ${at.id}',
                                      style: TextStyle(
                                        color: tc.textPrimary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: liveTrack.audio == at
                                        ? Icon(
                                            Icons.check_rounded,
                                            color: tc.primary,
                                            size: 18,
                                          )
                                        : null,
                                    onTap: () async {
                                      await player.setAudioTrack(at);
                                      setDialogState(() {});
                                    },
                                  ),
                            ],
                          ),
                        ),
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

  void _showMoreSettingsSheet(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final session = widget.session;
    final isHostOrAdmin =
        session.role == RoomRole.owner || session.role == RoomRole.admin;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final loopMode = session.loopMode;
          final loopTitle = switch (loopMode) {
            PlaybackLoopMode.loopAll => i18n.loopModeAll,
            PlaybackLoopMode.loopOne => i18n.loopModeOne,
            PlaybackLoopMode.sequential => i18n.loopModeSeq,
          };
          final loopIcon = switch (loopMode) {
            PlaybackLoopMode.loopAll => Icons.repeat_rounded,
            PlaybackLoopMode.loopOne => Icons.repeat_one_rounded,
            PlaybackLoopMode.sequential => Icons.playlist_play_rounded,
          };

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                margin: const EdgeInsets.all(16),
                child: GlassContainer.card(
                  surfaceStyle: GlassSurfaceStyle.solid,
                  color: tc.cardBackground,
                  shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 20, color: tc.primary),
                          const SizedBox(width: 8),
                          Text(
                            i18n.moreSettings,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: tc.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          GlassIconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: tc.textSecondary,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 1. Danmaku Toggle
                      ListTile(
                        key: const ValueKey('cinema-danmaku-btn'),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: Icon(
                          _danmakuEnabled
                              ? Icons.subtitles_rounded
                              : Icons.subtitles_off_rounded,
                          color: _danmakuEnabled
                              ? tc.primary
                              : tc.textSecondary,
                          size: 20,
                        ),
                        title: Text(
                          i18n.danmakuToggle,
                          style: TextStyle(
                            color: tc.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Switch.adaptive(
                          value: _danmakuEnabled,
                          activeColor: tc.primary,
                          onChanged: (val) {
                            setState(() => _danmakuEnabled = val);
                            setSheetState(() {});
                            _showPlayerToast(
                              val ? i18n.danmakuEnabled : i18n.danmakuDisabled,
                              val
                                  ? Icons.subtitles_rounded
                                  : Icons.subtitles_off_rounded,
                            );
                          },
                        ),
                        onTap: () {
                          final nextVal = !_danmakuEnabled;
                          setState(() => _danmakuEnabled = nextVal);
                          setSheetState(() {});
                          _showPlayerToast(
                            nextVal
                                ? i18n.danmakuEnabled
                                : i18n.danmakuDisabled,
                            nextVal
                                ? Icons.subtitles_rounded
                                : Icons.subtitles_off_rounded,
                          );
                        },
                      ),

                      // 2. Loop Mode
                      ListTile(
                        key: const ValueKey('cinema-loop-mode-btn'),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: Icon(loopIcon, color: tc.primary, size: 20),
                        title: Text(
                          loopTitle,
                          style: TextStyle(
                            color: tc.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: tc.textTertiary,
                          size: 20,
                        ),
                        onTap: () {
                          _cycleLoopMode();
                          setSheetState(() {});
                        },
                      ),

                      // 3. Subtitles & Audio Tracks
                      ListTile(
                        key: const ValueKey('cinema-tracks-btn'),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: Icon(
                          Icons.closed_caption_rounded,
                          color: tc.primary,
                          size: 20,
                        ),
                        title: Text(
                          '${i18n.subtitleTrack} / ${i18n.audioTrack}',
                          style: TextStyle(
                            color: tc.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: tc.textTertiary,
                          size: 20,
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showTrackSelectionDialog(context);
                        },
                      ),

                      // 4. Aspect Ratio
                      ListTile(
                        key: const ValueKey('cinema-aspect-ratio-btn'),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: Icon(
                          Icons.aspect_ratio_rounded,
                          color: tc.primary,
                          size: 20,
                        ),
                        title: Text(
                          '${i18n.aspectRatio}: ${_aspectFit == BoxFit.contain ? i18n.aspectFitContain : (_aspectFit == BoxFit.cover ? i18n.aspectFitCover : i18n.aspectFitFill)}',
                          style: TextStyle(
                            color: tc.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          Icons.swap_horiz_rounded,
                          color: tc.textTertiary,
                          size: 20,
                        ),
                        onTap: () {
                          _cycleAspectRatio();
                          setSheetState(() {});
                        },
                      ),

                      // 5. Wait for Peer Buffering Toggle (Host mode: BUG-PLAY-06)
                      if (isHostOrAdmin) ...[
                        ListTile(
                          key: const ValueKey(
                            'cinema-wait-buffering-toggle-btn',
                          ),
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: Icon(
                            Icons.hourglass_top_rounded,
                            color: tc.primary,
                            size: 20,
                          ),
                          title: Text(
                            i18n.waitForPeerBuffering,
                            style: TextStyle(
                              color: tc.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            i18n.waitForPeerBufferingDesc,
                            style: TextStyle(
                              color: tc.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          trailing: IgnorePointer(
                            child: Switch.adaptive(
                              value: session.waitForPeerBuffering,
                              activeColor: tc.primary,
                              onChanged: (_) {},
                            ),
                          ),
                          onTap: () {
                            session.waitForPeerBuffering =
                                !session.waitForPeerBuffering;
                            setSheetState(() {});
                          },
                        ),
                      ],

                      // 6. Volume Mute Toggle (BUG-UI-01: wrapped in IgnorePointer to avoid double-toggle)
                      ListTile(
                        key: const ValueKey('cinema-volume-mute-btn'),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: Icon(
                          _isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: _isMuted ? tc.warning : tc.primary,
                          size: 20,
                        ),
                        title: Text(
                          _isMuted ? i18n.unmuteTooltip : i18n.muteTooltip,
                          style: TextStyle(
                            color: tc.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IgnorePointer(
                          child: Switch.adaptive(
                            value: !_isMuted,
                            activeColor: tc.primary,
                            onChanged: (_) {},
                          ),
                        ),
                        onTap: () {
                          setState(() => _isMuted = !_isMuted);
                          setSheetState(() {});
                          session.player.setVolume(
                            _isMuted ? 0.0 : _volume * 100.0,
                          );
                        },
                      ),

                      if (!isHostOrAdmin) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            i18n.readOnlyControlTooltip,
                            style: TextStyle(
                              color: tc.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final isHostOrAdmin =
        widget.session.role == RoomRole.owner ||
        widget.session.role == RoomRole.admin;
    final isPlaying = widget.session.playback.mode == PlaybackMode.playing;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (isHostOrAdmin) {
        if (isPlaying) {
          widget.session.pause();
        } else {
          widget.session.play();
        }
        _restartControlsTimer();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (isHostOrAdmin) {
        _seekRelative(-10);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (isHostOrAdmin) {
        _seekRelative(10);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _volume = (_volume + 0.1).clamp(0.0, 1.0);
        if (_isMuted && _volume > 0) _isMuted = false;
      });
      widget.session.player.setVolume(_volume * 100.0);
      _showGestureHud('volume');
      _restartControlsTimer();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _volume = (_volume - 0.1).clamp(0.0, 1.0);
      });
      widget.session.player.setVolume(_volume * 100.0);
      _showGestureHud('volume');
      _restartControlsTimer();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _setFullscreen(!_isFullscreen);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
      setState(() => _isMuted = !_isMuted);
      widget.session.player.setVolume(_isMuted ? 0.0 : _volume * 100.0);
      _restartControlsTimer();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
      setState(() => _danmakuEnabled = !_danmakuEnabled);
      final i18n = AppI18n.of(context);
      _showPlayerToast(
        _danmakuEnabled ? i18n.danmakuEnabled : i18n.danmakuDisabled,
        _danmakuEnabled ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
      );
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.bracketLeft) {
      if (isHostOrAdmin) {
        final cur = widget.session.playback.rate;
        widget.session.setRate((cur - 0.25).clamp(0.5, 3.0));
        _restartControlsTimer();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.bracketRight) {
      if (isHostOrAdmin) {
        final cur = widget.session.playback.rate;
        widget.session.setRate((cur + 0.25).clamp(0.5, 3.0));
        _restartControlsTimer();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _submitChatMessage() {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) return;
    widget.session.sendChatMessage(text);
    _chatInputController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      }
    });
  }

  void _handleStartCall(CallType type) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    // 1. Prefer online members other than self
    var targetList = widget.session.members
        .where(
          (m) => m.deviceId != widget.session.identity.deviceId && m.online,
        )
        .toList();

    // 2. Fallback to any room member other than self (in case online flag is lagging)
    if (targetList.isEmpty) {
      targetList = widget.session.members
          .where((m) => m.deviceId != widget.session.identity.deviceId)
          .toList();
    }

    if (targetList.isEmpty) {
      showLiquidGlassSnackBar(
        context,
        owner: this,
        message: i18n.callBusy,
        icon: Icons.info_outline_rounded,
        iconColor: tc.warning,
      );
      return;
    }

    final peer = targetList.first;
    widget.session.callSession.startCall(
      type,
      targetId: peer.deviceId,
      targetName: peer.displayName,
      targetAvatar: peer.avatar,
    );
  }

  Widget _buildChatTab(BuildContext context, {bool isShort = false}) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final messages = widget.session.chatMessages;

    return Column(
      children: [
        // Message Stream
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: isShort ? 28 : 36,
                        color: tc.textTertiary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          i18n.chatEmptyNotice,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isShort ? 11 : 12,
                            color: tc.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('cinema-chat-list-view'),
                  controller: _chatScrollController,
                  padding: EdgeInsets.symmetric(
                    vertical: isShort ? 4 : 8,
                    horizontal: 4,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _buildChatMessageItem(
                      context,
                      msg,
                      isShort: isShort,
                    );
                  },
                ),
        ),

        const SizedBox(height: 6),

        // Chat & Danmaku Inset Input Well
        Container(
          height: isShort ? 36 : 42,
          padding: EdgeInsets.symmetric(horizontal: isShort ? 8 : 12),
          decoration: BoxDecoration(
            color: tc.inputBackground,
            borderRadius: BorderRadius.circular(isShort ? 18 : 21),
            border: Border.all(color: tc.glassBorderSubtle),
          ),
          child: Row(
            children: [
              Icon(
                Icons.subtitles_rounded,
                size: isShort ? 14 : 16,
                color: tc.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('cinema-chat-input-field'),
                  controller: _chatInputController,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(
                    fontSize: isShort ? 12 : 13,
                    color: tc.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: i18n.sendChatHint,
                    hintStyle: TextStyle(
                      fontSize: isShort ? 12 : 13,
                      color: tc.textTertiary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _submitChatMessage(),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                button: true,
                label: i18n.send,
                child: GestureDetector(
                  key: const ValueKey('cinema-chat-send-btn'),
                  onTap: _submitChatMessage,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isShort ? 10 : 12,
                      vertical: isShort ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: tc.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.send_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        if (!isShort) ...[
                          const SizedBox(width: 4),
                          Text(
                            i18n.send,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatMessageItem(
    BuildContext context,
    ChatMessage msg, {
    bool isShort = false,
  }) {
    final tc = ThemeColors.of(context);
    final isSelf = msg.isSelf;

    if (msg.type == ChatMessageType.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: tc.inputBackground.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              fontSize: isShort ? 10 : 11,
              color: tc.textTertiary,
            ),
          ),
        ),
      );
    }

    final timeStr =
        '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isSelf
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSelf) ...[
            _buildChatAvatar(
              msg.senderName,
              msg.senderAvatar,
              size: isShort ? 24 : 28,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isSelf
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isSelf)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 2),
                    child: Text(
                      msg.senderName,
                      style: TextStyle(
                        fontSize: isShort ? 10 : 10.5,
                        fontWeight: FontWeight.w600,
                        color: tc.textSecondary,
                      ),
                    ),
                  ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isShort ? 10 : 12,
                    vertical: isShort ? 6 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelf ? tc.primary : tc.inputBackground,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(isSelf ? 14 : 2),
                      bottomRight: Radius.circular(isSelf ? 2 : 14),
                    ),
                    border: isSelf
                        ? null
                        : Border.all(color: tc.glassBorderSubtle),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: isShort ? 12 : 13,
                      color: isSelf ? Colors.white : tc.textPrimary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                  child: Text(
                    timeStr,
                    style: TextStyle(fontSize: 9, color: tc.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          if (isSelf) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildChatAvatar(String name, String? avatar, {double size = 28}) {
    final initials = name.isNotEmpty
        ? name.characters.first.toUpperCase()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildCallOverlay(
    BuildContext context, {
    bool isFullscreen = false,
    bool isShort = false,
  }) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final callSession = widget.session.callSession;

    if (callSession.state == CallState.idle) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.sizeOf(context);
    final callTopPadding = isFullscreen
        ? 16.0
        : (MediaQuery.paddingOf(context).top + 58.0);

    if (callSession.state == CallState.incoming) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: callTopPadding,
            left: 16,
            right: 16,
            child: GlassContainer.card(
              key: const ValueKey('cinema-call-incoming-card'),
              surfaceStyle: GlassSurfaceStyle.glass,
              color: Colors.black87,
              shape: const LiquidRoundedSuperellipse(borderRadius: 18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tc.primary.withValues(alpha: 0.25),
                    ),
                    child: Icon(
                      callSession.type == CallType.video
                          ? Icons.videocam_rounded
                          : Icons.phone_in_talk_rounded,
                      color: tc.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          callSession.peerName ?? 'Friend',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          callSession.type == CallType.video
                              ? i18n.callIncomingVideo
                              : i18n.callIncomingVoice,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Decline Button
                  Semantics(
                    button: true,
                    label: i18n.callDecline,
                    child: GestureDetector(
                      key: const ValueKey('cinema-call-decline-btn'),
                      onTap: () => callSession.declineCall(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Accept Button
                  Semantics(
                    button: true,
                    label: i18n.callAccept,
                    child: GestureDetector(
                      key: const ValueKey('cinema-call-accept-btn'),
                      onTap: () => callSession.acceptCall(),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          callSession.type == CallType.video
                              ? Icons.videocam_rounded
                              : Icons.call_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (callSession.state == CallState.outgoing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: callTopPadding,
            right: 16,
            child: GlassContainer.card(
              key: const ValueKey('cinema-call-outgoing-card'),
              surfaceStyle: GlassSurfaceStyle.glass,
              color: Colors.black87,
              shape: const LiquidRoundedSuperellipse(borderRadius: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${i18n.callConnecting} ${callSession.peerName ?? ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    label: i18n.callEnd,
                    child: GestureDetector(
                      key: const ValueKey('cinema-call-hangup-btn'),
                      onTap: () => callSession.hangupCall(),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Connected Call
    final pipW = isShort ? 110.0 : 130.0;
    final pipH = isShort ? 145.0 : 170.0;
    const minDx = 10.0;
    final minDy = isFullscreen
        ? 10.0
        : (MediaQuery.paddingOf(context).top + 54.0);
    final maxDx = (size.width - pipW - 10.0).clamp(minDx, 4000.0);
    final maxDy = (size.height - pipH - 10.0).clamp(minDy, 4000.0);
    final effectivePipDx = _pipOffset.dx.clamp(minDx, maxDx);
    final effectivePipDy = _pipOffset.dy.clamp(minDy, maxDy);
    // Normalize _pipOffset so internal coordinates match visible clamped boundaries
    _pipOffset = Offset(effectivePipDx, effectivePipDy);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video PIP window if in video call and not minimized
        if (callSession.type == CallType.video && !callSession.isPipMinimized)
          Positioned(
            left: _pipOffset.dx,
            top: _pipOffset.dy,
            child: GestureDetector(
              onDoubleTap: () {
                setState(() {
                  _pipOffset = Offset(16.0, minDy);
                });
              },
              onPanStart: (_) {
                _pipOffset = Offset(
                  _pipOffset.dx.clamp(minDx, maxDx),
                  _pipOffset.dy.clamp(minDy, maxDy),
                );
              },
              onPanUpdate: (d) {
                setState(() {
                  _pipOffset = Offset(
                    (_pipOffset.dx + d.delta.dx).clamp(minDx, maxDx),
                    (_pipOffset.dy + d.delta.dy).clamp(minDy, maxDy),
                  );
                });
              },
              child: Container(
                key: const ValueKey('cinema-video-pip-window'),
                width: isShort ? 110 : 130,
                height: isShort ? 145 : 170,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Remote Video View
                      callSession.isPeerCameraOff
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.videocam_off_rounded,
                                    color: Colors.white38,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    callSession.peerName ?? 'Friend',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RTCVideoView(
                              callSession.remoteRenderer,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            ),

                      // Bottom Peer Name Pill
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            callSession.peerName ?? 'Friend',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      // Local Video Inset (Bottom-right)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          width: isShort ? 32 : 38,
                          height: isShort ? 42 : 50,
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white38, width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: callSession.isCameraOff
                                ? const Center(
                                    child: Icon(
                                      Icons.videocam_off_rounded,
                                      color: Colors.white38,
                                      size: 14,
                                    ),
                                  )
                                : RTCVideoView(
                                    callSession.localRenderer,
                                    mirror: true,
                                    objectFit: RTCVideoViewObjectFit
                                        .RTCVideoViewObjectFitCover,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Floating Call Controls Bar
        Positioned(
          top: callTopPadding,
          right: 16,
          child: GlassContainer.card(
            key: const ValueKey('cinema-call-connected-bar'),
            surfaceStyle: GlassSurfaceStyle.glass,
            color: Colors.black87,
            shape: const LiquidRoundedSuperellipse(borderRadius: 18),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timer & Green pulse dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  formatDuration(callSession.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),

                // Mic Toggle
                GestureDetector(
                  key: const ValueKey('cinema-call-mic-btn'),
                  onTap: () => callSession.toggleMic(),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: callSession.isMicMuted
                          ? Colors.redAccent.withValues(alpha: 0.3)
                          : Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      callSession.isMicMuted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      color: callSession.isMicMuted
                          ? Colors.redAccent
                          : Colors.white,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Speaker Toggle
                GestureDetector(
                  key: const ValueKey('cinema-call-speaker-btn'),
                  onTap: () => callSession.toggleSpeaker(),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      callSession.isSpeakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Video-specific controls
                if (callSession.type == CallType.video) ...[
                  // Camera Toggle
                  GestureDetector(
                    key: const ValueKey('cinema-call-camera-btn'),
                    onTap: () => callSession.toggleCamera(),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: callSession.isCameraOff
                            ? Colors.redAccent.withValues(alpha: 0.3)
                            : Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        callSession.isCameraOff
                            ? Icons.videocam_off_rounded
                            : Icons.videocam_rounded,
                        color: callSession.isCameraOff
                            ? Colors.redAccent
                            : Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Switch Camera
                  GestureDetector(
                    key: const ValueKey('cinema-call-flip-btn'),
                    onTap: () => callSession.switchCamera(),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.flip_camera_ios_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // PIP Minimize/Maximize
                  GestureDetector(
                    key: const ValueKey('cinema-call-pip-toggle-btn'),
                    onTap: () => setState(
                      () => callSession.isPipMinimized =
                          !callSession.isPipMinimized,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white12,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        callSession.isPipMinimized
                            ? Icons.open_in_full_rounded
                            : Icons.close_fullscreen_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Hangup Button
                Semantics(
                  button: true,
                  label: i18n.callEnd,
                  child: GestureDetector(
                    key: const ValueKey('cinema-call-hangup-btn'),
                    onTap: () => callSession.hangupCall(),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.session, AppSettings.instance]),
        builder: (context, _) {
          final i18n = AppI18n.of(context);
          final tc = ThemeColors.of(context);
          final mediaQuery = MediaQuery.of(context);
          final screenWidth = mediaQuery.size.width;
          final screenHeight = mediaQuery.size.height;
          final isMobile = screenWidth < 768;
          final isNarrow = screenWidth < 560;
          final isShort =
              screenHeight < 680 ||
              (screenWidth >= screenHeight && screenHeight < 750);
          final session = widget.session;
          final role = session.role;
          final isHostOrAdmin =
              role == RoomRole.owner || role == RoomRole.admin;
          final isOwner = role == RoomRole.owner;
          final isPlaying = session.playback.mode == PlaybackMode.playing;
          final currentMedia = _currentPlaylistItem;

          // Calculate progress duration using strictly real player position (avoids masking decoder freezes)
          final playerDuration = session.player.state.duration;
          final mediaDuration = (playerDuration > Duration.zero)
              ? playerDuration
              : (currentMedia?.duration ?? playerDuration);
          final playerPos = session.player.state.position;
          // Truthful UI projection: real progress is strictly playerPos; never disguise a frozen player
          final currentPos = playerPos;
          final syncTargetPos = session.playback.position;
          final isBuffering = session.player.state.buffering;

          final double progressRatio = mediaDuration.inMilliseconds > 0
              ? (currentPos.inMilliseconds / mediaDuration.inMilliseconds)
                    .clamp(0.0, 1.0)
              : 0.0;
          final double syncTargetRatio = mediaDuration.inMilliseconds > 0
              ? (syncTargetPos.inMilliseconds / mediaDuration.inMilliseconds)
                    .clamp(0.0, 1.0)
              : 0.0;

          if (_isFullscreen) {
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                _setFullscreen(false);
              },
              child: Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildPlayerStage(
                      context,
                      isMobile: isMobile,
                      isShort: true,
                      isPlaying: isPlaying,
                      isHostOrAdmin: isHostOrAdmin,
                      progressRatio: progressRatio,
                      currentPos: currentPos,
                      mediaDuration: mediaDuration,
                      currentMedia: currentMedia,
                      syncTargetPos: syncTargetPos,
                      syncTargetRatio: syncTargetRatio,
                      isBuffering: isBuffering,
                      isFullscreen: true,
                    ),
                    if (session.callSession.state != CallState.idle)
                      _buildCallOverlay(
                        context,
                        isFullscreen: true,
                        isShort: isShort,
                      ),
                  ],
                ),
              ),
            );
          }

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              _confirmAndLeaveRoom(context);
            },
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GlassScaffold(
                    resizeToAvoidBottomInset: false,
                    background: LiquidGlassAmbientBackground(
                      child: Container(),
                    ),
                    extendBody: false,
                    appBar: GlassAppBar(
                      centerTitle: false,
                      backgroundColor: Colors.transparent,
                      leading: Semantics(
                        button: true,
                        enabled: true,
                        label: isOwner ? i18n.disbandRoom : i18n.leaveRoom,
                        child: Tooltip(
                          message: isOwner ? i18n.disbandRoom : i18n.leaveRoom,
                          child: GlassIconButton(
                            key: const ValueKey('cinema-back-leave-btn'),
                            size: isMobile ? 36 : 40,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 15,
                            ),
                            onPressed: () => _confirmAndLeaveRoom(context),
                          ),
                        ),
                      ),
                      title: isMobile
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _copyInviteText(context),
                              child: Tooltip(
                                message: session.roomCode != null
                                    ? '${i18n.copyRoomCode}: ${session.roomCode}'
                                    : (session.roomId != null
                                          ? formatDeviceId(session.roomId!)
                                          : 'Eir'),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Line 1: Room Code + Role Tag
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          session.roomCode != null
                                              ? '# ${session.roomCode}'
                                              : (session.roomId != null
                                                    ? formatDeviceId(
                                                        session.roomId!,
                                                      )
                                                    : 'Eir'),
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                            color: tc.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        LiquidGlassTag(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1.5,
                                          ),
                                          color: isOwner
                                              ? tc.warning.withValues(
                                                  alpha: 0.18,
                                                )
                                              : (isHostOrAdmin
                                                    ? tc.primary.withValues(
                                                        alpha: 0.16,
                                                      )
                                                    : tc.inputBackground),
                                          child: Text(
                                            isOwner
                                                ? i18n.roleOwner
                                                : (isHostOrAdmin
                                                      ? i18n.roleAdmin
                                                      : i18n.roleMember),
                                            style: TextStyle(
                                              fontSize: 9.0,
                                              fontWeight: FontWeight.w700,
                                              color: isOwner
                                                  ? tc.warning
                                                  : (isHostOrAdmin
                                                        ? tc.primary
                                                        : tc.textSecondary),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 1.5),

                                    // Line 2: Status Dot + Connection Mode + Copy Hint
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _getConnectionDotColor(
                                              session.connectionState,
                                              tc,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _getConnectionLabel(session, i18n),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: _getConnectionDotColor(
                                              session.connectionState,
                                              tc,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          ' · ${i18n.copyRoomCode}',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                            color: tc.textSecondary.withValues(
                                              alpha: 0.75,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Desktop / Tablet layout
                                Tooltip(
                                  message: session.roomCode != null
                                      ? '${i18n.copyRoomCode}: ${session.roomCode}'
                                      : (session.roomId != null
                                            ? formatDeviceId(session.roomId!)
                                            : 'Eir'),
                                  child: GestureDetector(
                                    onTap: () => _copyInviteText(context),
                                    child: LiquidGlassTag(
                                      color: tc.primary.withValues(alpha: 0.16),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            session.roomCode != null
                                                ? Icons.tag_rounded
                                                : Icons.theater_comedy_rounded,
                                            size: 14,
                                            color: tc.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            session.roomCode ??
                                                (session.roomId != null
                                                    ? formatDeviceId(
                                                        session.roomId!,
                                                      )
                                                    : 'Eir'),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing:
                                                  session.roomCode != null
                                                  ? 1.0
                                                  : 0.5,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                              color: tc.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                LiquidGlassTag(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  color: isOwner
                                      ? tc.warning.withValues(alpha: 0.18)
                                      : (isHostOrAdmin
                                            ? tc.primary.withValues(alpha: 0.16)
                                            : tc.inputBackground),
                                  child: Text(
                                    isOwner
                                        ? i18n.roleOwner
                                        : (isHostOrAdmin
                                              ? i18n.roleAdmin
                                              : i18n.roleMember),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: isOwner
                                          ? tc.warning
                                          : (isHostOrAdmin
                                                ? tc.primary
                                                : tc.textSecondary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildConnectionIndicator(
                                  context,
                                  session.connectionState,
                                  isNarrow: false,
                                ),
                              ],
                            ),
                      actions: [
                        // Owner Disband Room Button (Desktop / Tablet only)
                        if (isOwner && !isMobile) ...[
                          Tooltip(
                            message: i18n.disbandRoom,
                            child: Semantics(
                              button: true,
                              label: i18n.disbandRoom,
                              child: LiquidGlassActionButton(
                                height: isShort ? 30 : 34,
                                onTap: () async {
                                  await session.closeRoom();
                                  widget.onLeaveRoom();
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.power_settings_new_rounded,
                                      size: 14,
                                      color: tc.error,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      i18n.disbandRoom,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: tc.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],

                        // Copy Invite Action Button (32x32 Glass button)
                        Semantics(
                          button: true,
                          enabled: true,
                          label: i18n.copyInvite,
                          child: Tooltip(
                            message: i18n.copyInvite,
                            child: GlassIconButton(
                              key: const ValueKey('cinema-copy-invite-btn'),
                              size: 32,
                              icon: Icon(
                                Icons.share_rounded,
                                size: 15,
                                color: tc.textPrimary,
                              ),
                              onPressed: () => _copyInviteText(context),
                            ),
                          ),
                        ),

                        // Call Pill (Grouped Voice & Video Call buttons)
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: tc.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: tc.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                button: true,
                                enabled: true,
                                label: i18n.callVoice,
                                child: Tooltip(
                                  message: i18n.callVoice,
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'cinema-voice-call-btn',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        _handleStartCall(CallType.voice),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Center(
                                        child: Icon(
                                          Icons.phone_rounded,
                                          size: 14,
                                          color: tc.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 14,
                                color: tc.textSecondary.withValues(alpha: 0.25),
                              ),
                              Semantics(
                                button: true,
                                enabled: true,
                                label: i18n.callVideo,
                                child: Tooltip(
                                  message: i18n.callVideo,
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'cinema-video-call-btn',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        _handleStartCall(CallType.video),
                                    child: SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Center(
                                        child: Icon(
                                          Icons.videocam_rounded,
                                          size: 15,
                                          color: tc.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Settings Dialog Trigger
                        Semantics(
                          button: true,
                          enabled: true,
                          label: i18n.settingsTitle,
                          child: Tooltip(
                            message: i18n.settingsTitle,
                            child: GlassIconButton(
                              key: const ValueKey('cinema-settings-btn'),
                              size: 32,
                              icon: Icon(
                                Icons.settings_outlined,
                                size: 15,
                                color: tc.textPrimary,
                              ),
                              onPressed: () => SettingsDialog.show(
                                context,
                                session: session,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: isNarrow ? 2 : 6),
                      ],
                    ),
                    body: SafeArea(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 8 : (isMobile ? 12 : 20),
                          vertical: isShort ? 8 : (isMobile ? 12 : 20),
                        ),
                        child: isShort
                            ? SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // State Banners
                                    if (session.connectionState ==
                                        RoomConnectionState.reconnecting)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _buildReconnectingBanner(
                                          context,
                                        ),
                                      ),
                                    if (session.connectionState ==
                                        RoomConnectionState.disconnected)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: _buildDisconnectedBanner(
                                          context,
                                        ),
                                      ),

                                    // Main Video Player & Control Stage (Preserves proportions and guarantees controls never get squished)
                                    SizedBox(
                                      height: (screenWidth * 9 / 16).clamp(
                                        165.0,
                                        220.0,
                                      ),
                                      child: _buildPlayerStage(
                                        context,
                                        isMobile: isMobile,
                                        isShort: isShort,
                                        isPlaying: isPlaying,
                                        isHostOrAdmin: isHostOrAdmin,
                                        progressRatio: progressRatio,
                                        currentPos: currentPos,
                                        mediaDuration: mediaDuration,
                                        currentMedia: currentMedia,
                                        syncTargetPos: syncTargetPos,
                                        syncTargetRatio: syncTargetRatio,
                                        isBuffering: isBuffering,
                                      ),
                                    ),

                                    const SizedBox(height: 8),

                                    // Bottom Dock (Tabs: Chat / Playlist / Peers / Info)
                                    SizedBox(
                                      height: 250,
                                      child: _buildInspectorDock(
                                        context,
                                        isMobile: isMobile,
                                        isShort: isShort,
                                        isOwner: isOwner,
                                        isHostOrAdmin: isHostOrAdmin,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  // State Banners
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    child:
                                        session.connectionState ==
                                            RoomConnectionState.reconnecting
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: _buildReconnectingBanner(
                                              context,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),

                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    child:
                                        session.connectionState ==
                                            RoomConnectionState.disconnected
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: _buildDisconnectedBanner(
                                              context,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),

                                  // Main Video Player & Control Stage (16:9 standard video aspect ratio, comfortably bounded)
                                  SizedBox(
                                    height: (screenWidth * 9 / 16).clamp(
                                      160.0,
                                      (screenHeight * 0.38).clamp(180.0, 320.0),
                                    ),
                                    child: _buildPlayerStage(
                                      context,
                                      isMobile: isMobile,
                                      isShort: false,
                                      isPlaying: isPlaying,
                                      isHostOrAdmin: isHostOrAdmin,
                                      progressRatio: progressRatio,
                                      currentPos: currentPos,
                                      mediaDuration: mediaDuration,
                                      currentMedia: currentMedia,
                                      syncTargetPos: syncTargetPos,
                                      syncTargetRatio: syncTargetRatio,
                                      isBuffering: isBuffering,
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  // Bottom Dock (Tabs: Chat / Playlist / Peers / Info)
                                  Expanded(
                                    child: _buildInspectorDock(
                                      context,
                                      isMobile: isMobile,
                                      isShort: false,
                                      isOwner: isOwner,
                                      isHostOrAdmin: isHostOrAdmin,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  if (session.callSession.state != CallState.idle)
                    _buildCallOverlay(
                      context,
                      isFullscreen: false,
                      isShort: isShort,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getConnectionDotColor(RoomConnectionState state, ThemeColors tc) {
    switch (state) {
      case RoomConnectionState.connected:
        if (widget.session.isP2pConnected) {
          return tc.success;
        } else if (widget.session.isP2pConnecting) {
          return tc.primary;
        } else if (widget.session.isP2pFailed) {
          return tc.warning;
        } else {
          return tc.primary;
        }
      case RoomConnectionState.connecting:
        return tc.primary;
      case RoomConnectionState.reconnecting:
        return tc.warning;
      case RoomConnectionState.disconnected:
        return tc.error;
    }
  }

  String _getConnectionLabel(RoomSession session, AppI18n i18n) {
    switch (session.connectionState) {
      case RoomConnectionState.connected:
        if (session.isP2pConnected) {
          return 'P2P';
        } else if (session.isP2pConnecting) {
          return i18n.p2pConnecting;
        } else if (session.isP2pFailed) {
          return i18n.p2pFailedPill;
        } else {
          return i18n.connectionServer;
        }
      case RoomConnectionState.connecting:
        return i18n.stateConnecting;
      case RoomConnectionState.reconnecting:
        return i18n.stateReconnecting;
      case RoomConnectionState.disconnected:
        return i18n.stateDisconnected;
    }
  }

  Widget _buildConnectionIndicator(
    BuildContext context,
    RoomConnectionState state, {
    bool isNarrow = false,
  }) {
    final tc = ThemeColors.of(context);
    final i18n = AppI18n.of(context);

    final dotColor = _getConnectionDotColor(state, tc);
    final label = _getConnectionLabel(widget.session, i18n);
    String tooltip;

    switch (state) {
      case RoomConnectionState.connected:
        if (widget.session.isP2pConnected) {
          tooltip = i18n.connectionP2pTooltip;
        } else if (widget.session.isP2pConnecting) {
          tooltip = i18n.p2pConnectingTooltip;
        } else if (widget.session.isP2pFailed) {
          tooltip = i18n.p2pFailedTooltip;
        } else {
          tooltip = i18n.connectionServerTooltip;
        }
        break;
      case RoomConnectionState.connecting:
        tooltip = i18n.stateConnecting;
        break;
      case RoomConnectionState.reconnecting:
        tooltip = i18n.stateReconnecting;
        break;
      case RoomConnectionState.disconnected:
        tooltip = i18n.stateDisconnected;
        break;
    }

    final tag = Tooltip(
      message: tooltip,
      child: LiquidGlassTag(
        color: dotColor.withValues(alpha: 0.14),
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 6 : 8,
          vertical: 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: isNarrow ? 9.5 : 10.5,
                fontWeight: FontWeight.w700,
                color: dotColor,
              ),
            ),
          ],
        ),
      ),
    );

    if (state == RoomConnectionState.disconnected) {
      return Semantics(
        button: true,
        enabled: true,
        label: '$label: ${i18n.retryConnection}',
        child: Tooltip(
          message: i18n.retryConnection,
          child: GestureDetector(
            onTap: () async {
              _lastReportedCinemaError = null;
              await widget.session.retry();
            },
            child: tag,
          ),
        ),
      );
    }
    return Tooltip(
      message: label,
      child: Semantics(label: label, child: tag),
    );
  }

  Widget _buildDisconnectedBanner(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.error.withValues(alpha: 0.12),
      shape: const LiquidRoundedSuperellipse(borderRadius: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: tc.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              i18n.disconnectedBannerText,
              style: TextStyle(
                fontSize: 12.5,
                color: tc.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            enabled: true,
            label: i18n.retryConnection,
            child: Tooltip(
              message: i18n.retryConnection,
              child: LiquidGlassActionButton(
                key: const ValueKey('cinema-retry-connection-btn'),
                height: 28,
                onTap: () async {
                  _lastReportedCinemaError = null;
                  await widget.session.retry();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 14, color: tc.primary),
                    const SizedBox(width: 4),
                    Text(
                      i18n.retryConnection,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tc.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconnectingBanner(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.warning.withValues(alpha: 0.12),
      shape: const LiquidRoundedSuperellipse(borderRadius: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: tc.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              i18n.stateReconnecting,
              style: TextStyle(
                fontSize: 12.5,
                color: tc.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerStage(
    BuildContext context, {
    required bool isMobile,
    bool isShort = false,
    bool isFullscreen = false,
    required bool isPlaying,
    required bool isHostOrAdmin,
    required double progressRatio,
    required Duration currentPos,
    required Duration mediaDuration,
    required PlaylistItem? currentMedia,
    required Duration syncTargetPos,
    required double syncTargetRatio,
    required bool isBuffering,
  }) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final effectiveRatio =
        _draggingSliderValue ?? _optimisticSeekRatio ?? progressRatio;
    final displayPos =
        (effectiveRatio != progressRatio && mediaDuration.inMilliseconds > 0)
        ? Duration(
            milliseconds: (effectiveRatio * mediaDuration.inMilliseconds)
                .round(),
          )
        : currentPos;
    final displayRatio = effectiveRatio.clamp(0.0, 1.0);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: Colors.black,
      shape: LiquidRoundedSuperellipse(
        borderRadius: isFullscreen ? 0 : (isShort ? 16 : 22),
      ),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          isFullscreen ? 0 : (isShort ? 16 : 22),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Real Video Surface
            Center(
              child: Video(
                controller: _videoController,
                fit: _aspectFit,
                controls: NoVideoControls,
              ),
            ),

            // Danmaku Overlay Layer
            if (_danmakuEnabled)
              Positioned.fill(
                child: IgnorePointer(
                  child: DanmakuOverlay(
                    danmakuStream: widget.session.danmakuStream,
                    enabled: _danmakuEnabled,
                  ),
                ),
              ),

            // Simulated Brightness Dimmer Overlay
            if (_brightness < 1.0)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: (1.0 - _brightness) * 0.75,
                  ),
                ),
              ),

            // 2. Gesture Detection Layer (Double-tap skip, Drag brightness/volume, Horizontal drag seek, Long-press 2.0x, with BUG-UI-03 axis lock)
            Positioned.fill(
              child: Row(
                children: [
                  // Left half: Double-tap rewind 10s, vertical drag brightness, horizontal drag seek, long-press 2.0x
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTap: isHostOrAdmin
                          ? () => _seekRelative(-10)
                          : null,
                      onLongPressStart: isHostOrAdmin
                          ? (_) {
                              _preSpeedRate = widget.session.playback.rate;
                              widget.session.setRate(2.0);
                              setState(() => _isLongPressSpeeding = true);
                            }
                          : null,
                      onLongPressEnd: (_) {
                        if (_isLongPressSpeeding) {
                          widget.session.setRate(_preSpeedRate);
                          setState(() => _isLongPressSpeeding = false);
                        }
                      },
                      onLongPressCancel: () {
                        if (_isLongPressSpeeding) {
                          widget.session.setRate(_preSpeedRate);
                          setState(() => _isLongPressSpeeding = false);
                        }
                      },
                      onVerticalDragStart: (_) {
                        if (!_isScrubbing) {
                          _isVerticalDragging = true;
                        }
                      },
                      onVerticalDragEnd: (_) {
                        _isVerticalDragging = false;
                      },
                      onVerticalDragCancel: () {
                        _isVerticalDragging = false;
                      },
                      onVerticalDragUpdate: (_isLocked || _isScrubbing)
                          ? null
                          : (d) {
                              final delta = -d.primaryDelta! / 200.0;
                              setState(() {
                                _brightness = (_brightness + delta).clamp(
                                  0.1,
                                  1.0,
                                );
                              });
                              _showGestureHud('brightness');
                            },
                      onHorizontalDragStart: (d) {
                        if (!_isVerticalDragging) {
                          _onHorizontalDragStart(d, currentPos, mediaDuration);
                        }
                      },
                      onHorizontalDragUpdate: (d) {
                        if (!_isVerticalDragging) {
                          _onHorizontalDragUpdate(
                            d,
                            mediaDuration,
                            screenWidth,
                          );
                        }
                      },
                      onHorizontalDragEnd: (d) {
                        _isVerticalDragging = false;
                        _onHorizontalDragEnd(d, isHostOrAdmin);
                      },
                      onHorizontalDragCancel: () {
                        _isVerticalDragging = false;
                        _onHorizontalDragCancel();
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // Right half: Double-tap forward 10s, vertical drag volume, horizontal drag seek, long-press 2.0x
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTap: isHostOrAdmin
                          ? () => _seekRelative(10)
                          : null,
                      onLongPressStart: isHostOrAdmin
                          ? (_) {
                              _preSpeedRate = widget.session.playback.rate;
                              widget.session.setRate(2.0);
                              setState(() => _isLongPressSpeeding = true);
                            }
                          : null,
                      onLongPressEnd: (_) {
                        if (_isLongPressSpeeding) {
                          widget.session.setRate(_preSpeedRate);
                          setState(() => _isLongPressSpeeding = false);
                        }
                      },
                      onLongPressCancel: () {
                        if (_isLongPressSpeeding) {
                          widget.session.setRate(_preSpeedRate);
                          setState(() => _isLongPressSpeeding = false);
                        }
                      },
                      onVerticalDragStart: (_) {
                        if (!_isScrubbing) {
                          _isVerticalDragging = true;
                        }
                      },
                      onVerticalDragEnd: (_) {
                        _isVerticalDragging = false;
                      },
                      onVerticalDragCancel: () {
                        _isVerticalDragging = false;
                      },
                      onVerticalDragUpdate: (_isLocked || _isScrubbing)
                          ? null
                          : (d) {
                              final delta = -d.primaryDelta! / 200.0;
                              setState(() {
                                _volume = (_volume + delta).clamp(0.0, 1.0);
                                if (_isMuted && _volume > 0) _isMuted = false;
                              });
                              widget.session.player.setVolume(_volume * 100.0);
                              _showGestureHud('volume');
                            },
                      onHorizontalDragStart: (d) {
                        if (!_isVerticalDragging) {
                          _onHorizontalDragStart(d, currentPos, mediaDuration);
                        }
                      },
                      onHorizontalDragUpdate: (d) {
                        if (!_isVerticalDragging) {
                          _onHorizontalDragUpdate(
                            d,
                            mediaDuration,
                            screenWidth,
                          );
                        }
                      },
                      onHorizontalDragEnd: (d) {
                        _isVerticalDragging = false;
                        _onHorizontalDragEnd(d, isHostOrAdmin);
                      },
                      onHorizontalDragCancel: () {
                        _isVerticalDragging = false;
                        _onHorizontalDragCancel();
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),

            // Peer Buffering Waiting Banner (Host mode: BUG-PLAY-06)
            if (widget.session.isHostWaitingPeerBuffering)
              Positioned(
                top: isFullscreen ? 56 : 16,
                left: 20,
                right: 20,
                child: Center(
                  child: GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.glass,
                    color: Colors.black54,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tc.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          i18n.peerBufferingPausedNotice,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Buffering Indicator
            if (isBuffering && widget.session.lastErrorCode != 'source_offline')
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tc.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          i18n.bufferingLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Source Offline Overlay
            if (widget.session.lastErrorCode == 'source_offline')
              Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 40,
                        color: tc.warning,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        i18n.sourceOfflineTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        i18n.sourceOfflineDesc,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Empty Media / Cinema Screen Overlay
            if (_currentPlaylistItem == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: GlassContainer.card(
                      surfaceStyle: GlassSurfaceStyle.solid,
                      color: tc.cardBackground.withValues(alpha: 0.92),
                      shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 22,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: tc.primary.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.movie_filter_rounded,
                                size: 28,
                                color: tc.primary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              i18n.emptyPlaylistTitle,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: tc.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              i18n.emptyPlaylistDesc,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: tc.textSecondary,
                              ),
                            ),
                            if (isHostOrAdmin) ...[
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  LiquidGlassActionButton(
                                    key: const ValueKey(
                                      'empty-screen-add-local-btn',
                                    ),
                                    onTap: () async {
                                      try {
                                        await widget.session
                                            .pickAndAddLocalFile();
                                      } catch (_) {}
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.file_open_rounded,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          i18n.addLocalVideo,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  LiquidGlassActionButton(
                                    key: const ValueKey(
                                      'empty-screen-add-online-btn',
                                    ),
                                    isPrimary: true,
                                    onTap: () => _showAddMediaDialog(context),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.link_rounded,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          i18n.addOnlineStream,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // P2P Blocked Local Media Overlay
            if (_currentPlaylistItem != null &&
                _currentPlaylistItem!.sourceType == 'local' &&
                widget.session.isP2pFailed &&
                !widget.session.isP2pConnected &&
                widget.session.lastErrorCode != 'source_offline')
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_tethering_off_rounded,
                          size: 44,
                          color: tc.warning,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          i18n.p2pFailedPill,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          i18n.p2pBlockedLocalNotice,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LiquidGlassActionButton(
                              onTap: () => widget.session.retryP2p(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    i18n.retryP2p,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            LiquidGlassActionButton(
                              onTap: () => SettingsDialog.show(
                                context,
                                session: widget.session,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.settings_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    i18n.settingsTitle,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating Scrub HUD (Horizontal Drag Seek Indicator)
            if (_isScrubbing && _scrubTarget != null)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 20,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _scrubDeltaSec >= 0
                                  ? Icons.fast_forward_rounded
                                  : Icons.fast_rewind_rounded,
                              color: _scrubDeltaSec >= 0
                                  ? tc.primary
                                  : Colors.orangeAccent,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_scrubDeltaSec >= 0 ? '+' : ''}${_scrubDeltaSec}s',
                              style: TextStyle(
                                color: _scrubDeltaSec >= 0
                                    ? tc.primary
                                    : Colors.orangeAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${formatDuration(_scrubTarget!)} / ${formatDuration(mediaDuration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 140,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: mediaDuration.inMilliseconds > 0
                                  ? (_scrubTarget!.inMilliseconds /
                                            mediaDuration.inMilliseconds)
                                        .clamp(0.0, 1.0)
                                  : 0.0,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                tc.primary,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating Center Gesture HUD (Brightness, Volume, Skip Indicator)
            if (_gestureHudType != null)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _gestureHudType == 'brightness'
                              ? Icons.brightness_medium_rounded
                              : (_gestureHudType == 'volume'
                                    ? (_volume > 0
                                          ? Icons.volume_up_rounded
                                          : Icons.volume_off_rounded)
                                    : (_gestureHudType == 'forward'
                                          ? Icons.fast_forward_rounded
                                          : Icons.fast_rewind_rounded)),
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        if (_gestureHudType == 'brightness' ||
                            _gestureHudType == 'volume') ...[
                          SizedBox(
                            width: 72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _gestureHudType == 'brightness'
                                    ? _brightness
                                    : _volume,
                                backgroundColor: Colors.white24,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  tc.primary,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${((_gestureHudType == 'brightness' ? _brightness : _volume) * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ] else ...[
                          Text(
                            _gestureHudType == 'forward' ? '+10s' : '-10s',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            // Floating 2.0x Long Press Acceleration HUD
            if (_isLongPressSpeeding)
              Positioned(
                top: isShort ? 44 : 58,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tc.primary.withValues(alpha: 0.8),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.fast_forward_rounded,
                          color: tc.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          i18n.fastForwarding2x,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isShort ? 11 : 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating In-Player Mini Toast HUD
            if (_playerToastMessage != null)
              Positioned(
                top: isShort ? 44 : 58,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_playerToastIcon != null) ...[
                          Icon(_playerToastIcon, color: tc.primary, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _playerToastMessage!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isShort ? 11.5 : 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating Screen Lock Button (Left edge)
            Positioned(
              left: isShort ? 12 : 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: (_showControls || _isLocked) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls && !_isLocked,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isLocked = !_isLocked;
                          if (!_isLocked) {
                            _showControls = true;
                            _restartControlsTimer();
                          }
                        });
                        _showPlayerToast(
                          _isLocked ? i18n.screenLocked : i18n.screenUnlocked,
                          _isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                        );
                      },
                      child: Container(
                        width: isShort ? 36 : 42,
                        height: isShort ? 36 : 42,
                        decoration: BoxDecoration(
                          color: _isLocked
                              ? tc.primary.withValues(alpha: 0.85)
                              : Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isLocked ? Colors.white : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          _isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          color: Colors.white,
                          size: isShort ? 18 : 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Top HUD: Media Title & Controls
            Positioned(
              top: isShort ? 8 : 14,
              left: isShort ? 10 : 16,
              right: isShort ? 10 : 16,
              child: AnimatedOpacity(
                opacity: (_showControls && !_isLocked) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls || _isLocked,
                  child: Row(
                    children: [
                      if (isFullscreen) ...[
                        Semantics(
                          button: true,
                          enabled: true,
                          label: i18n.exitFullscreen,
                          child: Tooltip(
                            message: i18n.exitFullscreen,
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => _setFullscreen(false),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (currentMedia != null)
                        Flexible(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isShort ? 8 : 12,
                              vertical: isShort ? 4 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.movie_rounded,
                                  size: isShort ? 12 : 14,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    currentMedia.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isShort ? 11 : 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (!isHostOrAdmin) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isShort ? 8 : 10,
                            vertical: isShort ? 3 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            i18n.readOnlyControlTooltip,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isShort ? 9.5 : 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (!isFullscreen && !_isLandscape) ...[
                        // Collapsed into single "···" More Settings button in portrait/narrow mode
                        Tooltip(
                          message: i18n.moreSettings,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              key: const ValueKey('cinema-more-btn'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: isShort ? 28 : 34,
                                minHeight: isShort ? 28 : 34,
                              ),
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: Colors.white,
                                size: isShort ? 18 : 20,
                              ),
                              onPressed: () {
                                _restartControlsTimer();
                                _showMoreSettingsSheet(context);
                              },
                            ),
                          ),
                        ),
                      ] else ...[
                        // Fullscreen or Landscape mode: expanded quick actions + more button
                        // Common Top Action: Danmaku Toggle
                        Tooltip(
                          message: _danmakuEnabled
                              ? i18n.danmakuEnabled
                              : i18n.danmakuDisabled,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              key: const ValueKey('cinema-danmaku-btn'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: isShort ? 28 : 32,
                                minHeight: isShort ? 28 : 32,
                              ),
                              icon: Icon(
                                _danmakuEnabled
                                    ? Icons.subtitles_rounded
                                    : Icons.subtitles_off_rounded,
                                color: _danmakuEnabled
                                    ? tc.primary
                                    : Colors.white38,
                                size: isShort ? 16 : 18,
                              ),
                              onPressed: () {
                                _restartControlsTimer();
                                setState(
                                  () => _danmakuEnabled = !_danmakuEnabled,
                                );
                                _showPlayerToast(
                                  _danmakuEnabled
                                      ? i18n.danmakuEnabled
                                      : i18n.danmakuDisabled,
                                  _danmakuEnabled
                                      ? Icons.subtitles_rounded
                                      : Icons.subtitles_off_rounded,
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Common Top Action: Loop Mode
                        Tooltip(
                          message:
                              widget.session.loopMode ==
                                  PlaybackLoopMode.loopOne
                              ? i18n.loopModeOne
                              : (widget.session.loopMode ==
                                        PlaybackLoopMode.sequential
                                    ? i18n.loopModeSeq
                                    : i18n.loopModeAll),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              key: const ValueKey('cinema-loop-mode-btn'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: isShort ? 28 : 32,
                                minHeight: isShort ? 28 : 32,
                              ),
                              icon: Icon(
                                widget.session.loopMode ==
                                        PlaybackLoopMode.loopOne
                                    ? Icons.repeat_one_rounded
                                    : (widget.session.loopMode ==
                                              PlaybackLoopMode.sequential
                                          ? Icons.playlist_play_rounded
                                          : Icons.repeat_rounded),
                                color: Colors.white70,
                                size: isShort ? 16 : 18,
                              ),
                              onPressed: () {
                                _restartControlsTimer();
                                _cycleLoopMode();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Common Top Action: Tracks & Subtitles
                        Tooltip(
                          message: '${i18n.subtitleTrack} / ${i18n.audioTrack}',
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              key: const ValueKey('cinema-tracks-btn'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: isShort ? 28 : 32,
                                minHeight: isShort ? 28 : 32,
                              ),
                              icon: Icon(
                                Icons.tune_rounded,
                                color: Colors.white70,
                                size: isShort ? 16 : 18,
                              ),
                              onPressed: () {
                                _restartControlsTimer();
                                _showTrackSelectionDialog(context);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Fullscreen Top Right: Aspect Ratio & Orientation Toggle
                        Tooltip(
                          message:
                              '${i18n.aspectRatio}: ${_aspectFit == BoxFit.contain ? i18n.aspectFitContain : (_aspectFit == BoxFit.cover ? i18n.aspectFitCover : i18n.aspectFitFill)}',
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              key: const ValueKey('cinema-aspect-ratio-btn'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: isShort ? 28 : 34,
                                minHeight: isShort ? 28 : 34,
                              ),
                              icon: Icon(
                                Icons.aspect_ratio_rounded,
                                color: Colors.white70,
                                size: isShort ? 16 : 18,
                              ),
                              onPressed: _cycleAspectRatio,
                            ),
                          ),
                        ),
                        if (!kIsWeb) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: i18n.toggleOrientation,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                key: const ValueKey('cinema-orientation-btn'),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(
                                  minWidth: isShort ? 28 : 34,
                                  minHeight: isShort ? 28 : 34,
                                ),
                                icon: Icon(
                                  _isLandscape
                                      ? Icons.stay_current_portrait_rounded
                                      : Icons.screen_rotation_rounded,
                                  color: Colors.white70,
                                  size: isShort ? 16 : 18,
                                ),
                                onPressed: () {
                                  _restartControlsTimer();
                                  _toggleOrientation();
                                },
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),

                        // More Settings Sheet in Landscape / Fullscreen too
                        Tooltip(
                          message: i18n.moreSettings,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              key: const ValueKey('cinema-more-btn-expanded'),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: isShort ? 28 : 34,
                                minHeight: isShort ? 28 : 34,
                              ),
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: Colors.white70,
                                size: isShort ? 18 : 20,
                              ),
                              onPressed: () {
                                _restartControlsTimer();
                                _showMoreSettingsSheet(context);
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Floating Scrubber Time Bubble (when dragging slider)
            if (_draggingSliderValue != null)
              Positioned(
                bottom: isShort ? 64 : 84,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tc.primary.withValues(alpha: 0.6),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      formatDuration(displayPos),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),

            // Center Big Play Indicator (Youku / Bilibili Mainstream Style)
            if (!isPlaying &&
                !isBuffering &&
                currentMedia != null &&
                !_isLocked)
              Center(
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.85,
                  duration: const Duration(milliseconds: 200),
                  child: Semantics(
                    button: true,
                    enabled: isHostOrAdmin,
                    label: i18n.playTooltip,
                    child: GestureDetector(
                      onTap: isHostOrAdmin
                          ? () async {
                              _restartControlsTimer();
                              try {
                                await widget.session.play();
                              } catch (_) {}
                            }
                          : null,
                      child: Container(
                        width: isShort ? 46 : 56,
                        height: isShort ? 46 : 56,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isHostOrAdmin
                                ? tc.primary.withValues(alpha: 0.8)
                                : Colors.white30,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: isShort ? 30 : 36,
                          color: isHostOrAdmin ? tc.primary : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom Player Control Deck
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: (_showControls && !_isLocked) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_showControls || _isLocked,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      isShort ? 10 : 16,
                      isShort ? 8 : 16,
                      isShort ? 10 : 16,
                      isShort ? 6 : 10,
                    ),
                    child: (!isFullscreen && !_isLandscape)
                        ? // ─── 竖屏单行极简控制栏 (优酷/B站风格，弹性自适应绝不溢出) ───
                          Row(
                            children: [
                              // 播放 / 暂停
                              Semantics(
                                button: true,
                                enabled: isHostOrAdmin,
                                label: !isHostOrAdmin
                                    ? '${isPlaying ? i18n.pauseTooltip : i18n.playTooltip} (${i18n.readOnlyControlTooltip})'
                                    : (isPlaying
                                          ? i18n.pauseTooltip
                                          : i18n.playTooltip),
                                child: Tooltip(
                                  message: !isHostOrAdmin
                                      ? i18n.readOnlyControlTooltip
                                      : (isPlaying
                                            ? i18n.pauseTooltip
                                            : i18n.playTooltip),
                                  child: IconButton(
                                    key: const ValueKey(
                                      'cinema-play-pause-btn',
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(
                                      minWidth: isShort ? 28 : 34,
                                      minHeight: isShort ? 28 : 34,
                                    ),
                                    icon: Icon(
                                      isPlaying
                                          ? Icons.pause_circle_filled_rounded
                                          : Icons.play_circle_fill_rounded,
                                      color: isHostOrAdmin
                                          ? tc.primary
                                          : Colors.white38,
                                      size: isShort ? 24 : 28,
                                    ),
                                    onPressed: isHostOrAdmin
                                        ? () async {
                                            _restartControlsTimer();
                                            try {
                                              if (isPlaying) {
                                                await widget.session.pause();
                                              } else {
                                                await widget.session.play();
                                              }
                                            } catch (_) {}
                                          }
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // 当前时间 / 总时长
                              Text(
                                '${formatDuration(displayPos)} / ${formatDuration(mediaDuration)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: isShort ? 10 : 11,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 弹性自适应进度条 (BUG-PLAY-01: 单一手势源 tapAndSlide，彻底消除 double-seek 竞争)
                              Expanded(
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: tc.primary,
                                      inactiveTrackColor: Colors.white24,
                                      secondaryActiveTrackColor: tc.primary
                                          .withValues(alpha: 0.35),
                                      thumbColor: Colors.white,
                                      thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius: isShort ? 4.5 : 5.5,
                                      ),
                                      overlayShape: RoundSliderOverlayShape(
                                        overlayRadius: isShort ? 9 : 11,
                                      ),
                                      trackHeight: isShort ? 2.5 : 3.0,
                                      allowedInteraction:
                                          SliderInteraction.tapAndSlide,
                                    ),
                                    child: Slider(
                                      key: const ValueKey(
                                        'cinema-timeline-slider',
                                      ),
                                      value: displayRatio,
                                      secondaryTrackValue:
                                          (syncTargetRatio > 0.0 &&
                                              syncTargetRatio != displayRatio &&
                                              _draggingSliderValue == null)
                                          ? syncTargetRatio
                                          : null,
                                      onChangeStart:
                                          (isHostOrAdmin &&
                                              mediaDuration.inMilliseconds > 0)
                                          ? (val) {
                                              _restartControlsTimer();
                                              _optimisticSeekTimer?.cancel();
                                              setState(() {
                                                _draggingSliderValue = val
                                                    .clamp(0.0, 1.0);
                                                _optimisticSeekRatio = val
                                                    .clamp(0.0, 1.0);
                                              });
                                            }
                                          : null,
                                      onChanged:
                                          (isHostOrAdmin &&
                                              mediaDuration.inMilliseconds > 0)
                                          ? (val) {
                                              _restartControlsTimer();
                                              setState(
                                                () => _draggingSliderValue = val
                                                    .clamp(0.0, 1.0),
                                              );
                                            }
                                          : null,
                                      onChangeEnd:
                                          (isHostOrAdmin &&
                                              mediaDuration.inMilliseconds > 0)
                                          ? (val) => _onSliderSeek(
                                              val,
                                              mediaDuration,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // 倍速胶囊
                              Semantics(
                                button: true,
                                enabled: isHostOrAdmin,
                                label:
                                    '${i18n.playbackRate}: ${widget.session.playback.rate}x',
                                child: Tooltip(
                                  message:
                                      '${i18n.playbackRate} (${widget.session.playback.rate}x)',
                                  child: GestureDetector(
                                    key: const ValueKey(
                                      'cinema-playback-rate-btn',
                                    ),
                                    onTap: isHostOrAdmin
                                        ? () {
                                            _restartControlsTimer();
                                            _showSpeedMenu(context);
                                          }
                                        : null,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isShort ? 5 : 7,
                                        vertical: isShort ? 2.5 : 3.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white12,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${widget.session.playback.rate}x',
                                        style: TextStyle(
                                          color: isHostOrAdmin
                                              ? Colors.white
                                              : Colors.white38,
                                          fontSize: isShort ? 10 : 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),

                              // 全屏按钮 (直接横屏全屏)
                              Semantics(
                                button: true,
                                enabled: true,
                                label: i18n.fullscreenTooltip,
                                child: Tooltip(
                                  message: i18n.fullscreenTooltip,
                                  child: IconButton(
                                    key: const ValueKey(
                                      'cinema-fullscreen-btn',
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: BoxConstraints(
                                      minWidth: isShort ? 28 : 34,
                                      minHeight: isShort ? 28 : 34,
                                    ),
                                    icon: Icon(
                                      Icons.fullscreen_rounded,
                                      color: Colors.white70,
                                      size: isShort ? 20 : 22,
                                    ),
                                    onPressed: () {
                                      _restartControlsTimer();
                                      _setFullscreen(true);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          )
                        : // ─── 横屏全屏模式双层控制台 (功能完整专业宽屏) ───
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Timeline Slider & Timestamps
                              Row(
                                children: [
                                  Text(
                                    formatDuration(displayPos),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isShort ? 10.5 : 11.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: tc.primary,
                                          inactiveTrackColor: Colors.white24,
                                          secondaryActiveTrackColor: tc.primary
                                              .withValues(alpha: 0.35),
                                          thumbColor: Colors.white,
                                          thumbShape: RoundSliderThumbShape(
                                            enabledThumbRadius: isShort
                                                ? 4.5
                                                : 6,
                                          ),
                                          overlayShape: RoundSliderOverlayShape(
                                            overlayRadius: isShort ? 9 : 12,
                                          ),
                                          trackHeight: isShort ? 2.5 : 3.5,
                                          allowedInteraction:
                                              SliderInteraction.tapAndSlide,
                                        ),
                                        child: Slider(
                                          key: const ValueKey(
                                            'cinema-timeline-slider',
                                          ),
                                          value: displayRatio,
                                          secondaryTrackValue:
                                              (syncTargetRatio > 0.0 &&
                                                  syncTargetRatio !=
                                                      displayRatio &&
                                                  _draggingSliderValue == null)
                                              ? syncTargetRatio
                                              : null,
                                          onChangeStart:
                                              (isHostOrAdmin &&
                                                  mediaDuration.inMilliseconds >
                                                      0)
                                              ? (val) {
                                                  _restartControlsTimer();
                                                  _optimisticSeekTimer
                                                      ?.cancel();
                                                  setState(() {
                                                    _draggingSliderValue = val
                                                        .clamp(0.0, 1.0);
                                                    _optimisticSeekRatio = val
                                                        .clamp(0.0, 1.0);
                                                  });
                                                }
                                              : null,
                                          onChanged:
                                              (isHostOrAdmin &&
                                                  mediaDuration.inMilliseconds >
                                                      0)
                                              ? (val) {
                                                  _restartControlsTimer();
                                                  setState(
                                                    () => _draggingSliderValue =
                                                        val.clamp(0.0, 1.0),
                                                  );
                                                }
                                              : null,
                                          onChangeEnd:
                                              (isHostOrAdmin &&
                                                  mediaDuration.inMilliseconds >
                                                      0)
                                              ? (val) => _onSliderSeek(
                                                  val,
                                                  mediaDuration,
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatDuration(mediaDuration),
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: isShort ? 10.5 : 11.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: isShort ? 2 : 6),

                              // Controls Row
                              Row(
                                children: [
                                  // Rewind 10s button
                                  IconButton(
                                    key: const ValueKey('cinema-rewind-10-btn'),
                                    padding: isShort
                                        ? const EdgeInsets.all(4)
                                        : const EdgeInsets.all(6),
                                    constraints: isShort
                                        ? const BoxConstraints()
                                        : null,
                                    icon: Icon(
                                      Icons.replay_10_rounded,
                                      color: isHostOrAdmin
                                          ? Colors.white70
                                          : Colors.white24,
                                      size: isShort ? 20 : 22,
                                    ),
                                    onPressed: isHostOrAdmin
                                        ? () => _seekRelative(-10)
                                        : null,
                                    tooltip: i18n.rewind10,
                                  ),

                                  // Shared Play / Pause Toggle
                                  Semantics(
                                    button: true,
                                    enabled: isHostOrAdmin,
                                    label: !isHostOrAdmin
                                        ? '${isPlaying ? i18n.pauseTooltip : i18n.playTooltip} (${i18n.readOnlyControlTooltip})'
                                        : (isPlaying
                                              ? i18n.pauseTooltip
                                              : i18n.playTooltip),
                                    child: Tooltip(
                                      message: !isHostOrAdmin
                                          ? i18n.readOnlyControlTooltip
                                          : (isPlaying
                                                ? i18n.pauseTooltip
                                                : i18n.playTooltip),
                                      child: IconButton(
                                        key: const ValueKey(
                                          'cinema-play-pause-btn',
                                        ),
                                        padding: isShort
                                            ? const EdgeInsets.all(4)
                                            : const EdgeInsets.all(8),
                                        constraints: isShort
                                            ? const BoxConstraints()
                                            : null,
                                        icon: Icon(
                                          isPlaying
                                              ? Icons
                                                    .pause_circle_filled_rounded
                                              : Icons.play_circle_fill_rounded,
                                          color: isHostOrAdmin
                                              ? tc.primary
                                              : Colors.white38,
                                          size: isShort ? 26 : 30,
                                        ),
                                        onPressed: isHostOrAdmin
                                            ? () async {
                                                _restartControlsTimer();
                                                try {
                                                  if (isPlaying) {
                                                    await widget.session
                                                        .pause();
                                                  } else {
                                                    await widget.session.play();
                                                  }
                                                } catch (_) {}
                                              }
                                            : null,
                                      ),
                                    ),
                                  ),

                                  // Forward 10s button
                                  IconButton(
                                    key: const ValueKey(
                                      'cinema-forward-10-btn',
                                    ),
                                    padding: isShort
                                        ? const EdgeInsets.all(4)
                                        : const EdgeInsets.all(6),
                                    constraints: isShort
                                        ? const BoxConstraints()
                                        : null,
                                    icon: Icon(
                                      Icons.forward_10_rounded,
                                      color: isHostOrAdmin
                                          ? Colors.white70
                                          : Colors.white24,
                                      size: isShort ? 20 : 22,
                                    ),
                                    onPressed: isHostOrAdmin
                                        ? () => _seekRelative(10)
                                        : null,
                                    tooltip: i18n.fastForward10,
                                  ),

                                  // Local Volume / Mute
                                  Semantics(
                                    button: true,
                                    enabled: true,
                                    label: _isMuted
                                        ? i18n.unmuteTooltip
                                        : i18n.muteTooltip,
                                    child: Tooltip(
                                      message: _isMuted
                                          ? i18n.unmuteTooltip
                                          : i18n.muteTooltip,
                                      child: IconButton(
                                        key: const ValueKey(
                                          'cinema-volume-mute-btn',
                                        ),
                                        padding: isShort
                                            ? const EdgeInsets.all(4)
                                            : const EdgeInsets.all(8),
                                        constraints: isShort
                                            ? const BoxConstraints()
                                            : null,
                                        icon: Icon(
                                          _isMuted
                                              ? Icons.volume_off_rounded
                                              : Icons.volume_up_rounded,
                                          color: Colors.white70,
                                          size: isShort ? 18 : 20,
                                        ),
                                        onPressed: () {
                                          _restartControlsTimer();
                                          setState(() => _isMuted = !_isMuted);
                                          widget.session.player.setVolume(
                                            _isMuted ? 0.0 : _volume * 100.0,
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                                  // Playback Rate Selector
                                  Semantics(
                                    button: true,
                                    enabled: isHostOrAdmin,
                                    label:
                                        '${i18n.playbackRate}: ${widget.session.playback.rate}x',
                                    child: Tooltip(
                                      message: isHostOrAdmin
                                          ? '${i18n.playbackRate} (${widget.session.playback.rate}x)'
                                          : '${i18n.playbackRate} (${i18n.readOnlyControlTooltip})',
                                      child: GestureDetector(
                                        key: const ValueKey(
                                          'cinema-playback-rate-btn',
                                        ),
                                        onTap: isHostOrAdmin
                                            ? () {
                                                _restartControlsTimer();
                                                _showSpeedMenu(context);
                                              }
                                            : null,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: isShort ? 6 : 8,
                                            vertical: isShort ? 3 : 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white12,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            '${widget.session.playback.rate}x',
                                            style: TextStyle(
                                              color: isHostOrAdmin
                                                  ? Colors.white
                                                  : Colors.white38,
                                              fontSize: isShort ? 10 : 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const Spacer(),

                                  // Aspect Ratio Toggle
                                  Tooltip(
                                    message:
                                        '${i18n.aspectRatio}: ${_aspectFit == BoxFit.contain ? i18n.aspectFitContain : (_aspectFit == BoxFit.cover ? i18n.aspectFitCover : i18n.aspectFitFill)}',
                                    child: IconButton(
                                      key: const ValueKey(
                                        'cinema-aspect-ratio-btn',
                                      ),
                                      padding: isShort
                                          ? const EdgeInsets.all(4)
                                          : const EdgeInsets.all(8),
                                      constraints: isShort
                                          ? const BoxConstraints()
                                          : null,
                                      icon: Icon(
                                        Icons.aspect_ratio_rounded,
                                        color: Colors.white70,
                                        size: isShort ? 18 : 20,
                                      ),
                                      onPressed: _cycleAspectRatio,
                                    ),
                                  ),

                                  // Fullscreen Toggle (Exit)
                                  Semantics(
                                    button: true,
                                    enabled: true,
                                    label: i18n.exitFullscreenTooltip,
                                    child: Tooltip(
                                      message: i18n.exitFullscreenTooltip,
                                      child: IconButton(
                                        key: const ValueKey(
                                          'cinema-fullscreen-btn',
                                        ),
                                        padding: isShort
                                            ? const EdgeInsets.all(4)
                                            : const EdgeInsets.all(8),
                                        constraints: isShort
                                            ? const BoxConstraints()
                                            : null,
                                        icon: Icon(
                                          Icons.fullscreen_exit_rounded,
                                          color: Colors.white70,
                                          size: isShort ? 18 : 22,
                                        ),
                                        onPressed: () {
                                          _restartControlsTimer();
                                          _setFullscreen(false);
                                        },
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorDock(
    BuildContext context, {
    required bool isMobile,
    bool isShort = false,
    required bool isOwner,
    required bool isHostOrAdmin,
  }) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: tc.cardBackground,
      shape: LiquidRoundedSuperellipse(borderRadius: isShort ? 16 : 20),
      padding: EdgeInsets.all(isShort ? 10 : 12),
      child: Column(
        children: [
          // Segmented Tab Switcher
          GlassSegmentedControl(
            selectedIndex: _selectedTabIndex,
            onSegmentSelected: (idx) => setState(() => _selectedTabIndex = idx),
            segments: [
              GlassSegment(label: i18n.tabChat),
              GlassSegment(label: i18n.tabPlaylist),
              GlassSegment(label: i18n.tabMembers),
              GlassSegment(label: i18n.tabSession),
            ],
          ),
          SizedBox(height: isShort ? 6 : 10),

          // Dock Body Content
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildChatTab(context, isShort: isShort),
                _buildPlaylistTab(context, isHostOrAdmin, isShort: isShort),
                _buildMembersTab(context, isOwner),
                _buildSessionInfoTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistTab(
    BuildContext context,
    bool isHostOrAdmin, {
    bool isShort = false,
  }) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final playlist = widget.session.playlist;
    final currentItemId = widget.session.currentItemId;

    return Column(
      children: [
        // Action Bar: Add Media
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${i18n.tabPlaylist} (${playlist.length})',
              style: TextStyle(
                fontSize: isShort ? 12 : 13,
                fontWeight: FontWeight.w700,
                color: tc.textPrimary,
              ),
            ),
            if (isHostOrAdmin)
              Semantics(
                button: true,
                label: i18n.addMedia,
                child: LiquidGlassActionButton(
                  key: const ValueKey('cinema-add-media-btn'),
                  height: isShort ? 28 : 32,
                  onTap: () => _showAddMediaDialog(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        i18n.addMedia,
                        style: TextStyle(
                          fontSize: isShort ? 11 : 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: isShort ? 6 : 8),

        Expanded(
          child: playlist.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.video_collection_outlined,
                          size: isShort ? 28 : 32,
                          color: tc.textTertiary,
                        ),
                        SizedBox(height: isShort ? 4 : 6),
                        Text(
                          i18n.playlistEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isShort ? 11 : 12,
                            color: tc.textTertiary,
                          ),
                        ),
                        if (isHostOrAdmin) ...[
                          const SizedBox(height: 12),
                          LiquidGlassActionButton(
                            height: 32,
                            onTap: () => _showAddMediaDialog(context),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_rounded, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  i18n.addMedia,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: playlist.length,
                  onReorder: (oldIndex, newIndex) {
                    if (!isHostOrAdmin) return;
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = playlist[oldIndex];
                    widget.session.reorderItem(item.itemId, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final item = playlist[index];
                    final isCurrent = item.itemId == currentItemId;
                    final isOffline = widget.session.isItemSourceOffline(item);

                    return Container(
                      key: ValueKey(item.itemId),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? tc.primary.withValues(alpha: 0.12)
                            : tc.inputBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? tc.primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          if (isHostOrAdmin)
                            ReorderableDragStartListener(
                              index: index,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 16,
                                    color: tc.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          Icon(
                            item.sourceType == 'local'
                                ? Icons.folder_rounded
                                : Icons.link_rounded,
                            size: 16,
                            color: isCurrent ? tc.primary : tc.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isCurrent
                                        ? tc.primary
                                        : tc.textPrimary,
                                  ),
                                ),
                                if (item.url != null)
                                  Text(
                                    item.url!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: tc.textTertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isOffline)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                i18n.sourceUserLeftRoom,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                            ),
                          if (isCurrent)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tc.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                i18n.nowPlayingBadge,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (isHostOrAdmin) ...[
                            // Reorder Up
                            Semantics(
                              button: true,
                              enabled: index > 0,
                              label: '${i18n.moveUp}: ${item.title}',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 16,
                                ),
                                tooltip: i18n.moveUp,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: index > 0
                                    ? () => widget.session.reorderItem(
                                        item.itemId,
                                        index - 1,
                                      )
                                    : null,
                              ),
                            ),
                            // Reorder Down
                            Semantics(
                              button: true,
                              enabled: index < playlist.length - 1,
                              label: '${i18n.moveDown}: ${item.title}',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 16,
                                ),
                                tooltip: i18n.moveDown,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: index < playlist.length - 1
                                    ? () => widget.session.reorderItem(
                                        item.itemId,
                                        index + 1,
                                      )
                                    : null,
                              ),
                            ),
                            // Replace item
                            Semantics(
                              button: true,
                              enabled: true,
                              label: '${i18n.replaceMedia}: ${item.title}',
                              child: IconButton(
                                icon: const Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 16,
                                ),
                                tooltip: i18n.replaceMedia,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () =>
                                    _showReplaceMediaDialog(context, item),
                              ),
                            ),
                            // Switch item (if not current)
                            if (!isCurrent)
                              Semantics(
                                button: true,
                                enabled: !isOffline,
                                label: '${i18n.switchMedia}: ${item.title}',
                                child: IconButton(
                                  icon: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                    color: isOffline ? Colors.white24 : null,
                                  ),
                                  tooltip: isOffline
                                      ? i18n.sourceUserLeftRoom
                                      : i18n.switchMedia,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  onPressed: isOffline
                                      ? () {
                                          showLiquidGlassSnackBar(
                                            context,
                                            owner: this,
                                            message: i18n.sourceUserLeftRoom,
                                            icon: Icons.error_outline_rounded,
                                            iconColor: Colors.orangeAccent,
                                          );
                                        }
                                      : () => widget.session.switchItem(
                                          item.itemId,
                                        ),
                                ),
                              ),
                            // Remove item
                            Semantics(
                              button: true,
                              enabled: true,
                              label: '${i18n.removeMedia}: ${item.title}',
                              child: IconButton(
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: tc.error,
                                ),
                                tooltip: i18n.removeMedia,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () =>
                                    widget.session.removeItem(item.itemId),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMembersTab(BuildContext context, bool isOwner) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final members = widget.session.members;
    final myDeviceId = widget.session.identity.deviceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${i18n.tabMembers} (${members.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: tc.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: ListView.separated(
            cacheExtent: 400,
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final member = members[index];
              final isMe = member.deviceId == myDeviceId;
              final isMemberAdmin = member.role == RoomRole.admin;
              final isMemberOwner = member.role == RoomRole.owner;

              return Semantics(
                container: true,
                child: Container(
                  decoration: BoxDecoration(
                    color: tc.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(
                          avatarKey: member.avatar.isNotEmpty
                              ? member.avatar
                              : (isMe ? AppSettings.instance.avatar : null),
                          fallbackSeed: isMe ? null : member.deviceId,
                          size: 28,
                        ),
                        if (isMemberOwner || isMemberAdmin)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isMemberOwner ? tc.warning : tc.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: tc.background,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                isMemberOwner
                                    ? Icons.star_rounded
                                    : Icons.shield_rounded,
                                size: 7,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                member.displayName.isNotEmpty
                                    ? member.displayName
                                    : formatDeviceId(member.deviceId),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: tc.textPrimary,
                                ),
                              ),
                              if (isMe)
                                Text(
                                  ' ${i18n.peerYou}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tc.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            formatDeviceId(member.deviceId),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: tc.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // F08: Member Playback Telemetry (Strict truthfulness: buffering=false != synced)
                          Builder(
                            builder: (context) {
                              final telemetry = widget
                                  .session
                                  .memberTelemetry[member.deviceId];
                              final memberName = member.displayName.isNotEmpty
                                  ? member.displayName
                                  : formatDeviceId(member.deviceId);
                              final semanticLabel = telemetry != null
                                  ? '$memberName: ${i18n.telemetryPosition} ${formatDuration(Duration(milliseconds: telemetry.positionMs))}${telemetry.buffering ? ', ${i18n.telemetryBuffering}' : ''}'
                                  : '$memberName: ${i18n.telemetryPosition} ${i18n.telemetryUnknown}';

                              return Semantics(
                                label: semanticLabel,
                                container: true,
                                child: Container(
                                  key: ValueKey(
                                    'member-telemetry-${member.deviceId}',
                                  ),
                                  child: telemetry != null
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              telemetry.buffering
                                                  ? Icons.hourglass_top_rounded
                                                  : Icons
                                                        .play_circle_outline_rounded,
                                              size: 11,
                                              color: telemetry.buffering
                                                  ? tc.warning
                                                  : tc.primary,
                                            ),
                                            const SizedBox(width: 3.5),
                                            Text(
                                              formatDuration(
                                                Duration(
                                                  milliseconds:
                                                      telemetry.positionMs,
                                                ),
                                              ),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                                color: tc.textSecondary,
                                              ),
                                            ),
                                            if (telemetry.buffering) ...[
                                              const SizedBox(width: 5),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 0.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: tc.warning.withValues(
                                                    alpha: 0.18,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: Text(
                                                  i18n.telemetryBuffering,
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: tc.warning,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.help_outline_rounded,
                                              size: 11,
                                              color: tc.textTertiary,
                                            ),
                                            const SizedBox(width: 3.5),
                                            Text(
                                              '${i18n.telemetryPosition}: ${i18n.telemetryUnknown}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: tc.textTertiary,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Role Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: isMemberOwner
                            ? tc.warning.withValues(alpha: 0.16)
                            : (isMemberAdmin
                                  ? tc.primary.withValues(alpha: 0.14)
                                  : tc.inputBackground),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isMemberOwner
                            ? i18n.roleOwner
                            : (isMemberAdmin
                                  ? i18n.roleAdmin
                                  : i18n.roleMember),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isMemberOwner
                              ? tc.warning
                              : (isMemberAdmin ? tc.primary : tc.textSecondary),
                        ),
                      ),
                    ),

                    // Owner ACL controls
                    if (isOwner && !isMe && !isMemberOwner) ...[
                      const SizedBox(width: 8),
                      LiquidGlassActionButton(
                        key: ValueKey('member-acl-${member.deviceId}'),
                        semanticLabel: isMemberAdmin
                            ? '${i18n.revokeAdmin}: ${member.displayName.isNotEmpty ? member.displayName : formatDeviceId(member.deviceId)}'
                            : '${i18n.grantAdmin}: ${member.displayName.isNotEmpty ? member.displayName : formatDeviceId(member.deviceId)}',
                        height: 30,
                        onTap: () {
                          if (isMemberAdmin) {
                            widget.session.revokeAdmin(member.deviceId);
                          } else {
                            widget.session.grantAdmin(member.deviceId);
                          }
                        },
                        child: Text(
                          isMemberAdmin ? i18n.revokeAdmin : i18n.grantAdmin,
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSessionInfoTab(BuildContext context) {
    final i18n = AppI18n.of(context);
    final session = widget.session;

    return SingleChildScrollView(
      child: Column(
        children: [
          if (session.roomCode != null)
            _buildInfoRow(context, i18n.roomCodeLabel, session.roomCode!),
          _buildInfoRow(context, i18n.roomIdLabel, session.roomId ?? '-'),
          if (session.inviteText != null)
            _buildInfoRow(context, i18n.copyInvite, session.inviteText!),
          _buildInfoRow(context, i18n.deviceIdLabel, session.identity.deviceId),
          _buildInfoRow(
            context,
            i18n.currentSeqLabel,
            session.playback.seq.toString(),
          ),
          _buildInfoRow(
            context,
            i18n.localPlaybackPos,
            formatDuration(session.player.state.position),
          ),
          if (session.playback.position > Duration.zero)
            _buildInfoRow(
              context,
              i18n.syncTargetLabel,
              formatDuration(session.playback.position),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final tc = ThemeColors.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: tc.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: tc.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

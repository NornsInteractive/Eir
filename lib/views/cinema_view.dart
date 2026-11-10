import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../app_localization.dart';
import '../apple_glass.dart';
import '../models.dart';
import 'settings_dialog.dart';
import 'profile_view.dart';

class CinemaView extends StatefulWidget {
  final RoomSession session;
  final VoidCallback onLeaveRoom;

  const CinemaView({
    super.key,
    required this.session,
    required this.onLeaveRoom,
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
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _isLocked = false;
  BoxFit _aspectFit = BoxFit.contain;
  String? _gestureHudType;
  Timer? _gestureHudTimer;
  double? _draggingSliderValue;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _bufferingSub;
  String? _lastReportedCinemaError;

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(widget.session.player);
    _subscribePlayerStreams(widget.session.player);
    widget.session.addListener(_onSessionStateChanged);
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
      widget.session.addListener(_onSessionStateChanged);
    }
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
    final isConnectionError = code == 'signaling_unavailable' ||
        code == 'connection_failed' ||
        widget.session.connectionState == RoomConnectionState.disconnected;

    showLiquidGlassSnackBar(
      context,
      owner: this,
      message: i18n.mapErrorCode(code),
      icon: isStorageFull ? Icons.disc_full_rounded : Icons.error_outline_rounded,
      onAction: isStorageFull
          ? () => SettingsDialog.show(context, session: widget.session)
          : null,
      actionLabel: isStorageFull ? i18n.clearCacheBtn : null,
      actionKey: isStorageFull ? const ValueKey('cinema-storage-full-clean-btn') : null,
      actionIcon: isStorageFull ? Icons.cleaning_services_rounded : null,
      onRetry: isConnectionError
          ? () async {
              _lastReportedCinemaError = null;
              await widget.session.retry();
            }
          : null,
      retryLabel: isConnectionError ? i18n.retryConnection : null,
      retryKey: isConnectionError ? const ValueKey('cinema-snackbar-retry-connection-btn') : null,
      duration: const Duration(seconds: 5),
    );
  }

  void _subscribePlayerStreams(Player player) {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub = player.stream.position.listen((_) {
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
    _controlsTimer?.cancel();
    _gestureHudTimer?.cancel();
    hideLiquidGlassSnackBar();
    widget.session.removeListener(_onSessionStateChanged);
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _bufferingSub?.cancel();
    // Note: widget.session.player is owned by widget.session, do not dispose player here!
    super.dispose();
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
    final cur = widget.session.playback.position;
    final dur = widget.session.player.state.duration;
    final target = cur + Duration(seconds: seconds);
    final targetMs =
        target.inMilliseconds.clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 0);
    _showGestureHud(seconds > 0 ? 'forward' : 'rewind');
    try {
      await widget.session.seek(Duration(milliseconds: targetMs));
    } catch (_) {}
    _restartControlsTimer();
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
        ? (invite != null
            ? '$roomCode\n\n$invite'
            : roomCode)
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
                        icon: Icon(Icons.close_rounded, size: 18, color: tc.textSecondary),
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
                      i18n.isZh ? '全选文本' : 'Select All',
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
                      minWidth: (constraints.maxWidth - horizontalMargin * 2).clamp(0.0, double.infinity),
                      minHeight: (constraints.maxHeight - verticalMargin * 2).clamp(0.0, double.infinity),
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
                                  Icon(Icons.video_library_rounded, size: isShortWindow ? 18 : 20, color: tc.primary),
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
                                      icon: Icon(Icons.close_rounded, size: isShortWindow ? 16 : 18, color: tc.textSecondary),
                                      tooltip: i18n.close,
                                      padding: isShortWindow ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
                                      constraints: isShortWindow ? const BoxConstraints() : null,
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
                                textStyle: TextStyle(color: tc.textPrimary, fontSize: 13),
                                placeholderStyle: TextStyle(color: tc.textTertiary, fontSize: 12.5),
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
                                textStyle: TextStyle(color: tc.textPrimary, fontSize: 13),
                                placeholderStyle: TextStyle(color: tc.textTertiary, fontSize: 12.5),
                              ),
                              SizedBox(height: isShortWindow ? 10 : 16),

                              Row(
                                children: [
                                  Expanded(
                                    child: LiquidGlassActionButton(
                                      key: const ValueKey('add-item-local-btn'),
                                      height: isShortWindow ? 38 : 42,
                                      onTap: () async {
                                        final messenger = ScaffoldMessenger.maybeOf(context);
                                        Navigator.of(ctx).pop();
                                        _lastReportedCinemaError = null;
                                        try {
                                          await widget.session.pickAndAddLocalFile();
                                        } catch (e) {
                                          if (mounted) {
                                            messenger?.showSnackBar(
                                              SnackBar(
                                                content: Text(i18n.filePickerFailed),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.file_open_rounded, size: isShortWindow ? 15 : 16),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              i18n.addLocalFile,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: isShortWindow ? 11.5 : 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LiquidGlassActionButton(
                                      key: const ValueKey('add-item-submit-btn'),
                                      isPrimary: true,
                                      height: isShortWindow ? 38 : 42,
                                      onTap: () async {
                                        final url = urlController.text.trim();
                                        if (url.isNotEmpty) {
                                          Navigator.of(ctx).pop();
                                          final title = titleController.text.trim();
                                          _lastReportedCinemaError = null;
                                          await widget.session.addUrl(
                                            url,
                                            title: title.isNotEmpty ? title : null,
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
                          Icon(Icons.swap_horiz_rounded, size: 20, color: tc.primary),
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
                              icon: Icon(Icons.close_rounded, size: 18, color: tc.textSecondary),
                              tooltip: i18n.close,
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        i18n.addVideoUrl,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tc.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      GlassTextField(
                        key: const ValueKey('replace-item-url-input'),
                        controller: urlController,
                        placeholder: i18n.urlInputPlaceholder,
                        height: 44,
                        surfaceStyle: GlassSurfaceStyle.solid,
                        color: tc.inputBackground,
                        textStyle: TextStyle(color: tc.textPrimary, fontSize: 13),
                        placeholderStyle: TextStyle(color: tc.textTertiary, fontSize: 12.5),
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
                                  await widget.session.replaceItem(item.itemId, url: newUrl);
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

  void _cyclePlaybackRate() {
    const rates = <double>[0.5, 1.0, 1.25, 1.5, 2.0];
    final current = widget.session.playback.rate;
    int nextIdx = 0;
    for (int i = 0; i < rates.length; i++) {
      if ((rates[i] - current).abs() < 0.05) {
        nextIdx = (i + 1) % rates.length;
        break;
      }
    }
    widget.session.setRate(rates[nextIdx]);
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
        final isNarrow = screenWidth < 560;
        final isShort = screenHeight < 520;
        final session = widget.session;
        final role = session.role;
        final isHostOrAdmin = role == RoomRole.owner || role == RoomRole.admin;
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
            ? (currentPos.inMilliseconds / mediaDuration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        final double syncTargetRatio = mediaDuration.inMilliseconds > 0
            ? (syncTargetPos.inMilliseconds / mediaDuration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Material(
          type: MaterialType.transparency,
          child: GlassScaffold(
          background: LiquidGlassAmbientBackground(child: Container()),
          extendBody: false,
          appBar: _isFullscreen
              ? null
              : GlassAppBar(
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
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                        onPressed: () async {
                          if (isOwner) {
                            await session.closeRoom();
                          } else {
                            await session.leaveRoom();
                          }
                          widget.onLeaveRoom();
                        },
                      ),
                    ),
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Room ID Badge (Icon-only on narrow screens with full tooltip/semantics to prevent overflow)
                      Tooltip(
                        message: session.roomId != null ? formatDeviceId(session.roomId!) : 'Eir',
                        child: Semantics(
                          label: session.roomId != null ? formatDeviceId(session.roomId!) : 'Eir',
                          child: LiquidGlassTag(
                            color: tc.primary.withValues(alpha: 0.16),
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrow ? 6 : 8,
                              vertical: isShort ? 3 : 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.theater_comedy_rounded, size: isNarrow ? 13 : 14, color: tc.primary),
                                if (!isNarrow) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    session.roomId != null
                                        ? formatDeviceId(session.roomId!)
                                        : 'Eir',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      color: tc.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isNarrow ? 4 : 6),

                      // Role Pill
                      LiquidGlassTag(
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 5 : 8,
                          vertical: isShort ? 3 : 4,
                        ),
                        color: isOwner
                            ? tc.warning.withValues(alpha: 0.18)
                            : (isHostOrAdmin
                                ? tc.primary.withValues(alpha: 0.16)
                                : tc.inputBackground),
                        child: Text(
                          isOwner
                              ? i18n.roleOwner
                              : (isHostOrAdmin ? i18n.roleAdmin : i18n.roleMember),
                          style: TextStyle(
                            fontSize: isNarrow ? 9.5 : 10.5,
                            fontWeight: FontWeight.w700,
                            color: isOwner
                                ? tc.warning
                                : (isHostOrAdmin ? tc.primary : tc.textSecondary),
                          ),
                        ),
                      ),
                      SizedBox(width: isNarrow ? 4 : 6),

                      // Connection State Indicator
                      _buildConnectionIndicator(context, session.connectionState, isNarrow: isNarrow),
                    ],
                  ),
                  actions: [
                    // Owner Disband Room Button
                    if (isOwner) ...[
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
                                Icon(Icons.power_settings_new_rounded, size: 14, color: tc.error),
                                if (!isNarrow) ...[
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
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isNarrow ? 4 : 6),
                    ],

                    // Short Room Code Badge
                    if (session.roomCode != null) ...[
                      Tooltip(
                        message: i18n.copyRoomCode,
                        child: GestureDetector(
                          onTap: () async {
                            final code = session.roomCode!;
                            await Clipboard.setData(ClipboardData(text: code));
                            if (!context.mounted) return;
                            showLiquidGlassSnackBar(
                              context,
                              owner: this,
                              message: '${i18n.roomCodeCopied}: $code',
                              icon: Icons.check_circle_outline_rounded,
                              iconColor: tc.primary,
                              duration: const Duration(seconds: 2),
                            );
                          },
                          child: Container(
                            height: isShort ? 30 : 34,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: tc.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: tc.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tag_rounded,
                                    size: 14, color: tc.primary),
                                const SizedBox(width: 4),
                                Text(
                                  session.roomCode!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                    color: tc.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isNarrow ? 4 : 6),
                    ],

                    // Copy Invite Payload
                    if (session.inviteText != null) ...[
                      Tooltip(
                        message: i18n.copyInvite,
                        child: Semantics(
                          button: true,
                          label: i18n.copyInvite,
                          child: LiquidGlassActionButton(
                            key: const ValueKey('cinema-copy-invite-btn'),
                            height: isShort ? 30 : 34,
                            onTap: () => _copyInviteText(context),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.copy_rounded, size: 14),
                                if (!isNarrow) ...[
                                  const SizedBox(width: 5),
                                  Text(i18n.copyInvite, style: const TextStyle(fontSize: 11.5)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isNarrow ? 4 : 6),
                    ],

                    // Settings Dialog Trigger
                    Semantics(
                      button: true,
                      enabled: true,
                      label: i18n.settingsTitle,
                      child: Tooltip(
                        message: i18n.settingsTitle,
                        child: GlassIconButton(
                          key: const ValueKey('cinema-settings-btn'),
                          icon: Icon(Icons.settings_outlined, size: isShort ? 16 : 18, color: tc.textPrimary),
                          onPressed: () => SettingsDialog.show(context, session: session),
                        ),
                      ),
                    ),
                    SizedBox(width: isNarrow ? 4 : 12),
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
                          if (session.connectionState == RoomConnectionState.reconnecting)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildReconnectingBanner(context),
                            ),
                          if (session.connectionState == RoomConnectionState.disconnected)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildDisconnectedBanner(context),
                            ),

                          // Main Video Player & Control Stage (Preserves proportions and guarantees controls never get squished)
                          SizedBox(
                            height: (screenWidth * 9 / 16).clamp(165.0, 220.0),
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

                          const SizedBox(height: 10),

                          // Bottom Dock (Tabs: Playlist / Peers / Info) (Dedicated height so items are fully visible & scrollable)
                          SizedBox(
                            height: 240,
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
                          child: session.connectionState == RoomConnectionState.reconnecting
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildReconnectingBanner(context),
                                )
                              : const SizedBox.shrink(),
                        ),

                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: session.connectionState == RoomConnectionState.disconnected
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildDisconnectedBanner(context),
                                )
                              : const SizedBox.shrink(),
                        ),

                        // Main Video Player & Control Stage
                        Expanded(
                          flex: 1,
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

                        const SizedBox(height: 12),

                        // Bottom Dock (Tabs: Playlist / Peers / Info)
                        Expanded(
                          flex: 1,
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
      );
    },
  );
}

  Widget _buildConnectionIndicator(BuildContext context, RoomConnectionState state, {bool isNarrow = false}) {
    final tc = ThemeColors.of(context);
    final i18n = AppI18n.of(context);

    Color dotColor;
    String label;

    switch (state) {
      case RoomConnectionState.connected:
        dotColor = tc.success;
        label = i18n.stateConnected;
        break;
      case RoomConnectionState.connecting:
        dotColor = tc.primary;
        label = i18n.stateConnecting;
        break;
      case RoomConnectionState.reconnecting:
        dotColor = tc.warning;
        label = i18n.stateReconnecting;
        break;
      case RoomConnectionState.disconnected:
        dotColor = tc.error;
        label = i18n.stateDisconnected;
        break;
    }

    final tag = LiquidGlassTag(
      color: dotColor.withValues(alpha: 0.14),
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 6 : 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          if (!isNarrow) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: dotColor,
              ),
            ),
          ],
        ],
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
      child: Semantics(
        label: label,
        child: tag,
      ),
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
              style: TextStyle(fontSize: 12.5, color: tc.error, fontWeight: FontWeight.w500),
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
              style: TextStyle(fontSize: 12.5, color: tc.warning, fontWeight: FontWeight.w500),
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
    final displayPos = (_draggingSliderValue != null && mediaDuration.inMilliseconds > 0)
        ? Duration(milliseconds: (_draggingSliderValue! * mediaDuration.inMilliseconds).round())
        : currentPos;
    final displayRatio = (_draggingSliderValue ?? progressRatio).clamp(0.0, 1.0);

    return GlassContainer.card(
      surfaceStyle: GlassSurfaceStyle.solid,
      color: Colors.black,
      shape: LiquidRoundedSuperellipse(borderRadius: isShort ? 16 : 22),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isShort ? 16 : 22),
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

            // Simulated Brightness Dimmer Overlay
            if (_brightness < 1.0)
              IgnorePointer(
                child: Container(
                  color: Colors.black
                      .withValues(alpha: (1.0 - _brightness) * 0.75),
                ),
              ),

            // 2. Gesture Detection Layer (Double-tap skip, Drag brightness/volume)
            Positioned.fill(
              child: Row(
                children: [
                  // Left half: Double-tap rewind 10s, vertical drag brightness
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTap:
                          isHostOrAdmin ? () => _seekRelative(-10) : null,
                      onVerticalDragUpdate: _isLocked
                          ? null
                          : (d) {
                              final delta = -d.primaryDelta! / 200.0;
                              setState(() {
                                _brightness =
                                    (_brightness + delta).clamp(0.1, 1.0);
                              });
                              _showGestureHud('brightness');
                            },
                      child: const SizedBox.expand(),
                    ),
                  ),
                  // Right half: Double-tap forward 10s, vertical drag volume
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onDoubleTap:
                          isHostOrAdmin ? () => _seekRelative(10) : null,
                      onVerticalDragUpdate: _isLocked
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
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),

            // Buffering Indicator
            if (isBuffering && widget.session.lastErrorCode != 'source_offline')
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                              strokeWidth: 2, color: tc.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          i18n.bufferingLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600),
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
                      Icon(Icons.cloud_off_rounded, size: 40, color: tc.warning),
                      const SizedBox(height: 12),
                      Text(
                        i18n.sourceOfflineTitle,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        i18n.sourceOfflineDesc,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ),

            // Floating Center Gesture HUD (Brightness, Volume, Skip Indicator)
            if (_gestureHudType != null)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
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
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(tc.primary),
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
                        showLiquidGlassSnackBar(
                          context,
                          owner: this,
                          message: _isLocked
                              ? i18n.screenLocked
                              : i18n.screenUnlocked,
                          icon: _isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          duration: const Duration(seconds: 1),
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
                                Icon(Icons.movie_rounded,
                                    size: isShort ? 12 : 14,
                                    color: Colors.white70),
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
                      if (!isHostOrAdmin)
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
                                fontSize: isShort ? 9.5 : 11),
                          ),
                        ),
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
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: tc.primary.withValues(alpha: 0.6)),
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
                      isShort ? 8 : 20,
                      isShort ? 10 : 16,
                      isShort ? 6 : 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Timeline Slider & Timestamps
                        Row(
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatDuration(displayPos),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isShort ? 10.5 : 11.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                if (syncTargetPos > Duration.zero &&
                                    (syncTargetPos - displayPos).abs() >
                                        const Duration(seconds: 1) &&
                                    _draggingSliderValue == null)
                                  Text(
                                    '${i18n.syncTargetLabel}: ${formatDuration(syncTargetPos)}',
                                    style: TextStyle(
                                      color: tc.primary,
                                      fontSize: isShort ? 8.5 : 9.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Material(
                                type: MaterialType.transparency,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: tc.primary,
                                    inactiveTrackColor: Colors.white24,
                                    secondaryActiveTrackColor:
                                        tc.primary.withValues(alpha: 0.35),
                                    thumbColor: Colors.white,
                                    thumbShape: RoundSliderThumbShape(
                                        enabledThumbRadius:
                                            isShort ? 4.5 : 6),
                                    overlayShape: RoundSliderOverlayShape(
                                        overlayRadius: isShort ? 9 : 12),
                                    trackHeight: isShort ? 2.5 : 3.5,
                                  ),
                                  child: Semantics(
                                    slider: true,
                                    enabled: isHostOrAdmin &&
                                        mediaDuration.inMilliseconds > 0,
                                    label: i18n.timelineLabel,
                                    value:
                                        '${formatDuration(displayPos)} / ${formatDuration(mediaDuration)} (${(displayRatio * 100).round()}%)',
                                    hint: !isHostOrAdmin
                                        ? i18n.readOnlyControlTooltip
                                        : (mediaDuration.inMilliseconds <= 0
                                            ? i18n.timelineEmptyHint
                                            : (syncTargetPos > Duration.zero &&
                                                    (syncTargetPos - displayPos)
                                                            .abs() >
                                                        const Duration(
                                                            seconds: 1)
                                                ? '${i18n.syncTargetLabel}: ${formatDuration(syncTargetPos)}. ${i18n.timelineSeekHint}'
                                                : i18n.timelineSeekHint)),
                                    child: Slider(
                                      key: const ValueKey(
                                          'cinema-timeline-slider'),
                                      value: displayRatio,
                                      secondaryTrackValue:
                                          (syncTargetRatio > 0.0 &&
                                                  syncTargetRatio !=
                                                      displayRatio &&
                                                  _draggingSliderValue == null)
                                              ? syncTargetRatio
                                              : null,
                                      onChanged: (isHostOrAdmin &&
                                              mediaDuration.inMilliseconds > 0)
                                          ? (val) {
                                              _restartControlsTimer();
                                              setState(() =>
                                                  _draggingSliderValue =
                                                      val.clamp(0.0, 1.0));
                                            }
                                          : null,
                                      onChangeEnd: (isHostOrAdmin &&
                                              mediaDuration.inMilliseconds > 0)
                                          ? (val) async {
                                              _restartControlsTimer();
                                              final clamped =
                                                  val.clamp(0.0, 1.0);
                                              final targetMs = (clamped *
                                                      mediaDuration
                                                          .inMilliseconds)
                                                  .round();
                                              setState(() =>
                                                  _draggingSliderValue = null);
                                              try {
                                                await widget.session.seek(
                                                    Duration(
                                                        milliseconds:
                                                            targetMs));
                                              } catch (_) {}
                                            }
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatDuration(mediaDuration),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: isShort ? 10.5 : 11.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
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
                              constraints:
                                  isShort ? const BoxConstraints() : null,
                              icon: Icon(
                                Icons.replay_10_rounded,
                                color:
                                    isHostOrAdmin ? Colors.white70 : Colors.white24,
                                size: isShort ? 20 : 22,
                              ),
                              onPressed: isHostOrAdmin
                                  ? () => _seekRelative(-10)
                                  : null,
                              tooltip: i18n.rewind10,
                            ),

                            // Shared Play / Pause Toggle (Host/Admin only)
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
                                  key: const ValueKey('cinema-play-pause-btn'),
                                  padding: isShort
                                      ? const EdgeInsets.all(4)
                                      : const EdgeInsets.all(8),
                                  constraints:
                                      isShort ? const BoxConstraints() : null,
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_circle_filled_rounded
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

                            // Forward 10s button
                            IconButton(
                              key: const ValueKey('cinema-forward-10-btn'),
                              padding: isShort
                                  ? const EdgeInsets.all(4)
                                  : const EdgeInsets.all(6),
                              constraints:
                                  isShort ? const BoxConstraints() : null,
                              icon: Icon(
                                Icons.forward_10_rounded,
                                color:
                                    isHostOrAdmin ? Colors.white70 : Colors.white24,
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
                                  key: const ValueKey('cinema-volume-mute-btn'),
                                  padding: isShort
                                      ? const EdgeInsets.all(4)
                                      : const EdgeInsets.all(8),
                                  constraints:
                                      isShort ? const BoxConstraints() : null,
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
                                        _isMuted ? 0.0 : _volume * 100.0);
                                  },
                                ),
                              ),
                            ),

                            // Playback Rate Selector (Host/Admin)
                            Semantics(
                              button: true,
                              enabled: isHostOrAdmin,
                              label:
                                  '${i18n.playbackRate}: ${widget.session.playback.rate}x',
                              hint: isHostOrAdmin
                                  ? i18n.rateChangeHint
                                  : i18n.readOnlyControlTooltip,
                              child: Tooltip(
                                message: isHostOrAdmin
                                    ? '${i18n.playbackRate} (${widget.session.playback.rate}x)'
                                    : '${i18n.playbackRate} (${i18n.readOnlyControlTooltip})',
                                child: GestureDetector(
                                  key: const ValueKey(
                                      'cinema-playback-rate-btn'),
                                  onTap: isHostOrAdmin
                                      ? () {
                                          _restartControlsTimer();
                                          _cyclePlaybackRate();
                                        }
                                      : null,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isShort ? 6 : 8,
                                      vertical: isShort ? 3 : 4,
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

                            const Spacer(),

                            // Aspect Ratio Toggle
                            Tooltip(
                              message:
                                  '${i18n.aspectRatio}: ${_aspectFit == BoxFit.contain ? "适应" : (_aspectFit == BoxFit.cover ? "铺满" : "拉伸")}',
                              child: IconButton(
                                key: const ValueKey('cinema-aspect-ratio-btn'),
                                padding: isShort
                                    ? const EdgeInsets.all(4)
                                    : const EdgeInsets.all(8),
                                constraints:
                                    isShort ? const BoxConstraints() : null,
                                icon: Icon(
                                  Icons.aspect_ratio_rounded,
                                  color: Colors.white70,
                                  size: isShort ? 18 : 20,
                                ),
                                onPressed: _cycleAspectRatio,
                              ),
                            ),

                            // Fullscreen Toggle (Local)
                            Semantics(
                              button: true,
                              enabled: true,
                              label: _isFullscreen
                                  ? i18n.exitFullscreenTooltip
                                  : i18n.fullscreenTooltip,
                              child: Tooltip(
                                message: _isFullscreen
                                    ? i18n.exitFullscreenTooltip
                                    : i18n.fullscreenTooltip,
                                child: IconButton(
                                  key: const ValueKey('cinema-fullscreen-btn'),
                                  padding: isShort
                                      ? const EdgeInsets.all(4)
                                      : const EdgeInsets.all(8),
                                  constraints:
                                      isShort ? const BoxConstraints() : null,
                                  icon: Icon(
                                    _isFullscreen
                                        ? Icons.fullscreen_exit_rounded
                                        : Icons.fullscreen_rounded,
                                    color: Colors.white70,
                                    size: isShort ? 18 : 22,
                                  ),
                                  onPressed: () {
                                    _restartControlsTimer();
                                    setState(
                                        () => _isFullscreen = !_isFullscreen);
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

  Widget _buildPlaylistTab(BuildContext context, bool isHostOrAdmin, {bool isShort = false}) {
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
                      Text(i18n.addMedia, style: TextStyle(fontSize: isShort ? 11 : 11.5, fontWeight: FontWeight.w600)),
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_collection_outlined, size: isShort ? 28 : 32, color: tc.textTertiary),
                        SizedBox(height: isShort ? 4 : 6),
                        Text(
                          i18n.playlistEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: isShort ? 11 : 12, color: tc.textTertiary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  cacheExtent: 400,
                  itemCount: playlist.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = playlist[index];
                    final isCurrent = item.itemId == currentItemId;

                    return Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? tc.primary.withValues(alpha: 0.12)
                            : tc.inputBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent ? tc.primary.withValues(alpha: 0.4) : Colors.transparent,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            item.sourceType == 'local' ? Icons.folder_rounded : Icons.link_rounded,
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
                                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                    color: isCurrent ? tc.primary : tc.textPrimary,
                                  ),
                                ),
                                if (item.url != null)
                                  Text(
                                    item.url!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10.5, color: tc.textTertiary),
                                  ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tc.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                i18n.nowPlayingBadge,
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          if (isHostOrAdmin) ...[
                            // Reorder Up
                            Semantics(
                              button: true,
                              enabled: index > 0,
                              label: '${i18n.moveUp}: ${item.title}',
                              child: IconButton(
                                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                                tooltip: i18n.moveUp,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: index > 0
                                    ? () => widget.session.reorderItem(item.itemId, index - 1)
                                    : null,
                              ),
                            ),
                            // Reorder Down
                            Semantics(
                              button: true,
                              enabled: index < playlist.length - 1,
                              label: '${i18n.moveDown}: ${item.title}',
                              child: IconButton(
                                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                                tooltip: i18n.moveDown,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: index < playlist.length - 1
                                    ? () => widget.session.reorderItem(item.itemId, index + 1)
                                    : null,
                              ),
                            ),
                            // Replace item
                            Semantics(
                              button: true,
                              enabled: true,
                              label: '${i18n.replaceMedia}: ${item.title}',
                              child: IconButton(
                                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                                tooltip: i18n.replaceMedia,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () => _showReplaceMediaDialog(context, item),
                              ),
                            ),
                            // Switch item (if not current)
                            if (!isCurrent)
                              Semantics(
                                button: true,
                                enabled: true,
                                label: '${i18n.switchMedia}: ${item.title}',
                                child: IconButton(
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  tooltip: i18n.switchMedia,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  onPressed: () => widget.session.switchItem(item.itemId),
                                ),
                              ),
                            // Remove item
                            Semantics(
                              button: true,
                              enabled: true,
                              label: '${i18n.removeMedia}: ${item.title}',
                              child: IconButton(
                                icon: Icon(Icons.delete_outline_rounded, size: 16, color: tc.error),
                                tooltip: i18n.removeMedia,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () => widget.session.removeItem(item.itemId),
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
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tc.textPrimary),
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

              return Container(
                decoration: BoxDecoration(
                  color: tc.inputBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(
                          avatarKey: member.avatar.isNotEmpty
                              ? member.avatar
                              : (isMe ? AppSettings.instance.avatar : null),
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
                                border: Border.all(color: tc.background, width: 1.5),
                              ),
                              child: Icon(
                                isMemberOwner ? Icons.star_rounded : Icons.shield_rounded,
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
                                  style: TextStyle(fontSize: 11, color: tc.primary, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                          Text(
                            formatDeviceId(member.deviceId),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: tc.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // F08: Member Playback Telemetry (Strict truthfulness: buffering=false != synced)
                          Builder(
                            builder: (context) {
                              final telemetry = widget.session.memberTelemetry[member.deviceId];
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
                                  key: ValueKey('member-telemetry-${member.deviceId}'),
                                  child: telemetry != null
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              telemetry.buffering
                                                  ? Icons.hourglass_top_rounded
                                                  : Icons.play_circle_outline_rounded,
                                              size: 11,
                                              color: telemetry.buffering ? tc.warning : tc.primary,
                                            ),
                                            const SizedBox(width: 3.5),
                                            Text(
                                              formatDuration(Duration(milliseconds: telemetry.positionMs)),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                                color: tc.textSecondary,
                                              ),
                                            ),
                                            if (telemetry.buffering) ...[
                                              const SizedBox(width: 5),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                                decoration: BoxDecoration(
                                                  color: tc.warning.withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(3),
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
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
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
                            : (isMemberAdmin ? i18n.roleAdmin : i18n.roleMember),
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
                      Semantics(
                        button: true,
                        enabled: true,
                        label: isMemberAdmin
                            ? '${i18n.revokeAdmin}: ${member.displayName.isNotEmpty ? member.displayName : formatDeviceId(member.deviceId)}'
                            : '${i18n.grantAdmin}: ${member.displayName.isNotEmpty ? member.displayName : formatDeviceId(member.deviceId)}',
                        child: LiquidGlassActionButton(
                          key: ValueKey('member-acl-${member.deviceId}'),
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
          _buildInfoRow(context, i18n.currentSeqLabel, session.playback.seq.toString()),
          _buildInfoRow(context, i18n.localPlaybackPos, formatDuration(session.player.state.position)),
          if (session.playback.position > Duration.zero)
            _buildInfoRow(context, i18n.syncTargetLabel, formatDuration(session.playback.position)),
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

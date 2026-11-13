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

/// Screen Share Lobby View - First-class bottom navigation destination
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
  bool _isConnecting = false;
  String? _errorMessage;

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _codeController.dispose();
    super.dispose();
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
      // If not already in a room, create a dedicated cast room
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

  Future<void> _handleJoinCast(String code) async {
    final cleanCode = code.trim();
    if (cleanCode.length != 6) {
      setState(() => _errorMessage = '请输入 6 位有效投屏码');
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // Connect to room if not already in it
      if (widget.session.roomCode != cleanCode) {
        await widget.session.joinRoomByCode(cleanCode);
      }

      final success = await _service.startViewing(castCode: cleanCode);
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
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      final text = data!.text!.replaceAll(RegExp(r'\D'), '');
      if (text.length >= 6) {
        _codeController.text = text.substring(0, 6);
      } else {
        _codeController.text = text;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tc = ThemeColors.of(context);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 18 : 36,
        vertical: isMobile ? 16 : 28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Section
              _buildHeaderSection(context, i18n, tc),
              const SizedBox(height: 20),

              // Active Session Pill if broadcasting/viewing
              if (_service.isActive) ...[
                _buildActiveSessionBanner(context, i18n, tc),
                const SizedBox(height: 16),
              ],

              // Error Notice
              if (_errorMessage != null) ...[
                _buildErrorBanner(context, _errorMessage!, tc),
                const SizedBox(height: 16),
              ],

              // 2. Dual Action Section (Start Cast vs Join Cast)
              _buildActionCards(context, i18n, tc, isMobile),
              const SizedBox(height: 24),

              // 3. Feature Highlights Bento Grid
              _buildFeatureBadges(context, i18n, tc, isMobile),
              const SizedBox(height: 24),

              // 4. Recent Cast History
              _buildRecentCasts(context, i18n, tc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: tc.cardBackground.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tc.glassBorderSubtle.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tc.primary, tc.primary.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: tc.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.screen_share_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      i18n.screenShareTabTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: tc.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 0.8),
                      ),
                      child: const Text(
                        '60 FPS',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  i18n.screenShareTabSubtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: tc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionBanner(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tc.primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.live_tv_rounded, color: tc.primary, size: 22),
          const SizedBox(width: 12),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => ScreenShareLiveView.launch(context, session: widget.session),
            child: const Text('返回全屏视窗', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message, ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 1),
      ),
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
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCards(BuildContext context, AppI18n i18n, ThemeColors tc, bool isMobile) {
    final startCard = _buildStartCastCard(context, i18n, tc);
    final joinCard = _buildJoinCastCard(context, i18n, tc);

    if (isMobile) {
      return Column(
        children: [
          startCard,
          const SizedBox(height: 14),
          joinCard,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: startCard),
        const SizedBox(width: 16),
        Expanded(child: joinCard),
      ],
    );
  }

  Widget _buildStartCastCard(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tc.glassBorderSubtle.withValues(alpha: 0.7), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tc.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.broadcast_on_personal_rounded, color: tc.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.startScreenShare,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tc.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '捕获窗口或手机全屏推流',
                    style: TextStyle(fontSize: 12, color: tc.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '支持选择特定软件窗口（如抖音、浏览器）或手机录屏推流，系统音频立体声伴奏同步直传。',
            style: TextStyle(
              fontSize: 12.5,
              color: tc.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('start-screen-share-btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tc.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(
                _isConnecting ? i18n.screenShareConnecting : i18n.startScreenShare,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              onPressed: _isConnecting ? null : _handleStartCast,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinCastCard(BuildContext context, AppI18n i18n, ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tc.glassBorderSubtle.withValues(alpha: 0.7), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tv_rounded, color: Colors.teal, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i18n.joinScreenShare,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tc.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    i18n.enterCastCodeHint,
                    style: TextStyle(fontSize: 12, color: tc.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 6-digit Code Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: tc.inputBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tc.glassBorderSubtle.withValues(alpha: 0.8), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.tag_rounded, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('cast-code-input'),
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: tc.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '6 位投屏码',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        letterSpacing: 0,
                        fontWeight: FontWeight.normal,
                        color: tc.textSecondary,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (val) => _handleJoinCast(val),
                  ),
                ),
                IconButton(
                  tooltip: '粘贴',
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  color: tc.textSecondary,
                  onPressed: _pasteFromClipboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('join-cast-btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.login_rounded, size: 20),
              label: Text(
                _isConnecting ? '正在连接...' : i18n.joinCast,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              onPressed: _isConnecting ? null : () => _handleJoinCast(_codeController.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadges(BuildContext context, AppI18n i18n, ThemeColors tc, bool isMobile) {
    final features = [
      (Icons.speed_rounded, Colors.amber, '60 FPS 极速推流', '画面帧率优先，专为刷抖音短视频优化'),
      (Icons.volume_up_rounded, Colors.indigoAccent, '系统伴音直传', 'Android 10+ 与 PC 原生内录，伴奏无杂音'),
      (Icons.window_rounded, Colors.blueAccent, '精准窗口捕获', '桌面端可单选某个应用窗口，隐私不外泄'),
      (Icons.record_voice_over_rounded, Colors.teal, '实时双向对讲', '看短视频的同时随时开麦边看边聊'),
    ];

    return GridView.count(
      crossAxisCount: isMobile ? 1 : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: isMobile ? 3.6 : 3.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: features.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: tc.cardBackground.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tc.glassBorderSubtle.withValues(alpha: 0.5), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: f.$2.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(f.$1, color: f.$2, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      f.$3,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tc.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      f.$4,
                      style: TextStyle(
                        fontSize: 11,
                        color: tc.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentCasts(BuildContext context, AppI18n i18n, ThemeColors tc) {
    final recentRooms = RoomHistoryService.recentRoomsNotifier.value;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tc.cardBackground.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tc.glassBorderSubtle.withValues(alpha: 0.6), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: tc.textSecondary),
              const SizedBox(width: 8),
              Text(
                i18n.recentCasts,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tc.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recentRooms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  i18n.noRecentCasts,
                  style: TextStyle(fontSize: 12.5, color: tc.textSecondary),
                ),
              ),
            )
          else
            ...recentRooms.take(3).map((r) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    _codeController.text = r.roomCode;
                    _handleJoinCast(r.roomCode);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tc.inputBackground.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tag_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          r.roomCode,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                            color: tc.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            r.title,
                            style: TextStyle(fontSize: 12, color: tc.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: tc.textSecondary),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

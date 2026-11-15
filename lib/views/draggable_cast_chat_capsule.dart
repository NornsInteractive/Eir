import 'dart:async';
import 'package:flutter/material.dart';
import '../apple_glass.dart';
import '../core/room_session.dart';

/// Draggable Floating Chat Capsule for Screen Sharing (Broadcaster & Viewer)
/// Allows user to move a chat bubble anywhere on screen and tap to chat.
class DraggableCastChatCapsule extends StatefulWidget {
  final RoomSession session;

  const DraggableCastChatCapsule({super.key, required this.session});

  @override
  State<DraggableCastChatCapsule> createState() =>
      _DraggableCastChatCapsuleState();
}

class _DraggableCastChatCapsuleState extends State<DraggableCastChatCapsule>
    with SingleTickerProviderStateMixin {
  Offset _offset = const Offset(16, 120);
  bool _initializedOffset = false;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  bool _isTucked = false;
  Timer? _tuckTimer;

  ScreenShareService get _service => widget.session.screenShareService;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        setState(() => _offset = _snapAnimation!.value);
      }
    });
    _resetTuckTimer();
  }

  void _resetTuckTimer() {
    _tuckTimer?.cancel();
    if (_isTucked) {
      setState(() => _isTucked = false);
    }
    _tuckTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _service.unreadCount == 0) {
        setState(() => _isTucked = true);
      }
    });
  }

  void _snapToNearestEdge(Size screenSize) {
    _resetTuckTimer();
    final isLeft = (_offset.dx + 44) < screenSize.width / 2;
    final targetX = isLeft ? 12.0 : (screenSize.width - 96.0);
    final targetY = _offset.dy.clamp(60.0, screenSize.height - 120.0);
    final target = Offset(targetX, targetY);

    _snapAnimation = Tween<Offset>(
      begin: _offset,
      end: target,
    ).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic));

    _snapController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _tuckTimer?.cancel();
    _snapController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _openChatSheet(BuildContext context) {
    _service.markMessagesAsRead();
    final tc = ThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final mediaQuery = MediaQuery.of(sheetContext);
            final keyboardHeight = mediaQuery.viewInsets.bottom;
            final sheetHeight = (mediaQuery.size.height * 0.65).clamp(
              380.0,
              680.0,
            );

            return Padding(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: GlassContainer.card(
                surfaceStyle: GlassSurfaceStyle.solid,
                color: isDark
                    ? const Color(0xFF141721)
                    : const Color(0xFFF9FAFC),
                shape: const LiquidRoundedSuperellipse(borderRadius: 26),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SizedBox(
                  height: sheetHeight,
                  child: Column(
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: tc.textTertiary.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: tc.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.forum_rounded,
                              size: 18,
                              color: tc.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '投屏实时互动',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: tc.textPrimary,
                                  ),
                                ),
                                Text(
                                  _service.isBroadcasting
                                      ? '正在向观看方发送消息'
                                      : '正在向投屏方发送消息',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: tc.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: tc.textSecondary,
                            ),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      Divider(color: tc.glassBorder, height: 1),

                      // Emoji Quick Reactions
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                [
                                  '❤️',
                                  '👍',
                                  '👏',
                                  '🚀',
                                  '🔥',
                                  '🎉',
                                  '😂',
                                  '✨',
                                ].map((emoji) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: InkWell(
                                      onTap: () {
                                        _service.sendReaction(emoji);
                                        Navigator.of(sheetContext).pop();
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tc.inputBackground,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: tc.glassBorder,
                                          ),
                                        ),
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                      ),

                      // Messages List
                      Expanded(
                        child: AnimatedBuilder(
                          animation: _service,
                          builder: (context, _) {
                            final messages = _service.messages;
                            if (messages.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 36,
                                      color: tc.textTertiary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '暂无消息，发送一条打个招呼吧',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: tc.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(
                                  _scrollController.position.maxScrollExtent,
                                );
                              }
                            });

                            return ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final msg = messages[index];
                                final isSelf = msg.isSelf;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    mainAxisAlignment: isSelf
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (!isSelf) ...[
                                        CircleAvatar(
                                          radius: 13,
                                          backgroundColor: tc.primary
                                              .withValues(alpha: 0.2),
                                          child: Text(
                                            (msg.senderName.isNotEmpty
                                                    ? msg.senderName[0]
                                                    : '?')
                                                .toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: tc.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: mediaQuery.size.width * 0.7,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 9,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelf
                                                ? tc.primary
                                                : tc.inputBackground,
                                            borderRadius:
                                                BorderRadius.circular(
                                                  16,
                                                ).copyWith(
                                                  bottomRight: isSelf
                                                      ? Radius.zero
                                                      : const Radius.circular(
                                                          16,
                                                        ),
                                                  bottomLeft: !isSelf
                                                      ? Radius.zero
                                                      : const Radius.circular(
                                                          16,
                                                        ),
                                                ),
                                            border: Border.all(
                                              color: isSelf
                                                  ? Colors.transparent
                                                  : tc.glassBorder,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: isSelf
                                                ? CrossAxisAlignment.end
                                                : CrossAxisAlignment.start,
                                            children: [
                                              if (!isSelf &&
                                                  msg.senderName.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 2,
                                                      ),
                                                  child: Text(
                                                    msg.senderName,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: tc.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              Text(
                                                msg.text,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  color: isSelf
                                                      ? Colors.white
                                                      : tc.textPrimary,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),

                      // Input Bar
                      Container(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: GlassTextField(
                                controller: _textController,
                                focusNode: _inputFocusNode,
                                placeholder: '发送即时消息...',
                                height: 42,
                                surfaceStyle: GlassSurfaceStyle.solid,
                                color: tc.inputBackground,
                                onSubmitted: (text) async {
                                  if (text.trim().isNotEmpty) {
                                    await _service.sendChatMessage(text.trim());
                                    _textController.clear();
                                    setSheetState(() {});
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            LiquidGlassActionButton(
                              isPrimary: true,
                              height: 42,
                              width: 58,
                              onTap: () async {
                                final text = _textController.text.trim();
                                if (text.isNotEmpty) {
                                  await _service.sendChatMessage(text);
                                  _textController.clear();
                                  setSheetState(() {});
                                }
                              },
                              child: const Icon(
                                Icons.send_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = ThemeColors.of(context);
    final screenSize = MediaQuery.of(context).size;

    if (!_initializedOffset) {
      _initializedOffset = true;
      _offset = Offset(screenSize.width - 96, screenSize.height - 180);
    }

    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final unread = _service.unreadCount;

        return Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: GestureDetector(
            onPanStart: (_) {
              _snapController.stop();
              _resetTuckTimer();
            },
            onPanUpdate: (details) {
              setState(() {
                _offset = Offset(
                  (_offset.dx + details.delta.dx).clamp(4.0, screenSize.width - 90.0),
                  (_offset.dy + details.delta.dy).clamp(50.0, screenSize.height - 90.0),
                );
              });
            },
            onPanEnd: (_) => _snapToNearestEdge(screenSize),
            onTap: () {
              _resetTuckTimer();
              _openChatSheet(context);
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _isTucked ? 0.65 : 1.0,
              child: GlassContainer.card(
                surfaceStyle: GlassSurfaceStyle.solid,
                color: tc.primary.withValues(alpha: 0.88),
                shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chat_bubble_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '聊天',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
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
    );
  }
}

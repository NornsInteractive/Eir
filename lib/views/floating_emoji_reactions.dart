import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Representation of an active floating reaction emoji particle
class FloatingEmojiData {
  final String id;
  final String emoji;
  final double startX;

  FloatingEmojiData({
    required this.id,
    required this.emoji,
    required this.startX,
  });
}

/// Animated rising, floating, and fading emoji particle
class FloatingEmojiWidget extends StatefulWidget {
  final String emoji;
  final double startX;

  const FloatingEmojiWidget({
    super.key,
    required this.emoji,
    required this.startX,
  });

  @override
  State<FloatingEmojiWidget> createState() => _FloatingEmojiWidgetState();
}

class _FloatingEmojiWidgetState extends State<FloatingEmojiWidget>
    with SingleTickerProviderStateMixin {
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
          right: (MediaQuery.of(context).size.width * (1.0 - widget.startX)) +
              xWobble,
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

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/room_session.dart';

class DanmakuOverlay extends StatefulWidget {
  final Stream<DanmakuMessage>? danmakuStream;
  final bool enabled;

  const DanmakuOverlay({
    super.key,
    required this.danmakuStream,
    this.enabled = true,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _ActiveDanmaku {
  _ActiveDanmaku({
    required this.id,
    required this.text,
    required this.sender,
    required this.track,
    required this.color,
    required this.speed,
  });

  final String id;
  final String text;
  final String sender;
  final int track;
  final Color color;
  final double speed;
  double x = 1.1; // relative coordinate 1.1 (right) -> -0.5 (left)
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  StreamSubscription<DanmakuMessage>? _streamSub;
  final List<_ActiveDanmaku> _items = [];
  final Random _rng = Random();
  static const int _numTracks = 4;
  final List<double> _lastTrackX = List.filled(_numTracks, -1.0);

  final List<Color> _palette = const [
    Colors.white,
    Colors.white,
    Colors.white,
    Color(0xFFE0F7FA),
    Color(0xFFFFF9C4),
    Color(0xFFFFE0B2),
    Color(0xFFF8BBD0),
    Color(0xFFE1BEE7),
  ];

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
    _subscribe();
  }

  void _startTickerIfNeeded() {
    if (widget.enabled && _items.isNotEmpty && !_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _subscribe() {
    _streamSub?.cancel();
    _streamSub = widget.danmakuStream?.listen((msg) {
      if (!mounted || !widget.enabled) return;
      _spawnDanmaku(msg);
    });
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.danmakuStream != widget.danmakuStream) {
      _subscribe();
    }
    if (!widget.enabled) {
      _ticker.stop();
    } else {
      _startTickerIfNeeded();
    }
  }

  void _spawnDanmaku(DanmakuMessage msg) {
    // Pick the track whose rightmost danmaku has moved farthest to the left
    int bestTrack = 0;
    double minX = 999.0;
    for (int t = 0; t < _numTracks; t++) {
      if (_lastTrackX[t] < minX) {
        minX = _lastTrackX[t];
        bestTrack = t;
      }
    }

    final speed = 0.0035 + (_rng.nextDouble() * 0.0015);
    final color = _palette[_rng.nextInt(_palette.length)];
    final item = _ActiveDanmaku(
      id: msg.id,
      text: msg.text,
      sender: msg.sender,
      track: bestTrack,
      color: color,
      speed: speed,
    );
    _lastTrackX[bestTrack] = 1.1;
    setState(() {
      _items.add(item);
    });
    _startTickerIfNeeded();
  }

  void _tick() {
    if (!mounted || !widget.enabled || _items.isEmpty) {
      _ticker.stop();
      return;
    }
    bool needsSetState = false;
    for (int t = 0; t < _numTracks; t++) {
      _lastTrackX[t] = -1.0;
    }

    _items.removeWhere((item) {
      item.x -= item.speed;
      if (item.x > _lastTrackX[item.track]) {
        _lastTrackX[item.track] = item.x;
      }
      needsSetState = true;
      return item.x < -0.6; // off left screen
    });

    if (_items.isEmpty) {
      _ticker.stop();
    }
    if (needsSetState) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _streamSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _items.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final trackHeight = (h * 0.35) / _numTracks;

        return Stack(
          children: _items.map((item) {
            final left = item.x * w;
            final top = 12.0 + (item.track * trackHeight);

            return Positioned(
              left: left,
              top: top,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.text,
                  style: TextStyle(
                    color: item.color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    shadows: const [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 4,
                        offset: Offset(1, 1),
                      ),
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(-1, -1),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

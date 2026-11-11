import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Thin WebSocket signaling client. The server (server/signaling_server.dart)
/// caps frames at 32 KiB; sending more is a programming error, so send()
/// throws instead of emitting an oversized frame.
class SignalingClient {
  static const int maxMessageBytes = 32 * 1024;

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _connection = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<bool> get connection => _connection.stream;
  bool get isConnected => _channel != null;

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_channel != null) {
        try {
          send(<String, dynamic>{'type': 'ping'});
        } catch (_) {}
      }
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> connect(String url) async {
    await disconnect();
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    try {
      await channel.ready;
      if (!identical(_channel, channel)) {
        unawaited(_closeChannel(channel));
        return;
      }
      _connection.add(true);
      _startPing();
      channel.stream.listen(
        (data) {
          if (!identical(_channel, channel)) return;
          if (data is! String) return;
          if (data.length > maxMessageBytes) return;
          try {
            final m = jsonDecode(data) as Map<String, dynamic>;
            if (m['type'] == 'pong') return;
            _messages.add(m);
          } catch (_) {}
        },
        onDone: () {
          if (!identical(_channel, channel)) return;
          _stopPing();
          _channel = null;
          _connection.add(false);
        },
        onError: (_) {
          if (!identical(_channel, channel)) return;
          _stopPing();
          _channel = null;
          _connection.add(false);
        },
      );
    } catch (_) {
      if (identical(_channel, channel)) {
        _channel = null;
        _connection.add(false);
      }
      rethrow;
    }
  }

  Future<void> send(Map<String, dynamic> message) async {
    final encoded = jsonEncode(message);
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw ArgumentError('signaling message exceeds $maxMessageBytes bytes');
    }
    _channel?.sink.add(encoded);
  }

  Future<void> disconnect() async {
    _stopPing();
    final channel = _channel;
    _channel = null;
    if (channel != null) _connection.add(false);
    // A pending WebSocket handshake may never finish closing. A new
    // connection must not wait for the retired channel's handshake.
    if (channel != null) unawaited(_closeChannel(channel));
  }

  Future<void> _closeChannel(WebSocketChannel channel) async {
    try {
      await channel.sink.close();
    } catch (_) {}
  }
}

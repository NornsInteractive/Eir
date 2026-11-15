import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Represents the diagnostic probe result of a TURN server.
class TurnTestResult {
  final bool success;
  final String message;
  final int? rttMs;
  final String? relayAddress;

  const TurnTestResult({
    required this.success,
    required this.message,
    this.rttMs,
    this.relayAddress,
  });
}

/// Service to probe TURN server connectivity and relay capability across all platforms.
class TurnDiagnosticService {
  /// Probes the specified TURN server by creating an isolated PeerConnection,
  /// gathering ICE candidates, and checking whether a `typ relay` candidate is produced.
  static Future<TurnTestResult> probeTurnServer({
    required String server,
    String? username,
    String? credential,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final clean = server.trim().replaceFirst(RegExp(r'^turns?:'), '');
    if (clean.isEmpty) {
      return const TurnTestResult(
        success: false,
        message: 'TURN 服务器地址不能为空',
      );
    }

    final isTurns = server.trim().startsWith('turns:');
    final scheme = isTurns ? 'turns:' : 'turn:';
    final turnUrls = isTurns
        ? <String>['$scheme$clean?transport=tcp']
        : <String>[
            '$scheme$clean?transport=udp',
            '$scheme$clean?transport=tcp',
          ];

    final turnConfig = <String, dynamic>{
      'urls': turnUrls,
    };
    if (username != null && username.trim().isNotEmpty) {
      turnConfig['username'] = username.trim();
    }
    if (credential != null && credential.trim().isNotEmpty) {
      turnConfig['credential'] = credential.trim();
    }

    final config = <String, dynamic>{
      'iceServers': [turnConfig],
      'sdpSemantics': 'unified-plan',
    };

    final completer = Completer<TurnTestResult>();
    final stopwatch = Stopwatch()..start();
    RTCPeerConnection? pc;

    final timeoutTimer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(const TurnTestResult(
          success: false,
          message: '探测超时 (未能分配中继候选，可能端口被阻断或凭据错误)',
        ));
      }
    });

    try {
      pc = await createPeerConnection(config);
      pc.onIceCandidate = (candidate) {
        if (completer.isCompleted) return;
        final candStr = candidate.candidate ?? '';
        if (candStr.contains('typ relay')) {
          stopwatch.stop();
          final rtt = stopwatch.elapsedMilliseconds;
          completer.complete(TurnTestResult(
            success: true,
            message: '连接成功 (中继就绪，耗时 ${rtt}ms)',
            rttMs: rtt,
            relayAddress: candStr,
          ));
        }
      };

      // Create a lightweight data channel and offer to start candidate gathering
      final dc = await pc.createDataChannel('turn_probe', RTCDataChannelInit());
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);

      final result = await completer.future;
      timeoutTimer.cancel();
      try {
        await dc.close();
      } catch (_) {}
      try {
        await pc.close();
      } catch (_) {}
      return result;
    } catch (e) {
      timeoutTimer.cancel();
      try {
        await pc?.close();
      } catch (_) {}
      return TurnTestResult(
        success: false,
        message: '探测异常: $e',
      );
    }
  }
}

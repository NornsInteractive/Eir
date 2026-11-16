import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app_localization.dart';

enum TurnDiagnosticStatus {
  emptyServer,
  timeout,
  success,
  exception,
}

/// Represents the diagnostic probe result of a TURN server.
class TurnTestResult {
  final bool success;
  final String message;
  final TurnDiagnosticStatus status;
  final int? rttMs;
  final String? relayAddress;
  final String? errorDetail;

  const TurnTestResult({
    required this.success,
    required this.message,
    this.status = TurnDiagnosticStatus.exception,
    this.rttMs,
    this.relayAddress,
    this.errorDetail,
  });

  String getLocalizedMessage(AppI18n i18n) {
    switch (status) {
      case TurnDiagnosticStatus.emptyServer:
        return i18n.turnServerAddressEmpty;
      case TurnDiagnosticStatus.timeout:
        return i18n.turnProbeTimeout;
      case TurnDiagnosticStatus.success:
        return i18n.turnConnectionSuccessWithRtt(rttMs ?? 0);
      case TurnDiagnosticStatus.exception:
        return i18n.turnProbeException(errorDetail ?? message);
    }
  }
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
        message: 'TURN server address cannot be empty',
        status: TurnDiagnosticStatus.emptyServer,
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
          message: 'Probe timed out (Failed to allocate relay candidate)',
          status: TurnDiagnosticStatus.timeout,
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
            message: 'Connected successfully (Relay ready, ${rtt}ms)',
            status: TurnDiagnosticStatus.success,
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
        message: 'Probe exception: $e',
        status: TurnDiagnosticStatus.exception,
        errorDetail: e.toString(),
      );
    }
  }
}

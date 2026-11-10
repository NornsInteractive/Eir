import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'platform/dtls_fingerprint.dart';

class WebRtcLoopbackResult {
  const WebRtcLoopbackResult({
    required this.success,
    required this.elapsed,
    this.error,
    this.sentMessage,
    this.receivedMessage,
    this.messageValidated = false,
    this.binaryValidated = false,
    this.maxBufferedAmount = 0,
    this.backpressureObserved = false,
    this.backpressureThresholdCrossed = false,
    this.statsReportCount = 0,
    this.statsTypes = const <String, int>{},
    this.fingerprintFields = const <String>[],
    this.callbackErrors = const <String>[],
    this.remoteDtlsFingerprint,
  });

  final bool success;
  final Duration elapsed;
  final String? error;
  final String? sentMessage;
  final String? receivedMessage;
  final bool messageValidated;
  final bool binaryValidated;
  final int maxBufferedAmount;
  final bool backpressureObserved;
  final bool backpressureThresholdCrossed;
  final int statsReportCount;
  final Map<String, int> statsTypes;
  final List<String> fingerprintFields;
  final List<String> callbackErrors;
  final String? remoteDtlsFingerprint;

  @override
  String toString() {
    return 'WebRtcLoopbackResult(success=$success, elapsed=${elapsed.inMilliseconds}ms, '
        'messageValidated=$messageValidated, binaryValidated=$binaryValidated, '
        'maxBufferedAmount=$maxBufferedAmount, backpressureObserved=$backpressureObserved, '
        'backpressureThresholdCrossed=$backpressureThresholdCrossed, '
        'statsReportCount=$statsReportCount, callbackErrors=$callbackErrors, '
        'remoteDtlsFingerprint=$remoteDtlsFingerprint, error=$error)';
  }
}

Future<WebRtcLoopbackResult> runWebRtcLoopback({
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  RTCPeerConnection? pc1;
  RTCPeerConnection? pc2;
  RTCDataChannel? dc1;
  RTCDataChannel? dc2;
  bool closed = false;

  List<RTCIceCandidate> queuedForPc1 = <RTCIceCandidate>[];
  List<RTCIceCandidate> queuedForPc2 = <RTCIceCandidate>[];
  final callbackErrors = <String>[];
  bool pc1RemoteDescInstalled = false;
  bool pc2RemoteDescInstalled = false;

  Duration remaining() {
    final r = timeout - stopwatch.elapsed;
    if (r <= Duration.zero) {
      throw TimeoutException('webrtc loopback', timeout);
    }
    return r;
  }

  void checkDeadline() {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('webrtc loopback', timeout);
    }
  }

  try {
    pc1 = await createPeerConnection(<String, dynamic>{'iceServers': <dynamic>[]})
        .timeout(remaining());
    pc2 = await createPeerConnection(<String, dynamic>{'iceServers': <dynamic>[]})
        .timeout(remaining());

    pc1.onIceCandidate = (RTCIceCandidate candidate) {
      if (closed) return;
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      if (pc2RemoteDescInstalled) {
        final target = pc2;
        if (target != null) {
          unawaited(target.addCandidate(candidate).catchError((Object e) {
            callbackErrors.add('pc1.onIceCandidate addCandidate pc2: $e');
          }));
        }
      } else {
        queuedForPc2.add(candidate);
      }
    };
    pc2.onIceCandidate = (RTCIceCandidate candidate) {
      if (closed) return;
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      if (pc1RemoteDescInstalled) {
        final target = pc1;
        if (target != null) {
          unawaited(target.addCandidate(candidate).catchError((Object e) {
            callbackErrors.add('pc2.onIceCandidate addCandidate pc1: $e');
          }));
        }
      } else {
        queuedForPc1.add(candidate);
      }
    };

    final dcOpen = Completer<void>();
    final textEcho = Completer<String>();
    final binaryEcho = Completer<Uint8List>();
    String? pendingToken;
    Uint8List? pendingBinary;

    dc1 = await pc1.createDataChannel(
      'eir-loopback',
      RTCDataChannelInit()..id = 1,
    ).timeout(remaining());

    pc2.onDataChannel = (RTCDataChannel channel) {
      dc2 = channel;
      channel.onMessage = (RTCDataChannelMessage message) {
        if (message.isBinary) {
          unawaited(channel.send(RTCDataChannelMessage.fromBinary(message.binary))
              .catchError((Object e) {
            callbackErrors.add('datachannel echo send binary: $e');
          }));
        } else {
          unawaited(channel.send(RTCDataChannelMessage('ECHO:${message.text}'))
              .catchError((Object e) {
            callbackErrors.add('datachannel echo send text: $e');
          }));
        }
      };
    };

    dc1.onDataChannelState = (RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !dcOpen.isCompleted) {
        dcOpen.complete();
      }
    };
    dc1.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        if (pendingBinary != null &&
            _bytesEqual(message.binary, pendingBinary) &&
            !binaryEcho.isCompleted) {
          binaryEcho.complete(message.binary);
        }
      } else {
        if (pendingToken != null &&
            message.text == 'ECHO:PING:$pendingToken' &&
            !textEcho.isCompleted) {
          textEcho.complete(message.text);
        }
      }
    };

    final offer = await pc1.createOffer(<String, dynamic>{}).timeout(remaining());
    await pc2.setRemoteDescription(offer).timeout(remaining());
    pc2RemoteDescInstalled = true;
    for (final c in queuedForPc2) {
      try {
        await pc2.addCandidate(c).timeout(remaining());
      } catch (e) {
        callbackErrors.add('flush queuedForPc2: $e');
      }
    }
    queuedForPc2.clear();

    final answer = await pc2.createAnswer(<String, dynamic>{}).timeout(remaining());
    await pc1.setLocalDescription(offer).timeout(remaining());
    await pc2.setLocalDescription(answer).timeout(remaining());
    await pc1.setRemoteDescription(answer).timeout(remaining());
    pc1RemoteDescInstalled = true;
    for (final c in queuedForPc1) {
      try {
        await pc1.addCandidate(c).timeout(remaining());
      } catch (e) {
        callbackErrors.add('flush queuedForPc1: $e');
      }
    }
    queuedForPc1.clear();

    await dcOpen.future.timeout(remaining());

    // Backpressure probe with bounded chunked sends.
    int maxBufferedAmount = 0;
    bool thresholdCrossed = false;
    bool resumed = false;
    bool backpressureObserved = false;
    const threshold = 64 * 1024;
    try {
      final chunk = List<int>.filled(16 * 1024, 42);
      for (var i = 0; i < 8; i++) {
        checkDeadline();
        while (true) {
          checkDeadline();
          final buffered = await dc1.getBufferedAmount().timeout(remaining());
          if (buffered > maxBufferedAmount) maxBufferedAmount = buffered;
          if (buffered > threshold) thresholdCrossed = true;
          if (thresholdCrossed && buffered <= threshold) resumed = true;
          if (buffered <= threshold) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await dc1.send(RTCDataChannelMessage(String.fromCharCodes(chunk))).timeout(remaining());
      }
      backpressureObserved = thresholdCrossed && resumed;
    } catch (_) {
      backpressureObserved = false;
    }

    // Text ping with exact token correlation.
    pendingToken = 'ping-${DateTime.now().microsecondsSinceEpoch}';
    final token = pendingToken;
    await dc1.send(RTCDataChannelMessage('PING:$token')).timeout(remaining());
    final echo = await textEcho.future.timeout(remaining());
    final expected = 'ECHO:PING:$token';
    final messageValidated = echo == expected;

    // Binary payload verification.
    pendingBinary = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    final sentBinary = pendingBinary;
    await dc1.send(RTCDataChannelMessage.fromBinary(sentBinary)).timeout(remaining());
    final receivedBinary = await binaryEcho.future.timeout(remaining());
    final binaryValidated = _bytesEqual(receivedBinary, sentBinary);

    // Stats and actual remote DTLS fingerprint mapping.
    final stats1 = await pc1.getStats().timeout(remaining());
    final stats2 = await pc2.getStats().timeout(remaining());

    final fingerprintFields = <String>[];
    final statsTypes = <String, int>{};

    for (final reports in <List<StatsReport>>[stats1, stats2]) {
      for (final report in reports) {
        statsTypes[report.type] = (statsTypes[report.type] ?? 0) + 1;
        report.values.forEach((key, value) {
          final lower = key.toString().toLowerCase();
          if (lower.contains('fingerprint') ||
              lower.contains('certificate') ||
              lower.contains('dtls')) {
            fingerprintFields.add('${report.type}.$key=$value');
          }
        });
      }
    }
    final remoteDtlsFingerprintValue = await remoteDtlsFingerprint(pc1);

    if (remoteDtlsFingerprintValue == null) {
      fingerprintFields.add(
        'BLOCKER: getStats did not expose a transport remoteCertificateId/certificate fingerprint',
      );
    }

    stopwatch.stop();
    final success = messageValidated &&
        binaryValidated &&
        callbackErrors.isEmpty;
    return WebRtcLoopbackResult(
      success: success,
      elapsed: stopwatch.elapsed,
      error: success
          ? null
          : 'validation failed: text=$messageValidated binary=$binaryValidated '
              'callbackErrors=$callbackErrors',
      sentMessage: 'PING:$token',
      receivedMessage: echo,
      messageValidated: messageValidated,
      binaryValidated: binaryValidated,
      maxBufferedAmount: maxBufferedAmount,
      backpressureObserved: backpressureObserved,
      backpressureThresholdCrossed: thresholdCrossed,
      statsReportCount: stats1.length + stats2.length,
      statsTypes: statsTypes,
      fingerprintFields: fingerprintFields,
      callbackErrors: callbackErrors,
      remoteDtlsFingerprint: remoteDtlsFingerprintValue,
    );
  } on TimeoutException catch (e) {
    stopwatch.stop();
    return WebRtcLoopbackResult(
      success: false,
      elapsed: stopwatch.elapsed,
      error: 'timeout: $e',
    );
  } catch (e) {
    stopwatch.stop();
    return WebRtcLoopbackResult(
      success: false,
      elapsed: stopwatch.elapsed,
      error: '$e',
    );
  } finally {
    closed = true;
    const grace = Duration(seconds: 3);
    try {
      final c = dc1;
      if (c != null) await c.close().timeout(grace);
    } catch (_) {}
    try {
      final c = dc2;
      if (c != null) await c.close().timeout(grace);
    } catch (_) {}
    try {
      final c = pc1;
      if (c != null) await c.close().timeout(grace);
    } catch (_) {}
    try {
      final c = pc2;
      if (c != null) await c.close().timeout(grace);
    } catch (_) {}
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

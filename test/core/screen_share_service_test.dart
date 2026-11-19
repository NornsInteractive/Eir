import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:eir/core/screen_share_service.dart';

import 'fake_webrtc.dart';

/// Local test seam: getStats results are released by explicit gates so a slow
/// sample from one peer connection can be completed after a newer one.
class GatedStatsPeerConnection extends FakePeerConnection {
  final List<Completer<List<StatsReport>>> _gates =
      <Completer<List<StatsReport>>>[];

  Completer<List<StatsReport>> nextStatsGate() {
    final gate = Completer<List<StatsReport>>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) {
    if (_gates.isNotEmpty) return _gates.removeAt(0).future;
    return super.getStats(track);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenShareService Unit Tests', () {
    test('initializes with idle state and default properties', () {
      final signals = <Map<String, dynamic>>[];
      final service = ScreenShareService(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'dev-test-123',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => 'preset:aurora',
      );

      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(service.isActive, isFalse);
      expect(service.isBroadcasting, isFalse);
      expect(service.isViewing, isFalse);
      expect(service.targetFps, 60);
      expect(service.volume, 1.0);
      expect(service.isMuted, isFalse);
      expect(service.duration, Duration.zero);

      service.dispose();
    });

    test('volume adjustment and muting work as expected', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Bob',
        getCurrentAvatar: () => null,
      );

      service.setVolume(0.5);
      expect(service.volume, 0.5);
      expect(service.isMuted, isFalse);

      service.setVolume(0.0);
      expect(service.isMuted, isTrue);

      service.setVolume(0.8);
      expect(service.isMuted, isFalse);

      service.toggleMute();
      expect(service.isMuted, isTrue);

      service.toggleMute();
      expect(service.isMuted, isFalse);

      service.dispose();
    });

    test('handles incoming screen_share_started signal', () async {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-viewer',
        getCurrentDisplayName: () => 'Viewer',
        getCurrentAvatar: () => null,
      );

      await service.handleSignal({
        'type': 'screen_share_started',
        'sourceTitle': '抖音 - 发现美好',
        'sourceType': 'window',
        'targetFps': 60,
      });

      expect(service.sourceTitle, '抖音 - 发现美好');
      expect(service.sourceType, 'window');
      expect(service.targetFps, 60);

      service.dispose();
    });

    test('handles incoming screen_share_stop signal', () async {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-test',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      await service.handleSignal({
        'type': 'screen_share_stop',
        'reason': 'remote_closed',
      });

      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(service.isActive, isFalse);

      service.dispose();
    });

    test('dual-channel volume and smart audio ducking', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.companionVolume, 1.0);
      expect(service.voiceVolume, 1.0);
      expect(service.isAudioDuckingEnabled, isTrue);

      service.setCompanionVolume(0.7);
      service.setVoiceVolume(1.4);
      service.setAudioDucking(false);

      expect(service.companionVolume, 0.7);
      expect(service.voiceVolume, 1.4);
      expect(service.isAudioDuckingEnabled, isFalse);

      service.dispose();
    });

    test('aspect ratio mode toggle (cover vs contain)', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.isCoverMode, isFalse);
      service.toggleAspectMode();
      expect(service.isCoverMode, isTrue);
      service.toggleAspectMode();
      expect(service.isCoverMode, isFalse);

      service.dispose();
    });

    test('reaction emoji streaming and signaling', () async {
      final sentSignals = <Map<String, dynamic>>[];
      final receivedReactions = <String>[];

      final service = ScreenShareService(
        sendSignal: (sig) async => sentSignals.add(sig),
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      final sub = service.onReaction.listen(receivedReactions.add);

      await service.sendReaction('🔥');
      expect(sentSignals.length, 1);
      expect(sentSignals.first['type'], 'screen_share_reaction');
      expect(sentSignals.first['emoji'], '🔥');

      await service.handleSignal({
        'type': 'screen_share_reaction',
        'emoji': '❤️',
      });
      expect(receivedReactions, contains('❤️'));

      await sub.cancel();
      service.dispose();
    });

    test('stream health diagnostics are unavailable instead of fake zero', () {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.rttMs, isNull);
      expect(service.bitrateMbps, isNull);
      expect(service.packetLoss, isNull);
      expect(service.statsAvailable, isFalse);

      service.dispose();
    });

    test('cancel permission leaves idle state and never acquires capture',
        () async {
      var mediaRequested = false;
      final methods = <String>[];
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        platformIsAndroid: () => true,
        requestCapturePermissionOverride: () async => false,
        platformMethodInvoker: (method, [arguments]) async {
          methods.add(method);
          return null;
        },
        getDisplayMediaOverride: (_) async {
          mediaRequested = true;
          return FakeMediaStream(tracks: [FakeMediaTrack('video')]);
        },
      );

      final started = await service.startBroadcasting(castCode: 'room-1');

      expect(started, isFalse);
      expect(mediaRequested, isFalse);
      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(service.lastError, contains('permission'));
      expect(methods, isNot(contains('startMediaProjectionService')));

      service.dispose();
    });

    test('stop during a pending capture never activates the late stream',
        () async {
      final captureRequested = Completer<void>();
      final capture = Completer<MediaStream?>();
      var pcCreates = 0;
      final signals = <Map<String, dynamic>>[];
      final lateTrack = FakeMediaTrack('video');
      final lateStream = FakeMediaStream(tracks: [lateTrack]);
      final service = ScreenShareService(
        sendSignal: (signal) async => signals.add(signal),
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        getDisplayMediaOverride: (_) {
          if (!captureRequested.isCompleted) captureRequested.complete();
          return capture.future;
        },
        createPeerConnectionOverride: (_) async {
          pcCreates++;
          return FakePeerConnection();
        },
      );

      final starting = service.startBroadcasting(castCode: 'room-1');
      await captureRequested.future;
      await service.stop(reason: 'cancelled');
      capture.complete(lateStream);

      expect(await starting, isFalse);
      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(lateTrack.stopped, isTrue);
      expect(lateStream.disposed, isTrue);
      expect(pcCreates, 0);
      expect(
        signals.where((s) => s['type'] == 'screen_share_started'),
        isEmpty,
      );

      service.dispose();
    });

    test('stop then restart isolates stale tracks, ICE, SDP and callbacks',
        () async {
      final firstTrack = FakeMediaTrack('video', idValue: 'first-video');
      final secondTrack = FakeMediaTrack('video', idValue: 'second-video');
      final firstStream = FakeMediaStream(tracks: [firstTrack], id: 'first');
      final secondStream = FakeMediaStream(tracks: [secondTrack], id: 'second');
      final streams = <FakeMediaStream>[firstStream, secondStream];
      final pcs = <FakePeerConnection>[];
      final signals = <Map<String, dynamic>>[];
      var displayCalls = 0;
      final service = ScreenShareService(
        sendSignal: (signal) async => signals.add(signal),
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        getDisplayMediaOverride: (_) async => streams[displayCalls++],
        createPeerConnectionOverride: (_) async {
          final pc = FakePeerConnection();
          pcs.add(pc);
          return pc;
        },
      );

      expect(
        await service.startBroadcasting(castCode: 'room-1'),
        isTrue,
      );
      expect(service.isBroadcasting, isTrue);
      final firstPc = pcs.single;

      await service.stop(reason: 'restart');
      expect(firstTrack.stopped, isTrue);
      expect(firstPc.closed, isTrue);

      expect(
        await service.startBroadcasting(castCode: 'room-2'),
        isTrue,
      );
      expect(service.isBroadcasting, isTrue);
      expect(secondTrack.stopped, isFalse);
      expect(secondStream.disposed, isFalse);
      final secondPc = pcs.last;
      expect(secondPc.closed, isFalse);

      signals.clear();
      final staleStream =
          FakeMediaStream(tracks: [FakeMediaTrack('video')], id: 'stale');
      firstPc.onTrack?.call(RTCTrackEvent(
        streams: [staleStream],
        track: FakeMediaTrack('video'),
      ));
      firstPc.onIceCandidate?.call(RTCIceCandidate(
        'candidate:stale 1 UDP 1 127.0.0.1 9 typ host',
        '0',
        0,
      ));
      firstPc.onConnectionState
          ?.call(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
      firstTrack.onEnded?.call();
      await Future<void>.delayed(Duration.zero);

      expect(service.hasRemoteStream, isFalse);
      expect(service.isBroadcasting, isTrue);
      expect(signals.where((s) => s['type'] == 'screen_share_ice'), isEmpty);

      // A late SDP from the previous cast cannot recreate a peer connection.
      final pcCountBefore = pcs.length;
      await service.handleSignal({
        'type': 'screen_share_sdp',
        'castCode': 'room-1',
        'sdp': {'type': 'offer', 'sdp': 'v=0 stale'},
      });
      expect(pcs.length, pcCountBefore);
      expect(service.isBroadcasting, isTrue);

      service.dispose();
    });

    test('dispose stops tracks, closes the PC and the Android projection service',
        () async {
      final track = FakeMediaTrack('video');
      final stream = FakeMediaStream(tracks: [track]);
      final pc = FakePeerConnection();
      final methods = <String>[];
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        platformIsAndroid: () => true,
        requestCapturePermissionOverride: () async => true,
        platformMethodInvoker: (method, [arguments]) async {
          methods.add(method);
          return null;
        },
        getDisplayMediaOverride: (_) async => stream,
        createPeerConnectionOverride: (_) async => pc,
      );

      expect(await service.startBroadcasting(castCode: 'room-1'), isTrue);
      expect(methods, contains('startMediaProjectionService'));

      service.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(track.stopped, isTrue);
      expect(stream.disposed, isTrue);
      expect(pc.closed, isTrue);
      expect(methods, contains('stopMediaProjectionService'));
    });

    test('stream health samples real getStats and reports unavailable explicitly',
        () async {
      final pc = FakePeerConnection();
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        getDisplayMediaOverride: (_) async =>
            FakeMediaStream(tracks: [FakeMediaTrack('video')]),
        createPeerConnectionOverride: (_) async => pc,
      );

      expect(await service.startBroadcasting(castCode: 'room-1'), isTrue);
      expect(service.statsAvailable, isFalse);

      pc.stats = [
        StatsReport('in', 'inbound-rtp', 0, {
          'type': 'inbound-rtp',
          'kind': 'video',
          'bytesReceived': 100000,
          'packetsLost': 2,
          'packetsReceived': 98,
        }),
        StatsReport('pair', 'candidate-pair', 0, {
          'type': 'candidate-pair',
          'state': 'succeeded',
          'currentRoundTripTime': 0.045,
        }),
      ];
      await service.refreshStats();
      expect(service.statsAvailable, isTrue);
      expect(service.rttMs, 45);
      expect(service.packetLoss, closeTo(0.02, 0.0001));
      expect(service.bitrateMbps, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      pc.stats = [
        StatsReport('in', 'inbound-rtp', 1, {
          'type': 'inbound-rtp',
          'kind': 'video',
          'bytesReceived': 200000,
          'packetsLost': 4,
          'packetsReceived': 196,
        }),
      ];
      await service.refreshStats();
      expect(service.bitrateMbps, isNotNull);
      expect(service.bitrateMbps!, greaterThan(0));
      expect(service.rttMs, isNull);

      pc.stats = [];
      await service.refreshStats();
      expect(service.statsAvailable, isFalse);
      expect(service.rttMs, isNull);
      expect(service.bitrateMbps, isNull);
      expect(service.packetLoss, isNull);

      service.dispose();
    });

    test('in-cast messaging sending, receiving, and unread count tracking', () async {
      final sentSignals = <Map<String, dynamic>>[];
      final receivedMessages = <dynamic>[];

      final service = ScreenShareService(
        sendSignal: (sig) async => sentSignals.add(sig),
        getCurrentDeviceId: () => 'dev-alice',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => 'preset:aurora',
      );

      final sub = service.onChatMessage.listen(receivedMessages.add);

      expect(service.messages, isEmpty);
      expect(service.unreadCount, 0);
      expect(service.danmakuEnabled, isTrue);

      // 1. Send chat message
      await service.sendChatMessage('Hello screen cast!');
      expect(service.messages.length, 1);
      expect(service.messages.first.text, 'Hello screen cast!');
      expect(service.messages.first.isSelf, isTrue);
      expect(service.messages.first.senderName, 'Alice');
      expect(sentSignals.length, 1);
      expect(sentSignals.first['type'], 'screen_share_chat');
      expect(sentSignals.first['message']['text'], 'Hello screen cast!');

      // 2. Handle incoming chat message from peer
      await service.handleSignal({
        'type': 'screen_share_chat',
        'message': {
          'id': 'msg-bob-1',
          'senderDeviceId': 'dev-bob',
          'senderName': 'Bob',
          'senderAvatar': null,
          'text': 'Nice cast, looks so smooth!',
          'timestamp': DateTime.now().toIso8601String(),
        },
      });

      expect(service.messages.length, 2);
      expect(service.messages.last.text, 'Nice cast, looks so smooth!');
      expect(service.messages.last.isSelf, isFalse);
      expect(service.unreadCount, 1);

      // 3. Mark messages as read
      service.markMessagesAsRead();
      expect(service.unreadCount, 0);

      // 4. Toggle danmaku
      service.toggleDanmaku();
      expect(service.danmakuEnabled, isFalse);
      service.toggleDanmaku();
      expect(service.danmakuEnabled, isTrue);

      await sub.cancel();
      service.dispose();
    });

    test('camera video talkback status signaling and state', () async {
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-test',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
      );

      expect(service.isCameraEnabled, isFalse);
      expect(service.isRemoteCameraActive, isFalse);
      expect(service.isFrontCamera, isTrue);

      // Receive remote camera status signal
      await service.handleSignal({
        'type': 'screen_share_camera_status',
        'enabled': true,
      });

      expect(service.isRemoteCameraActive, isTrue);

      await service.handleSignal({
        'type': 'screen_share_camera_status',
        'enabled': false,
      });

      expect(service.isRemoteCameraActive, isFalse);

      service.dispose();
    });

    test('stop while Android capture permission is pending drops a late grant',
        () async {
      final permissionRequested = Completer<void>();
      final permission = Completer<bool>();
      final methods = <String>[];
      var mediaRequested = false;
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        platformIsAndroid: () => true,
        requestCapturePermissionOverride: () {
          if (!permissionRequested.isCompleted) permissionRequested.complete();
          return permission.future;
        },
        platformMethodInvoker: (method, [arguments]) async {
          methods.add(method);
          return null;
        },
        getDisplayMediaOverride: (_) async {
          mediaRequested = true;
          return FakeMediaStream(tracks: [FakeMediaTrack('video')]);
        },
        statsInterval: Duration.zero,
      );

      final starting = service.startBroadcasting(castCode: 'room-1');
      await permissionRequested.future;
      await service.stop(reason: 'cancelled_while_awaiting_permission');
      permission.complete(true); // grant arrives after stop

      expect(await starting, isFalse);
      expect(service.state, ScreenShareState.idle);
      expect(service.role, ScreenShareRole.none);
      expect(service.isActive, isFalse);
      expect(mediaRequested, isFalse);
      expect(methods, isNot(contains('startMediaProjectionService')));

      service.dispose();
    });

    test('late connected callbacks from a stopped session cannot revive it',
        () async {
      final lateStream = FakeMediaStream(tracks: [FakeMediaTrack('video')]);
      final pc = FakePeerConnection();
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        getDisplayMediaOverride: (_) async =>
            FakeMediaStream(tracks: [FakeMediaTrack('video')]),
        createPeerConnectionOverride: (_) async => pc,
      );

      expect(await service.startBroadcasting(castCode: 'room-1'), isTrue);
      await service.stop(reason: 'restart');
      expect(service.state, ScreenShareState.idle);
      expect(pc.closed, isTrue);

      pc.onConnectionState
          ?.call(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      pc.onIceConnectionState
          ?.call(RTCIceConnectionState.RTCIceConnectionStateConnected);
      pc.onIceConnectionState
          ?.call(RTCIceConnectionState.RTCIceConnectionStateCompleted);
      pc.onTrack?.call(RTCTrackEvent(
        streams: [lateStream],
        track: FakeMediaTrack('video'),
      ));
      await Future<void>.delayed(Duration.zero);

      expect(service.state, ScreenShareState.idle);
      expect(service.isActive, isFalse);
      expect(service.hasRemoteStream, isFalse);

      service.dispose();
    });

    test('partial stats reports keep missing metrics null without fake zeros',
        () async {
      final pc = FakePeerConnection();
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        getDisplayMediaOverride: (_) async =>
            FakeMediaStream(tracks: [FakeMediaTrack('video')]),
        createPeerConnectionOverride: (_) async => pc,
      );

      expect(await service.startBroadcasting(castCode: 'room-1'), isTrue);

      // A recognized report type with no metrics is "available" but every
      // individual metric stays null (UI contract: never coerce to 0).
      pc.stats = [
        StatsReport('in', 'inbound-rtp', 0, {
          'type': 'inbound-rtp',
          'kind': 'video',
        }),
      ];
      await service.refreshStats();
      expect(service.statsAvailable, isTrue);
      expect(service.rttMs, isNull);
      expect(service.bitrateMbps, isNull);
      expect(service.packetLoss, isNull);

      // Establish a byte baseline, then a counter reset must yield no bitrate
      // rather than a fabricated negative value.
      pc.stats = [
        StatsReport('in', 'inbound-rtp', 1, {
          'type': 'inbound-rtp',
          'bytesReceived': 1000,
        }),
      ];
      await service.refreshStats();
      expect(service.bitrateMbps, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      pc.stats = [
        StatsReport('in', 'inbound-rtp', 2, {
          'type': 'inbound-rtp',
          'bytesReceived': 500,
        }),
      ];
      await service.refreshStats();
      expect(service.bitrateMbps, isNull);

      service.dispose();
    });

    test('a slow stats sample from an old peer connection cannot overwrite new state',
        () async {
      final firstPc = GatedStatsPeerConnection();
      final secondPc = GatedStatsPeerConnection();
      final pcs = <FakePeerConnection>[firstPc, secondPc];
      var createIndex = 0;
      final service = ScreenShareService(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'dev-1',
        getCurrentDisplayName: () => 'Tester',
        getCurrentAvatar: () => null,
        statsInterval: Duration.zero,
        getDisplayMediaOverride: (_) async =>
            FakeMediaStream(tracks: [FakeMediaTrack('video')]),
        createPeerConnectionOverride: (_) async => pcs[createIndex++],
      );

      expect(await service.startBroadcasting(castCode: 'room-1'), isTrue);

      final oldGate = firstPc.nextStatsGate();
      unawaited(service.refreshStats()); // pending on the old PC

      await service.stop(reason: 'restart');
      expect(await service.startBroadcasting(castCode: 'room-2'), isTrue);
      expect(identical(firstPc, secondPc), isFalse);

      final newGate = secondPc.nextStatsGate();
      unawaited(service.refreshStats()); // pending on the new PC

      newGate.complete([
        StatsReport('in', 'inbound-rtp', 0, {
          'type': 'inbound-rtp',
          'bytesReceived': 1000,
          'packetsReceived': 100,
          'packetsLost': 1,
        }),
        StatsReport('pair', 'candidate-pair', 0, {
          'type': 'candidate-pair',
          'state': 'succeeded',
          'currentRoundTripTime': 0.05,
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(service.statsAvailable, isTrue);
      expect(service.rttMs, 50);
      expect(service.packetLoss, closeTo(0.01, 0.0001));

      oldGate.complete([
        StatsReport('in', 'inbound-rtp', 0, {
          'type': 'inbound-rtp',
          'bytesReceived': 999999,
          'packetsReceived': 1,
          'packetsLost': 1,
        }),
        StatsReport('pair', 'candidate-pair', 0, {
          'type': 'candidate-pair',
          'state': 'succeeded',
          'currentRoundTripTime': 9.0,
        }),
      ]);
      await Future<void>.delayed(Duration.zero);

      // The stale sample must not mutate the newer session's state.
      expect(service.rttMs, 50);
      expect(service.packetLoss, closeTo(0.01, 0.0001));
      expect(service.statsAvailable, isTrue);

      service.dispose();
    });
  });
}

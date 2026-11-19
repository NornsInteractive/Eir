import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eir/models.dart';
import 'package:eir/core/call_session.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'fake_webrtc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMessage & CallSession Core Unit Tests', () {
    test('ChatMessage json serialization and deserialization roundtrip', () {
      final now = DateTime.now();
      final msg = ChatMessage(
        id: 'msg-123',
        senderDeviceId: 'dev-456',
        senderName: 'Alice',
        senderAvatar: 'preset:rose',
        text: 'Hello, World!',
        timestamp: now,
        type: ChatMessageType.text,
        colorHex: '#FF5500',
      );

      final json = msg.toJson();
      expect(json['id'], 'msg-123');
      expect(json['senderDeviceId'], 'dev-456');
      expect(json['senderName'], 'Alice');
      expect(json['text'], 'Hello, World!');
      expect(json['colorHex'], '#FF5500');

      final reconstructed = ChatMessage.fromJson(json, currentDeviceId: 'dev-456');
      expect(reconstructed.id, 'msg-123');
      expect(reconstructed.senderName, 'Alice');
      expect(reconstructed.text, 'Hello, World!');
      expect(reconstructed.isSelf, isTrue);

      final otherUser = ChatMessage.fromJson(json, currentDeviceId: 'dev-other');
      expect(otherUser.isSelf, isFalse);
    });

    test('CallSession starts in idle state and transitions to outgoing on startCall', () async {
      final signals = <Map<String, dynamic>>[];
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
      );

      expect(session.state, CallState.idle);
      expect(session.isMicMuted, isFalse);

      await session.startCall(
        CallType.voice,
        targetId: 'peer-dev-id',
        targetName: 'Bob',
      );

      expect(session.state, CallState.outgoing);
      expect(session.type, CallType.voice);
      expect(session.peerName, 'Bob');
      expect(signals.length, 1);
      expect(signals.first['type'], 'call_invite');
      expect(signals.first['callType'], 'voice');
      expect(signals.first['callerId'], 'my-dev-id');

      // Hangup from outgoing
      await session.hangupCall(reason: 'user_cancel');
      expect(session.state, CallState.idle);
      expect(signals.length, 2);
      expect(signals.last['type'], 'call_hangup');

      session.dispose();
    });

    test('CallSession receives incoming call and accepts', () async {
      final signals = <Map<String, dynamic>>[];
      bool ducking = false;
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
        onAudioDuckingChange: (inCall) => ducking = inCall,
      );

      // Simulate incoming invite signal
      await session.handleCallSignal({
        'type': 'call_invite',
        'callType': 'video',
        'callerId': 'bob-dev-id',
        'callerName': 'Bob',
      });

      expect(session.state, CallState.incoming);
      expect(session.type, CallType.video);
      expect(session.peerName, 'Bob');

      // Accept call
      await session.acceptCall();
      expect(session.state, CallState.connected);
      expect(ducking, isTrue);
      expect(signals.any((s) => s['type'] == 'call_accept'), isTrue);

      // Toggle mic & camera
      session.toggleMic();
      expect(session.isMicMuted, isTrue);
      expect(signals.last['type'], 'call_track_state');
      expect(signals.last['micMuted'], isTrue);

      session.toggleCamera();
      expect(session.isCameraOff, isTrue);

      // Hangup
      await session.hangupCall();
      expect(session.state, CallState.idle);
      expect(ducking, isFalse);

      session.dispose();
    });

    test('CallSession receives incoming call and declines', () async {
      final signals = <Map<String, dynamic>>[];
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
      );

      await session.handleCallSignal({
        'type': 'call_invite',
        'callType': 'voice',
        'callerId': 'bob-dev-id',
        'callerName': 'Bob',
      });

      expect(session.state, CallState.incoming);

      await session.declineCall();
      expect(session.state, CallState.idle);
      expect(signals.any((s) => s['type'] == 'call_reject'), isTrue);

      session.dispose();
    });

    test('CallSession handles peer track state changes', () async {
      final session = CallSession(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
      );

      await session.handleCallSignal({
        'type': 'call_track_state',
        'micMuted': true,
        'cameraOff': true,
      });

      expect(session.isPeerMicMuted, isTrue);
      expect(session.isPeerCameraOff, isTrue);

      session.dispose();
    });

    test('CallSession ignores SDP and ICE candidates while no call is connected', () async {
      final signals = <Map<String, dynamic>>[];
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
      );

      // Early incoming SDP offer before call is accepted
      await session.handleCallSignal({
        'type': 'call_sdp',
        'sdp': {'type': 'offer', 'sdp': 'v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n'},
      });

      // Early ICE candidates before connection is ready
      await session.handleCallSignal({
        'type': 'call_ice',
        'candidate': {
          'candidate': 'candidate:1 1 UDP 2130706431 192.168.1.100 50000 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });

      // Early candidates and SDP should not throw or corrupt state
      expect(session.state, CallState.idle);

      // Cleanup clears all pending state safely
      session.dispose();
      expect(session.state, CallState.idle);
    });

    test('CallSession ignores stale SDP and ICE after hangup', () async {
      final signals = <Map<String, dynamic>>[];
      final pc = FakePeerConnection();
      final remoteStream =
          FakeMediaStream(tracks: [FakeMediaTrack('video')], id: 'old-remote');
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
        createPeerConnectionOverride: (_) async => pc,
        getUserMediaOverride: (_) async => FakeMediaStream(
          tracks: [FakeMediaTrack('audio'), FakeMediaTrack('video')],
        ),
      );

      await session.startCall(CallType.video, targetId: 'bob-dev-id');
      await session.handleCallSignal({'type': 'call_accept'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(session.state, CallState.connected);

      await session.hangupCall();
      expect(session.state, CallState.idle);
      expect(pc.closed, isTrue);
      signals.clear();

      await session.handleCallSignal({
        'type': 'call_sdp',
        'sdp': {'type': 'offer', 'sdp': 'v=0 old'},
      });
      await session.handleCallSignal({
        'type': 'call_ice',
        'candidate': {
          'candidate': 'candidate:old 1 UDP 1 127.0.0.1 9 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });
      pc.onTrack?.call(RTCTrackEvent(
        streams: [remoteStream],
        track: FakeMediaTrack('video'),
      ));
      pc.onIceCandidate?.call(RTCIceCandidate(
        'candidate:late 1 UDP 1 127.0.0.1 9 typ host',
        '0',
        0,
      ));
      await Future<void>.delayed(Duration.zero);

      expect(session.state, CallState.idle);
      expect(session.hasRemoteStream, isFalse);
      expect(pc.setRemoteDescriptionCalls, 0);
      expect(pc.addedCandidates, isEmpty);
      expect(signals.where((s) => s['type'] == 'call_ice'), isEmpty);

      session.dispose();
    });

    test('startCall hangup during invite send keeps the session idle', () async {
      final inviteSignal = Completer<void>();
      final signals = <Map<String, dynamic>>[];
      var pcCreates = 0;
      final session = CallSession(
        sendSignal: (sig) async {
          signals.add(sig);
          if (sig['type'] == 'call_invite') await inviteSignal.future;
        },
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
        createPeerConnectionOverride: (_) async {
          pcCreates++;
          return FakePeerConnection();
        },
      );

      final starting = session.startCall(
        CallType.voice,
        targetId: 'bob-dev-id',
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.state, CallState.outgoing);

      await session.hangupCall(reason: 'cancelled');
      expect(session.state, CallState.idle);

      inviteSignal.complete();
      await starting;

      expect(session.state, CallState.idle);
      expect(pcCreates, 0);
      expect(signals.last['type'], 'call_hangup');

      session.dispose();
    });

    test('hangup during datachannel media acquisition disposes the late stream',
        () async {
      final mediaRequested = Completer<void>();
      final media = Completer<MediaStream>();
      final lateTrack = FakeMediaTrack('video');
      final lateStream = FakeMediaStream(tracks: [lateTrack]);
      final pc = FakePeerConnection();
      final session = CallSession(
        sendSignal: (_) async {},
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
        createPeerConnectionOverride: (_) async => pc,
        getUserMediaOverride: (_) {
          if (!mediaRequested.isCompleted) mediaRequested.complete();
          return media.future;
        },
      );

      await session.startCall(CallType.video, targetId: 'bob-dev-id');
      final accepting = session.handleCallSignal({'type': 'call_accept'});
      await mediaRequested.future;

      await session.hangupCall();
      expect(session.state, CallState.idle);
      expect(pc.closed, isTrue);

      media.complete(lateStream);
      await accepting;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(session.state, CallState.idle);
      expect(session.hasRemoteStream, isFalse);
      expect(lateTrack.stopped, isTrue);
      expect(lateStream.disposed, isTrue);
      expect(pc.addedTracks, isEmpty);

      session.dispose();
    });

    test('acceptCall hangup during accept send never starts callee media',
        () async {
      final acceptSignal = Completer<void>();
      var pcCreates = 0;
      final session = CallSession(
        sendSignal: (sig) async {
          if (sig['type'] == 'call_accept') await acceptSignal.future;
        },
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
        createPeerConnectionOverride: (_) async {
          pcCreates++;
          return FakePeerConnection();
        },
      );

      await session.handleCallSignal({
        'type': 'call_invite',
        'callType': 'video',
        'callerId': 'bob-dev-id',
        'callerName': 'Bob',
      });
      final accepting = session.acceptCall();
      await Future<void>.delayed(Duration.zero);
      expect(session.state, CallState.connected);

      await session.hangupCall(reason: 'cancelled');
      expect(session.state, CallState.idle);

      acceptSignal.complete();
      await accepting;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(session.state, CallState.idle);
      expect(pcCreates, 0);

      session.dispose();
    });

    test('CallSession deduplicates duplicate call_invite from the same caller without busy rejection', () async {
      final signals = <Map<String, dynamic>>[];
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
      );

      // First invite
      await session.handleCallSignal({
        'type': 'call_invite',
        'callType': 'voice',
        'callerId': 'caller-bob',
        'callerName': 'Bob',
      });
      expect(session.state, CallState.incoming);
      expect(session.peerName, 'Bob');

      // Duplicate invite from the same caller (e.g. multi-path delivery)
      await session.handleCallSignal({
        'type': 'call_invite',
        'callType': 'voice',
        'callerId': 'caller-bob',
        'callerName': 'Bob',
      });

      // Must remain in incoming state and NOT emit call_reject(busy)
      expect(session.state, CallState.incoming);
      expect(signals.any((s) => s['type'] == 'call_reject'), isFalse);

      session.dispose();
    });

    test('late SDP, ICE and hangup from a previous call cannot mutate a new call',
        () async {
      final signals = <Map<String, dynamic>>[];
      final pcs = <FakePeerConnection>[];
      final session = CallSession(
        sendSignal: (sig) async => signals.add(sig),
        getCurrentDeviceId: () => 'my-dev-id',
        getCurrentDisplayName: () => 'Alice',
        getCurrentAvatar: () => null,
        createPeerConnectionOverride: (_) async {
          final pc = FakePeerConnection();
          pcs.add(pc);
          return pc;
        },
        getUserMediaOverride: (_) async =>
            FakeMediaStream(tracks: [FakeMediaTrack('audio')]),
      );

      // First call, driven entirely through the public seam so the callIds are
      // the real ones emitted by the session (not invented by the test).
      await session.startCall(CallType.voice, targetId: 'bob');
      final oldCallId = signals
          .firstWhere((s) => s['type'] == 'call_invite')['callId'] as String;
      await session.handleCallSignal({
        'type': 'call_accept',
        'callId': oldCallId,
      });
      await Future<void>.delayed(Duration.zero);
      expect(session.state, CallState.connected);
      final oldPc = pcs.single;

      await session.hangupCall();
      expect(session.state, CallState.idle);
      expect(oldPc.closed, isTrue);

      // Second call with a distinct callId and a fresh peer connection.
      signals.clear();
      await session.startCall(CallType.voice, targetId: 'bob');
      final newCallId = signals
          .firstWhere((s) => s['type'] == 'call_invite')['callId'] as String;
      expect(newCallId, isNot(oldCallId));
      await session.handleCallSignal({
        'type': 'call_accept',
        'callId': newCallId,
      });
      await Future<void>.delayed(Duration.zero);
      expect(session.state, CallState.connected);
      final newPc = pcs.last;
      expect(identical(oldPc, newPc), isFalse);

      // Delayed signaling from the prior call must be ignored.
      await session.handleCallSignal({
        'type': 'call_sdp',
        'callId': oldCallId,
        'sdp': {'type': 'offer', 'sdp': 'v=0 old'},
      });
      await session.handleCallSignal({
        'type': 'call_ice',
        'callId': oldCallId,
        'candidate': {
          'candidate': 'candidate:old 1 UDP 1 127.0.0.1 9 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });
      await session.handleCallSignal({
        'type': 'call_hangup',
        'callId': oldCallId,
      });
      await Future<void>.delayed(Duration.zero);

      expect(session.state, CallState.connected);
      expect(newPc.setRemoteDescriptionCalls, 0);
      expect(newPc.addedCandidates, isEmpty);
      expect(signals.where((s) => s['type'] == 'call_hangup'), isEmpty);

      // Signaling for the current call still works.
      await session.handleCallSignal({
        'type': 'call_hangup',
        'callId': newCallId,
      });
      expect(session.state, CallState.idle);

      // Once idle, another late hangup is a harmless no-op.
      await session.handleCallSignal({
        'type': 'call_hangup',
        'callId': oldCallId,
      });
      expect(session.state, CallState.idle);

      session.dispose();
    });
  });
}

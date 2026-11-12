import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eir/models.dart';
import 'package:eir/core/call_session.dart';

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
  });
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Call State machine enum
enum CallState {
  idle,
  outgoing,
  incoming,
  connected,
}

/// Call media type
enum CallType {
  voice,
  video,
}

/// Chat message type
enum ChatMessageType {
  text,
  system,
}

/// Message model for Room Chat stream
class ChatMessage {
  final String id;
  final String senderDeviceId;
  final String senderName;
  final String? senderAvatar;
  final String text;
  final DateTime timestamp;
  final ChatMessageType type;
  final bool isSelf;
  final String? colorHex;

  ChatMessage({
    required this.id,
    required this.senderDeviceId,
    required this.senderName,
    this.senderAvatar,
    required this.text,
    required this.timestamp,
    this.type = ChatMessageType.text,
    this.isSelf = false,
    this.colorHex,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderDeviceId': senderDeviceId,
        'senderName': senderName,
        'senderAvatar': senderAvatar,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'colorHex': colorHex,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json,
      {required String currentDeviceId}) {
    final senderId = json['senderDeviceId'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderDeviceId: senderId,
      senderName: json['senderName'] as String? ?? 'User',
      senderAvatar: json['senderAvatar'] as String?,
      text: json['text'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      type: json['type'] == 'system'
          ? ChatMessageType.system
          : ChatMessageType.text,
      isSelf: senderId.isNotEmpty && senderId == currentDeviceId,
      colorHex: json['colorHex'] as String?,
    );
  }
}

/// Dedicated WebRTC Audio & Video Call Controller
class CallSession extends ChangeNotifier {
  final Future<void> Function(Map<String, dynamic> signal) sendSignal;
  final void Function(bool inCall)? onAudioDuckingChange;
  final String Function() getCurrentDeviceId;
  final String Function() getCurrentDisplayName;
  final String? Function() getCurrentAvatar;

  CallSession({
    required this.sendSignal,
    required this.getCurrentDeviceId,
    required this.getCurrentDisplayName,
    required this.getCurrentAvatar,
    this.onAudioDuckingChange,
  });

  CallState _state = CallState.idle;
  CallState get state => _state;

  CallType _type = CallType.voice;
  CallType get type => _type;

  String? _peerId;
  String? get peerId => _peerId;

  String? _peerName;
  String? get peerName => _peerName;

  String? _peerAvatar;
  String? get peerAvatar => _peerAvatar;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  bool _isMicMuted = false;
  bool get isMicMuted => _isMicMuted;

  bool _isCameraOff = false;
  bool get isCameraOff => _isCameraOff;

  bool _isSpeakerOn = true;
  bool get isSpeakerOn => _isSpeakerOn;

  bool _isPeerMicMuted = false;
  bool get isPeerMicMuted => _isPeerMicMuted;

  bool _isPeerCameraOff = false;
  bool get isPeerCameraOff => _isPeerCameraOff;

  bool _isPipMinimized = false;
  bool get isPipMinimized => _isPipMinimized;

  set isPipMinimized(bool val) {
    if (_isPipMinimized != val) {
      _isPipMinimized = val;
      notifyListeners();
    }
  }

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _callPc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  Timer? _durationTimer;
  Timer? _ringTimer;
  bool _renderersInitialized = false;
  bool _renderersUnavailable = false;
  final List<RTCIceCandidate> _pendingCallIce = <RTCIceCandidate>[];
  RTCSessionDescription? _pendingRemoteDesc;
  bool _remoteDescSet = false;

  Future<void> _flushPendingCallIce() async {
    if (_callPc == null || !_remoteDescSet) return;
    for (final cand in _pendingCallIce) {
      try {
        await _callPc!.addCandidate(cand);
      } catch (_) {}
    }
    _pendingCallIce.clear();
  }

  /// Initializes the local/remote renderers. Returns whether media rendering is
  /// available on this platform. Failures are remembered so an unsupported
  /// platform (or a test environment without the WebRTC plugin) does not block
  /// the call state machine or retry an initialization that can never finish.
  Future<bool> initRenderers() async {
    if (_renderersInitialized) return true;
    if (_renderersUnavailable) return false;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
      return true;
    } catch (e) {
      _renderersUnavailable = true;
      debugPrint('[CallSession] Renderer initialize error: $e');
      return false;
    }
  }

  /// Start outgoing call to peer
  Future<void> startCall(CallType callType,
      {String? targetId, String? targetName, String? targetAvatar}) async {
    if (_state != CallState.idle) return;

    _state = CallState.outgoing;
    _type = callType;
    _peerId = targetId;
    _peerName = targetName ?? 'Friend';
    _peerAvatar = targetAvatar;
    _isMicMuted = false;
    _isCameraOff = (callType == CallType.voice);
    _duration = Duration.zero;
    notifyListeners();

    // Send call invite signal over room transport
    await sendSignal({
      'type': 'call_invite',
      'callType': callType.name,
      'callerId': getCurrentDeviceId(),
      'callerName': getCurrentDisplayName(),
      'callerAvatar': getCurrentAvatar(),
    });

    // 35s Ring timeout
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 35), () {
      if (_state == CallState.outgoing) {
        hangupCall(reason: 'timeout');
      }
    });
  }

  /// Accept incoming call
  Future<void> acceptCall() async {
    if (_state != CallState.incoming) return;
    _ringTimer?.cancel();

    _state = CallState.connected;
    _isMicMuted = false;
    _isCameraOff = (_type == CallType.voice);
    _duration = Duration.zero;
    _startDurationTimer();
    onAudioDuckingChange?.call(true);
    notifyListeners();

    await sendSignal({
      'type': 'call_accept',
      'calleeId': getCurrentDeviceId(),
      'calleeName': getCurrentDisplayName(),
      'calleeAvatar': getCurrentAvatar(),
    });

    // Media setup runs in the background so accepting a call never blocks the
    // UI (or a test) on platform renderer/plugin availability.
    unawaited(_startCalleeMedia());
  }

  Future<void> _startCalleeMedia() async {
    if (_type == CallType.video) {
      await initRenderers();
    }
    if (_state != CallState.connected) return;
    try {
      await _setupPeerConnection(isCaller: false);
    } catch (e) {
      debugPrint('[CallSession] Peer connection setup error: $e');
    }
  }

  /// Decline incoming call
  Future<void> declineCall() async {
    if (_state != CallState.incoming) return;
    _ringTimer?.cancel();
    await sendSignal({
      'type': 'call_reject',
      'reason': 'declined',
    });
    _cleanup();
  }

  /// Hangup current call
  Future<void> hangupCall({String? reason}) async {
    if (_state == CallState.idle) return;
    _ringTimer?.cancel();
    try {
      await sendSignal({
        'type': 'call_hangup',
        'reason': reason ?? 'hangup',
      });
    } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    _ringTimer?.cancel();
    _durationTimer?.cancel();
    _duration = Duration.zero;
    _pendingCallIce.clear();
    _pendingRemoteDesc = null;
    _remoteDescSet = false;

    if (_renderersInitialized) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }

    _localStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _remoteStream?.dispose();
    _remoteStream = null;

    _callPc?.close();
    _callPc = null;

    final wasConnected = _state == CallState.connected;
    _state = CallState.idle;
    _peerId = null;
    _peerName = null;
    _peerAvatar = null;
    _isMicMuted = false;
    _isCameraOff = false;
    _isPeerMicMuted = false;
    _isPeerCameraOff = false;
    _isPipMinimized = false;

    if (wasConnected) {
      onAudioDuckingChange?.call(false);
    }
    notifyListeners();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state == CallState.connected) {
        _duration += const Duration(seconds: 1);
        notifyListeners();
      }
    });
  }

  /// Handle incoming call signaling from peer
  Future<void> handleCallSignal(Map<String, dynamic> data) async {
    final sigType = data['type'] as String?;
    if (sigType == null) return;

    switch (sigType) {
      case 'call_invite':
        final callerId = data['callerId'] as String?;
        // Ignore duplicate invite from the same caller (e.g. multi-path or retry)
        if ((_state == CallState.incoming || _state == CallState.connected) &&
            _peerId != null &&
            _peerId == callerId) {
          return;
        }
        if (_state != CallState.idle) {
          // Already in a call or dialing with someone else, reject busy
          await sendSignal({
            'type': 'call_reject',
            'reason': 'busy',
          });
          return;
        }
        _state = CallState.incoming;
        _type = (data['callType'] == 'video') ? CallType.video : CallType.voice;
        _peerId = callerId;
        _peerName = data['callerName'] as String? ?? 'Friend';
        _peerAvatar = data['callerAvatar'] as String?;
        _duration = Duration.zero;
        notifyListeners();

        // 35s Ring timeout
        _ringTimer?.cancel();
        _ringTimer = Timer(const Duration(seconds: 35), () {
          if (_state == CallState.incoming) {
            _cleanup();
          }
        });
        break;

      case 'call_accept':
        if (_state == CallState.outgoing) {
          _ringTimer?.cancel();
          _state = CallState.connected;
          _startDurationTimer();
          onAudioDuckingChange?.call(true);
          notifyListeners();

          // Caller creates WebRTC Offer. If video, try initializing renderers.
          if (_type == CallType.video) {
            await initRenderers();
          }
          if (_state == CallState.connected) {
            try {
              await _setupPeerConnection(isCaller: true);
            } catch (e) {
              debugPrint('[CallSession] Peer connection setup error: $e');
            }
          }
        }
        break;

      case 'call_reject':
        if (_state == CallState.outgoing || _state == CallState.incoming) {
          _cleanup();
        }
        break;

      case 'call_hangup':
        if (_state != CallState.idle) {
          _cleanup();
        }
        break;

      case 'call_sdp':
        final sdpMap = data['sdp'] as Map<String, dynamic>?;
        if (sdpMap != null) {
          final sdpType = sdpMap['type'] as String?;
          final sdpDesc = sdpMap['sdp'] as String?;
          if (sdpType != null && sdpDesc != null) {
            final desc = RTCSessionDescription(sdpDesc, sdpType);
            if (_callPc == null) {
              _pendingRemoteDesc = desc;
            } else {
              try {
                await _callPc!.setRemoteDescription(desc);
                _remoteDescSet = true;
                await _flushPendingCallIce();
                if (sdpType == 'offer') {
                  final answer = await _callPc!.createAnswer();
                  await _callPc!.setLocalDescription(answer);
                  await sendSignal({
                    'type': 'call_sdp',
                    'sdp': {'type': answer.type, 'sdp': answer.sdp},
                  });
                }
              } catch (e) {
                debugPrint('[CallSession] setRemoteDescription error: $e');
              }
            }
          }
        }
        break;

      case 'call_ice':
        final iceMap = data['candidate'] as Map<String, dynamic>?;
        if (iceMap != null) {
          final candidate = RTCIceCandidate(
            iceMap['candidate'] as String?,
            iceMap['sdpMid'] as String?,
            iceMap['sdpMLineIndex'] as int?,
          );
          if (_callPc != null && _remoteDescSet) {
            try {
              await _callPc!.addCandidate(candidate);
            } catch (_) {}
          } else {
            _pendingCallIce.add(candidate);
          }
        }
        break;

      case 'call_track_state':
        _isPeerMicMuted = data['micMuted'] as bool? ?? _isPeerMicMuted;
        _isPeerCameraOff = data['cameraOff'] as bool? ?? _isPeerCameraOff;
        notifyListeners();
        break;
    }
  }

  Future<void> _setupPeerConnection({required bool isCaller}) async {
    final Map<String, dynamic> config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    final pc = await createPeerConnection(config);
    _callPc = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        sendSignal({
          'type': 'call_ice',
          'candidate': candidate.toMap(),
        });
      }
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        remoteRenderer.srcObject = _remoteStream;
        notifyListeners();
      }
    };

    // Obtain local media with WebRTC echo cancellation & noise suppression
    // Using modern W3C ideal constraints compatible across modern Web and Native
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': (_type == CallType.video)
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            }
          : false,
    };

    try {
      final stream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = stream;
      localRenderer.srcObject = _localStream;

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[CallSession] getUserMedia error: $e');
      // If camera failed, fallback to audio only
      if (_type == CallType.video) {
        try {
          final audioStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
          _localStream = audioStream;
          localRenderer.srcObject = _localStream;
          for (final track in audioStream.getTracks()) {
            await pc.addTrack(track, audioStream);
          }
          _isCameraOff = true;
          notifyListeners();
        } catch (_) {}
      }
    }

    if (isCaller) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await sendSignal({
        'type': 'call_sdp',
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } else if (_pendingRemoteDesc != null) {
      final desc = _pendingRemoteDesc!;
      _pendingRemoteDesc = null;
      try {
        await pc.setRemoteDescription(desc);
        _remoteDescSet = true;
        await _flushPendingCallIce();
        if (desc.type == 'offer') {
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          await sendSignal({
            'type': 'call_sdp',
            'sdp': {'type': answer.type, 'sdp': answer.sdp},
          });
        }
      } catch (e) {
        debugPrint('[CallSession] setRemoteDescription on setup error: $e');
      }
    }
  }

  /// Toggle local microphone mute
  void toggleMic() {
    _isMicMuted = !_isMicMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMicMuted;
    });
    sendSignal({
      'type': 'call_track_state',
      'micMuted': _isMicMuted,
      'cameraOff': _isCameraOff,
    });
    notifyListeners();
  }

  /// Toggle local camera video stream
  void toggleCamera() {
    if (_type != CallType.video) return;
    _isCameraOff = !_isCameraOff;
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isCameraOff;
    });
    sendSignal({
      'type': 'call_track_state',
      'micMuted': _isMicMuted,
      'cameraOff': _isCameraOff,
    });
    notifyListeners();
  }

  /// Switch front/back camera
  Future<void> switchCamera() async {
    if (kIsWeb) return;
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      try {
        await Helper.switchCamera(videoTrack);
        notifyListeners();
      } catch (e) {
        debugPrint('[CallSession] switchCamera error: $e');
      }
    }
  }

  /// Toggle speakerphone
  void toggleSpeaker() {
    if (kIsWeb) return;
    _isSpeakerOn = !_isSpeakerOn;
    try {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }
}

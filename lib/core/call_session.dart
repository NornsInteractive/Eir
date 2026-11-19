import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'room_session.dart';

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
  final Future<RTCPeerConnection> Function(Map<String, dynamic> config)?
      createPeerConnectionOverride;
  final Future<MediaStream> Function(Map<String, dynamic> constraints)?
      getUserMediaOverride;

  CallSession({
    required this.sendSignal,
    required this.getCurrentDeviceId,
    required this.getCurrentDisplayName,
    required this.getCurrentAvatar,
    this.onAudioDuckingChange,
    this.createPeerConnectionOverride,
    this.getUserMediaOverride,
  });

  int _generation = 0;
  bool _disposed = false;

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

  // Identity of the current call, echoed on every call signal so delayed
  // signaling from a previous call cannot mutate a newer one. Signals without
  // a callId are still accepted (backward compatibility with older/peers that
  // do not tag them).
  String? _callId;
  String _newCallId() => const Uuid().v4();

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

  bool get hasRemoteStream => _remoteStream != null;

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation;

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
    if (_disposed || _state != CallState.idle) return;
    final generation = ++_generation;
    final callId = _newCallId();
    _callId = callId;

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
      'callId': callId,
      'callType': callType.name,
      'callerId': getCurrentDeviceId(),
      'callerName': getCurrentDisplayName(),
      'callerAvatar': getCurrentAvatar(),
    });
    if (!_isCurrent(generation)) return;

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
    if (_disposed || _state != CallState.incoming) return;
    _ringTimer?.cancel();
    final generation = ++_generation;
    _callId ??= _newCallId();

    _state = CallState.connected;
    _isMicMuted = false;
    _isCameraOff = (_type == CallType.voice);
    _duration = Duration.zero;
    _startDurationTimer();
    onAudioDuckingChange?.call(true);
    notifyListeners();

    await sendSignal({
      'type': 'call_accept',
      'callId': _callId,
      'calleeId': getCurrentDeviceId(),
      'calleeName': getCurrentDisplayName(),
      'calleeAvatar': getCurrentAvatar(),
    });
    if (!_isCurrent(generation)) return;

    // Media setup runs in the background so accepting a call never blocks the
    // UI (or a test) on platform renderer/plugin availability.
    unawaited(_startCalleeMedia(generation));
  }

  Future<void> _startCalleeMedia(int generation) async {
    if (_type == CallType.video) {
      await initRenderers();
    }
    if (!_isCurrent(generation) || _state != CallState.connected) return;
    try {
      await _setupPeerConnection(isCaller: false, generation: generation);
    } catch (e) {
      debugPrint('[CallSession] Peer connection setup error: $e');
    }
  }

  /// Decline incoming call
  Future<void> declineCall() async {
    if (_state != CallState.incoming) return;
    _ringTimer?.cancel();
    final generation = ++_generation;
    await sendSignal({
      'type': 'call_reject',
      'callId': _callId,
      'reason': 'declined',
    });
    if (!_isCurrent(generation)) return;
    _cleanup();
  }

  /// Hangup current call
  Future<void> hangupCall({String? reason}) async {
    if (_state == CallState.idle) return;
    _ringTimer?.cancel();
    final generation = ++_generation;
    try {
      await sendSignal({
        'type': 'call_hangup',
        'callId': _callId,
        'reason': reason ?? 'hangup',
      });
    } catch (_) {}
    if (!_isCurrent(generation)) return;
    _cleanup();
  }

  void _cleanup() {
    _generation++;
    _callId = null;
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
    unawaited(_localStream?.dispose() ?? Future<void>.value());
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    unawaited(_remoteStream?.dispose() ?? Future<void>.value());
    _remoteStream = null;

    unawaited(_closeCallPeerConnection(_callPc));
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

    // A tagged signal that belongs to a different call is stale: drop it
    // before it can touch the current session. Untagged signals are still
    // accepted for backward compatibility.
    final signalCallId = data['callId'] as String?;
    if (sigType != 'call_invite' &&
        signalCallId != null &&
        signalCallId != _callId) {
      return;
    }

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
            'callId': signalCallId ?? _callId,
            'reason': 'busy',
          });
          return;
        }
        _callId = signalCallId ?? _newCallId();
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
          final generation = ++_generation;
          _state = CallState.connected;
          _startDurationTimer();
          onAudioDuckingChange?.call(true);
          notifyListeners();

          // Caller creates WebRTC Offer. If video, try initializing renderers.
          if (_type == CallType.video) {
            await initRenderers();
          }
          if (_isCurrent(generation) && _state == CallState.connected) {
            try {
              await _setupPeerConnection(
                isCaller: true,
                generation: generation,
              );
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
        // SDP is only meaningful inside an accepted call. Dropping it in any
        // other state prevents a late offer/answer from an ended call being
        // buffered and later applied to a new call.
        if (_state != CallState.connected) return;
        final sdpMap = data['sdp'] as Map<String, dynamic>?;
        if (sdpMap != null) {
          final sdpType = sdpMap['type'] as String?;
          final sdpDesc = sdpMap['sdp'] as String?;
          if (sdpType != null && sdpDesc != null) {
            final desc = RTCSessionDescription(sdpDesc, sdpType);
            final generation = _generation;
            if (_callPc == null) {
              _pendingRemoteDesc = desc;
            } else {
              final pc = _callPc!;
              bool stillCurrent() =>
                  _isCurrent(generation) &&
                  _state == CallState.connected &&
                  identical(_callPc, pc);
              try {
                await pc.setRemoteDescription(desc);
                if (!stillCurrent()) return;
                _remoteDescSet = true;
                await _flushPendingCallIce();
                if (!stillCurrent()) return;
                if (sdpType == 'offer') {
                  final answer = await pc.createAnswer();
                  if (!stillCurrent()) return;
                  await pc.setLocalDescription(answer);
                  if (!stillCurrent()) return;
                  await sendSignal({
                    'type': 'call_sdp',
                    'callId': _callId,
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
        if (_state != CallState.connected) return;
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

  Future<void> _setupPeerConnection({
    required bool isCaller,
    required int generation,
  }) async {
    final Map<String, dynamic> config = {
      'iceServers': RoomSession.effectiveIceServers,
      'sdpSemantics': 'unified-plan',
    };

    final pc = await (createPeerConnectionOverride ?? createPeerConnection)(
      config,
    );
    if (!_isCurrent(generation) || _state != CallState.connected) {
      await _closeCallPeerConnection(pc);
      return;
    }
    _callPc = pc;
    bool stillCurrent() =>
        _isCurrent(generation) &&
        _state == CallState.connected &&
        identical(_callPc, pc);

    pc.onIceCandidate = (candidate) {
      if (!stillCurrent()) return;
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        sendSignal({
          'type': 'call_ice',
          'callId': _callId,
          'candidate': candidate.toMap(),
        });
      }
    };

    pc.onTrack = (event) {
      if (!stillCurrent()) return;
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        if (_renderersInitialized) {
          remoteRenderer.srcObject = _remoteStream;
        }
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
    final getMedia = getUserMediaOverride ??
        (Map<String, dynamic> constraints) =>
            navigator.mediaDevices.getUserMedia(constraints);

    try {
      final stream = await getMedia(mediaConstraints);
      if (!stillCurrent()) {
        await _disposeCallStream(stream);
        return;
      }
      _localStream = stream;
      if (_renderersInitialized) localRenderer.srcObject = _localStream;

      for (final track in stream.getTracks()) {
        if (!stillCurrent()) {
          await _disposeCallStream(stream);
          return;
        }
        await pc.addTrack(track, stream);
      }
      if (!stillCurrent()) return;
      notifyListeners();
    } catch (e) {
      if (!stillCurrent()) return;
      debugPrint('[CallSession] getUserMedia error: $e');
      // If camera failed, fallback to audio only
      if (_type == CallType.video) {
        try {
          final audioStream = await getMedia({
            'audio': true,
            'video': false,
          });
          if (!stillCurrent()) {
            await _disposeCallStream(audioStream);
            return;
          }
          _localStream = audioStream;
          if (_renderersInitialized) {
            localRenderer.srcObject = _localStream;
          }
          for (final track in audioStream.getTracks()) {
            if (!stillCurrent()) {
              await _disposeCallStream(audioStream);
              return;
            }
            await pc.addTrack(track, audioStream);
          }
          if (!stillCurrent()) return;
          _isCameraOff = true;
          notifyListeners();
        } catch (_) {}
      }
    }

    if (!stillCurrent()) return;
    if (isCaller) {
      final offer = await pc.createOffer();
      if (!stillCurrent()) return;
      await pc.setLocalDescription(offer);
      if (!stillCurrent()) return;
      await sendSignal({
        'type': 'call_sdp',
        'callId': _callId,
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } else if (_pendingRemoteDesc != null) {
      final desc = _pendingRemoteDesc!;
      _pendingRemoteDesc = null;
      try {
        await pc.setRemoteDescription(desc);
        if (!stillCurrent()) return;
        _remoteDescSet = true;
        await _flushPendingCallIce();
        if (!stillCurrent()) return;
        if (desc.type == 'offer') {
          final answer = await pc.createAnswer();
          if (!stillCurrent()) return;
          await pc.setLocalDescription(answer);
          if (!stillCurrent()) return;
          await sendSignal({
            'type': 'call_sdp',
            'callId': _callId,
            'sdp': {'type': answer.type, 'sdp': answer.sdp},
          });
        }
      } catch (e) {
        debugPrint('[CallSession] setRemoteDescription on setup error: $e');
      }
    }
  }

  Future<void> _disposeCallStream(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (e) {
        debugPrint('[CallSession] track stop error: $e');
      }
    }
    try {
      await stream.dispose();
    } catch (e) {
      debugPrint('[CallSession] stream dispose error: $e');
    }
  }

  Future<void> _closeCallPeerConnection(RTCPeerConnection? pc) async {
    if (pc == null) return;
    try {
      await pc.close();
    } catch (e) {
      debugPrint('[CallSession] peer connection close error: $e');
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
      'callId': _callId,
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
      'callId': _callId,
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
    if (_disposed) return;
    _disposed = true;
    _cleanup();
    unawaited(localRenderer.dispose());
    unawaited(remoteRenderer.dispose());
    super.dispose();
  }
}

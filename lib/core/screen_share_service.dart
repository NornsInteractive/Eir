import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Screen sharing role
enum ScreenShareRole {
  none,
  broadcaster,
  viewer,
}

/// Screen sharing state machine
enum ScreenShareState {
  idle,
  selectingSource,
  connecting,
  active,
  error,
}

/// High-FPS Screen & Application Window Sharing Service
class ScreenShareService extends ChangeNotifier {
  final Future<void> Function(Map<String, dynamic> signal) sendSignal;
  final String Function() getCurrentDeviceId;
  final String Function() getCurrentDisplayName;
  final String? Function() getCurrentAvatar;
  final List<Map<String, dynamic>> Function()? getIceServers;

  ScreenShareService({
    required this.sendSignal,
    required this.getCurrentDeviceId,
    required this.getCurrentDisplayName,
    required this.getCurrentAvatar,
    this.getIceServers,
  });

  ScreenShareRole _role = ScreenShareRole.none;
  ScreenShareRole get role => _role;

  ScreenShareState _state = ScreenShareState.idle;
  ScreenShareState get state => _state;

  bool get isBroadcasting => _role == ScreenShareRole.broadcaster && _state == ScreenShareState.active;
  bool get isBroadcaster => _role == ScreenShareRole.broadcaster;
  bool get isViewing => _role == ScreenShareRole.viewer && _state == ScreenShareState.active;
  bool get isViewer => _role == ScreenShareRole.viewer;
  bool get isActive => _state == ScreenShareState.active;

  String? _activeCastCode;
  String? get activeCastCode => _activeCastCode;

  String? _sourceTitle;
  String? get sourceTitle => _sourceTitle;

  String? _sourceType;
  String? get sourceType => _sourceType;

  int _targetFps = 60;
  int get targetFps => _targetFps;

  bool _isAudioEnabled = true;
  bool get isAudioEnabled => _isAudioEnabled;

  bool _isMicEnabled = false;
  bool get isMicEnabled => _isMicEnabled;

  double _volume = 1.0;
  double get volume => _volume;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;
  Timer? _durationTimer;

  // WebRTC Renderers
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;
  bool get renderersInitialized => _renderersInitialized;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _micStream;

  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteDescSet = false;

  /// Initialize video renderers for local preview and remote playback
  Future<void> initRenderers() async {
    if (_renderersInitialized) return;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ScreenShareService] initRenderers error: $e');
    }
  }

  /// Start broadcasting screen or a specific window at 60 FPS
  Future<bool> startBroadcasting({
    DesktopCapturerSource? source,
    bool shareAudio = true,
    int targetFps = 60,
    String? customTitle,
    String? castCode,
  }) async {
    _state = ScreenShareState.connecting;
    _role = ScreenShareRole.broadcaster;
    _activeCastCode = castCode;
    _targetFps = targetFps;
    _isAudioEnabled = shareAudio;
    _sourceTitle = customTitle ?? source?.name ?? (source == null ? '全屏幕' : '应用窗口');
    _sourceType = source?.type == SourceType.Window ? 'window' : 'screen';
    _lastError = null;
    notifyListeners();

    await initRenderers();

    try {
      // Platform-specific capture permission handling
      if (!kIsWeb && WebRTC.platformIsAndroid) {
        try {
          await Helper.requestCapturePermission();
        } catch (e) {
          debugPrint('[ScreenShareService] Android capture permission error: $e');
        }
      }

      // Constraints enforcing 60 FPS and audio loopback
      final mediaConstraints = <String, dynamic>{
        'audio': shareAudio,
        'video': source == null
            ? {
                'mandatory': {
                  'minFrameRate': '30',
                  'idealFrameRate': '$targetFps',
                  'maxFrameRate': '$targetFps',
                }
              }
            : {
                'deviceId': {'exact': source.id},
                'mandatory': {
                  'minFrameRate': '30',
                  'idealFrameRate': '$targetFps',
                  'maxFrameRate': '$targetFps',
                }
              },
      };

      try {
        _localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      } catch (e) {
        // Fallback for environments where getDisplayMedia with constraints fails
        _localStream = await navigator.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': shareAudio,
        });
      }

      if (_localStream != null) {
        localRenderer.srcObject = _localStream;
        // Listen for user stopping sharing via system UI
        for (final track in _localStream!.getVideoTracks()) {
          track.onEnded = () {
            stop(reason: 'user_ended_from_system');
          };
        }
      }

      await _setupPeerConnection(isBroadcaster: true);

      _state = ScreenShareState.active;
      _startedAt = DateTime.now();
      _startDurationTimer();
      notifyListeners();

      // Broadcast share ready signal to room/code
      await sendSignal({
        'type': 'screen_share_started',
        'broadcasterId': getCurrentDeviceId(),
        'broadcasterName': getCurrentDisplayName(),
        'broadcasterAvatar': getCurrentAvatar(),
        'sourceTitle': _sourceTitle,
        'sourceType': _sourceType,
        'castCode': _activeCastCode,
        'hasAudio': _isAudioEnabled,
        'targetFps': _targetFps,
      });

      return true;
    } catch (e) {
      debugPrint('[ScreenShareService] startBroadcasting error: $e');
      _state = ScreenShareState.error;
      _lastError = e.toString();
      _cleanup();
      notifyListeners();
      return false;
    }
  }

  /// Start viewing a broadcast by cast code
  Future<bool> startViewing({required String castCode}) async {
    _state = ScreenShareState.connecting;
    _role = ScreenShareRole.viewer;
    _activeCastCode = castCode;
    _lastError = null;
    notifyListeners();

    await initRenderers();

    try {
      await _setupPeerConnection(isBroadcaster: false);

      _state = ScreenShareState.active;
      _startedAt = DateTime.now();
      _startDurationTimer();
      notifyListeners();

      // Notify streamer that a viewer has joined
      await sendSignal({
        'type': 'screen_share_viewer_join',
        'viewerId': getCurrentDeviceId(),
        'viewerName': getCurrentDisplayName(),
        'viewerAvatar': getCurrentAvatar(),
        'castCode': castCode,
      });

      return true;
    } catch (e) {
      debugPrint('[ScreenShareService] startViewing error: $e');
      _state = ScreenShareState.error;
      _lastError = e.toString();
      _cleanup();
      notifyListeners();
      return false;
    }
  }

  /// Setup WebRTC peer connection
  Future<void> _setupPeerConnection({required bool isBroadcaster}) async {
    final iceServers = getIceServers?.call() ?? [
      {'urls': 'stun:stun.l.google.com:19302'},
    ];

    final rtcConfig = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    _pc = await createPeerConnection(rtcConfig);

    _pc!.onIceCandidate = (candidate) {
      sendSignal({
        'type': 'screen_share_ice',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        'castCode': _activeCastCode,
      });
    };

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        remoteRenderer.srcObject = _remoteStream;
        notifyListeners();
      }
    };

    if (isBroadcaster && _localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      // Create Offer for viewers
      final offer = await _pc!.createOffer({
        'offerToReceiveVideo': 0,
        'offerToReceiveAudio': 1,
      });
      await _pc!.setLocalDescription(offer);

      await sendSignal({
        'type': 'screen_share_sdp',
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
        'sourceTitle': _sourceTitle,
        'sourceType': _sourceType,
        'castCode': _activeCastCode,
      });
    }
  }

  /// Handle incoming screen share signaling message
  Future<void> handleSignal(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'screen_share_started':
        _sourceTitle = data['sourceTitle'] as String? ?? _sourceTitle;
        _sourceType = data['sourceType'] as String? ?? _sourceType;
        _targetFps = (data['targetFps'] as num?)?.toInt() ?? _targetFps;
        notifyListeners();
        break;

      case 'screen_share_viewer_join':
        // If we are broadcasting, renegotiate / send offer to newly joined viewer
        if (_role == ScreenShareRole.broadcaster && _pc != null) {
          try {
            final offer = await _pc!.createOffer({
              'offerToReceiveVideo': 0,
              'offerToReceiveAudio': 1,
            });
            await _pc!.setLocalDescription(offer);
            await sendSignal({
              'type': 'screen_share_sdp',
              'sdp': {'type': offer.type, 'sdp': offer.sdp},
              'sourceTitle': _sourceTitle,
              'sourceType': _sourceType,
              'castCode': _activeCastCode,
            });
          } catch (e) {
            debugPrint('[ScreenShareService] Viewer join renegotiation error: $e');
          }
        }
        break;

      case 'screen_share_sdp':
        final sdpMap = data['sdp'] as Map<String, dynamic>?;
        if (sdpMap == null) return;
        final sdpType = sdpMap['type'] as String?;
        final sdpDesc = sdpMap['sdp'] as String?;
        if (sdpType == null || sdpDesc == null) return;

        final desc = RTCSessionDescription(sdpDesc, sdpType);
        if (_pc == null) {
          await _setupPeerConnection(isBroadcaster: _role == ScreenShareRole.broadcaster);
        }

        try {
          await _pc!.setRemoteDescription(desc);
          _remoteDescSet = true;
          await _flushPendingIce();

          if (sdpType == 'offer') {
            final answer = await _pc!.createAnswer({
              'offerToReceiveVideo': 1,
              'offerToReceiveAudio': 1,
            });
            await _pc!.setLocalDescription(answer);
            await sendSignal({
              'type': 'screen_share_sdp',
              'sdp': {'type': answer.type, 'sdp': answer.sdp},
              'castCode': _activeCastCode,
            });
          }
        } catch (e) {
          debugPrint('[ScreenShareService] SDP exchange error: $e');
        }
        break;

      case 'screen_share_ice':
        final iceMap = data['candidate'] as Map<String, dynamic>?;
        if (iceMap != null) {
          final candidate = RTCIceCandidate(
            iceMap['candidate'] as String?,
            iceMap['sdpMid'] as String?,
            iceMap['sdpMLineIndex'] as int?,
          );
          if (_pc != null && _remoteDescSet) {
            try {
              await _pc!.addCandidate(candidate);
            } catch (_) {}
          } else {
            _pendingIce.add(candidate);
          }
        }
        break;

      case 'screen_share_stop':
        stop(reason: data['reason'] as String? ?? 'remote_stopped');
        break;
    }
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null || !_remoteDescSet) return;
    for (final cand in _pendingIce) {
      try {
        await _pc!.addCandidate(cand);
      } catch (_) {}
    }
    _pendingIce.clear();
  }

  /// Stop sharing or viewing
  Future<void> stop({String? reason}) async {
    if (_state == ScreenShareState.idle) return;

    try {
      await sendSignal({
        'type': 'screen_share_stop',
        'reason': reason ?? 'user_action',
        'castCode': _activeCastCode,
      });
    } catch (_) {}

    _cleanup();
    _state = ScreenShareState.idle;
    _role = ScreenShareRole.none;
    _activeCastCode = null;
    notifyListeners();
  }

  void _cleanup() {
    _durationTimer?.cancel();
    _duration = Duration.zero;
    _pendingIce.clear();
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

    _micStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _micStream?.dispose();
    _micStream = null;

    _remoteStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _remoteStream?.dispose();
    _remoteStream = null;

    _pc?.close();
    _pc = null;
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _duration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  /// Set remote audio volume (0.0 to 1.0)
  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    _isMuted = _volume == 0.0;
    notifyListeners();
  }

  /// Toggle mute state
  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  /// Toggle microphone talkback during screen share
  Future<void> toggleMic() async {
    _isMicEnabled = !_isMicEnabled;
    if (_isMicEnabled) {
      try {
        _micStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
        if (_pc != null && _micStream != null) {
          for (final track in _micStream!.getAudioTracks()) {
            await _pc!.addTrack(track, _micStream!);
          }
        }
      } catch (e) {
        debugPrint('[ScreenShareService] Mic enable error: $e');
        _isMicEnabled = false;
      }
    } else {
      _micStream?.getTracks().forEach((track) {
        try {
          track.stop();
        } catch (_) {}
      });
      _micStream?.dispose();
      _micStream = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    if (_renderersInitialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}

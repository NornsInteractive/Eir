import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'call_session.dart' show ChatMessage;

/// Screen sharing role
enum ScreenShareRole { none, broadcaster, viewer }

/// Screen sharing state machine
enum ScreenShareState { idle, selectingSource, connecting, active, error }

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
  }) {
    _setupNativeMethodCallHandler();
  }

  ScreenShareRole _role = ScreenShareRole.none;
  ScreenShareRole get role => _role;

  ScreenShareState _state = ScreenShareState.idle;
  ScreenShareState get state => _state;

  bool get isBroadcasting =>
      _role == ScreenShareRole.broadcaster && _state == ScreenShareState.active;
  bool get isBroadcaster => _role == ScreenShareRole.broadcaster;
  bool get isViewing =>
      _role == ScreenShareRole.viewer && _state == ScreenShareState.active;
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

  double _companionVolume = 1.0;
  double get companionVolume => _companionVolume;

  double _voiceVolume = 1.0;
  double get voiceVolume => _voiceVolume;

  bool _isAudioDuckingEnabled = true;
  bool get isAudioDuckingEnabled => _isAudioDuckingEnabled;

  bool _isCoverMode = false;
  bool get isCoverMode => _isCoverMode;

  final StreamController<String> _reactionController =
      StreamController<String>.broadcast();
  Stream<String> get onReaction => _reactionController.stream;

  // In-cast Real-time Messaging
  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  final StreamController<ChatMessage> _chatController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onChatMessage => _chatController.stream;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _danmakuEnabled = true;
  bool get danmakuEnabled => _danmakuEnabled;

  // Viewer connection tracking
  int _viewerCount = 0;
  int get viewerCount => _viewerCount;
  bool get hasViewer => _viewerCount > 0;

  void markMessagesAsRead() {
    if (_unreadCount > 0) {
      _unreadCount = 0;
      notifyListeners();
    }
  }

  void toggleDanmaku() {
    _danmakuEnabled = !_danmakuEnabled;
    notifyListeners();
  }

  // Camera Video Talkback (Picture-in-Picture)
  bool _isCameraEnabled = false;
  bool get isCameraEnabled => _isCameraEnabled;

  bool _isRemoteCameraActive = false;
  bool get isRemoteCameraActive => _isRemoteCameraActive;

  bool _isFrontCamera = true;
  bool get isFrontCamera => _isFrontCamera;

  final RTCVideoRenderer localCameraRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteCameraRenderer = RTCVideoRenderer();
  bool _cameraRenderersInitialized = false;
  bool get cameraRenderersInitialized => _cameraRenderersInitialized;

  MediaStream? _cameraStream;
  RTCRtpSender? _cameraSender;

  // Stream health statistics
  int _rttMs = 0;
  int get rttMs => _rttMs;
  double _bitrateMbps = 0.0;
  double get bitrateMbps => _bitrateMbps;
  double _packetLoss = 0.0;
  double get packetLoss => _packetLoss;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;
  Timer? _durationTimer;
  Timer? _handshakeWatchdogTimer;

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
  final List<RTCIceCandidate> _cachedLocalIce = [];
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

  /// Initialize camera video renderers
  Future<void> initCameraRenderers() async {
    if (_cameraRenderersInitialized) return;
    try {
      await localCameraRenderer.initialize();
      await remoteCameraRenderer.initialize();
      _cameraRenderersInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[ScreenShareService] initCameraRenderers error: $e');
    }
  }

  /// Start broadcasting screen or a specific window at 60 FPS
  Future<bool> startBroadcasting({
    DesktopCapturerSource? source,
    bool shareAudio = true,
    int targetFps = 60,
    String? customTitle,
    String? castCode,
    bool enableFloatingChat = true,
  }) async {
    _state = ScreenShareState.connecting;
    _role = ScreenShareRole.broadcaster;
    _activeCastCode = castCode;
    _targetFps = targetFps;
    _isAudioEnabled = shareAudio;
    _sourceTitle =
        customTitle ?? source?.name ?? (source == null ? '全屏幕' : '应用窗口');
    _sourceType = source?.type == SourceType.Window ? 'window' : 'screen';
    _lastError = null;
    notifyListeners();

    await initRenderers();

    try {
      // Platform-specific capture permission handling & Android MediaProjection Foreground Service
      if (!kIsWeb && WebRTC.platformIsAndroid) {
        // In Android 14+ (API 34+), the system screen capture prompt must be granted
        // BEFORE starting the MediaProjection foreground service to avoid SecurityException.
        bool granted = false;
        try {
          granted = await Helper.requestCapturePermission();
        } catch (e) {
          debugPrint(
            '[ScreenShareService] Android capture permission error: $e',
          );
        }
        if (!granted) {
          debugPrint('[ScreenShareService] Screen capture permission denied by user.');
          _state = ScreenShareState.idle;
          _role = ScreenShareRole.none;
          _lastError = '用户取消或未授予屏幕录制权限';
          _cleanup();
          notifyListeners();
          return false;
        }

        try {
          await const MethodChannel(
            'com.norns.eir/media_picker',
          ).invokeMethod('startMediaProjectionService', {
            'enableFloatingChat': enableFloatingChat,
          });
        } catch (e) {
          debugPrint(
            '[ScreenShareService] startMediaProjectionService error: $e',
          );
        }
      }

      // Platform-tailored constraints avoiding Android MediaProjection black screen
      final mediaConstraints = (!kIsWeb && WebRTC.platformIsAndroid)
          ? <String, dynamic>{'audio': shareAudio, 'video': true}
          : <String, dynamic>{
              'audio': shareAudio,
              'video': source == null
                  ? {
                      'mandatory': {
                        'minFrameRate': '30',
                        'idealFrameRate': '$targetFps',
                        'maxFrameRate': '$targetFps',
                      },
                    }
                  : {
                      'deviceId': {'exact': source.id},
                      'mandatory': {
                        'minFrameRate': '30',
                        'idealFrameRate': '$targetFps',
                        'maxFrameRate': '$targetFps',
                      },
                    },
            };

      try {
        _localStream = await navigator.mediaDevices.getDisplayMedia(
          mediaConstraints,
        );
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

  /// Prepare viewing state before joining signaling room
  void prepareViewing({required String castCode}) {
    _role = ScreenShareRole.viewer;
    _state = ScreenShareState.connecting;
    _activeCastCode = castCode;
    _lastError = null;
    notifyListeners();
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

      // Watchdog: If no video track arrives after 4 seconds, re-request offer
      _handshakeWatchdogTimer?.cancel();
      _handshakeWatchdogTimer = Timer(const Duration(seconds: 4), () async {
        if (_role == ScreenShareRole.viewer &&
            (remoteRenderer.srcObject == null || _remoteStream == null)) {
          debugPrint('[ScreenShareService] Handshake watchdog: re-sending viewer_join');
          try {
            await sendSignal({
              'type': 'screen_share_viewer_join',
              'viewerId': getCurrentDeviceId(),
              'viewerName': getCurrentDisplayName(),
              'viewerAvatar': getCurrentAvatar(),
              'castCode': castCode,
            });
          } catch (_) {}
        }
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

  /// Manually retry viewer signaling handshake
  Future<void> retryViewerHandshake() async {
    if (_role != ScreenShareRole.viewer || _activeCastCode == null) return;
    try {
      debugPrint('[ScreenShareService] Manual retry viewer handshake for $_activeCastCode');
      await sendSignal({
        'type': 'screen_share_viewer_join',
        'viewerId': getCurrentDeviceId(),
        'viewerName': getCurrentDisplayName(),
        'viewerAvatar': getCurrentAvatar(),
        'castCode': _activeCastCode!,
      });
    } catch (_) {}
  }

  /// Setup WebRTC peer connection
  Future<void> _setupPeerConnection({required bool isBroadcaster}) async {
    final iceServers =
        getIceServers?.call() ??
        [
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
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _cachedLocalIce.add(candidate);
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

    _pc!.onConnectionState = (state) {
      debugPrint('[ScreenShareService] PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _state = ScreenShareState.active;
        if (isBroadcaster) {
          _viewerCount = math.max(1, _viewerCount);
        }
        notifyListeners();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (!isBroadcaster) {
          _state = ScreenShareState.error;
        }
        notifyListeners();
      }
    };

    _pc!.onIceConnectionState = (state) {
      debugPrint('[ScreenShareService] ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _state = ScreenShareState.active;
        if (isBroadcaster) {
          _viewerCount = math.max(1, _viewerCount);
        }
        notifyListeners();
      }
    };

    _pc!.onTrack = (event) async {
      debugPrint(
        '[ScreenShareService] onTrack kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}',
      );
      if (event.track.kind == 'video') {
        // If main remote stream has no video track yet, bind this track as primary screen canvas
        if (_remoteStream == null || _remoteStream!.getVideoTracks().isEmpty) {
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
          } else {
            _remoteStream ??= await createLocalMediaStream('remote_screen_stream');
            _remoteStream!.addTrack(event.track);
          }
          remoteRenderer.srcObject = _remoteStream;
        } else {
          // Additional video track -> remote camera PiP
          _isRemoteCameraActive = true;
          if (event.streams.isNotEmpty) {
            remoteCameraRenderer.srcObject = event.streams.first;
          } else {
            final camStream = await createLocalMediaStream('remote_camera_stream');
            camStream.addTrack(event.track);
            remoteCameraRenderer.srcObject = camStream;
          }
        }
        notifyListeners();
      } else if (event.track.kind == 'audio') {
        if (_remoteStream == null) {
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
          } else {
            _remoteStream = await createLocalMediaStream('remote_screen_stream');
            _remoteStream!.addTrack(event.track);
          }
        } else {
          _remoteStream!.addTrack(event.track);
        }
        if (_remoteStream!.getVideoTracks().isNotEmpty) {
          remoteRenderer.srcObject = _remoteStream;
        }
        notifyListeners();
      }
    };

    if (!isBroadcaster) {
      try {
        await _pc!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        await _pc!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      } catch (e) {
        debugPrint('[ScreenShareService] addTransceiver error: $e');
      }
    }

    if (isBroadcaster && _localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
      await _sendOfferToViewer(restartIce: false);
    }
  }

  /// Safely generate, munge, set local description, send offer, and forward all cached ICE candidates
  Future<void> _sendOfferToViewer({bool restartIce = false}) async {
    if (_pc == null || _role != ScreenShareRole.broadcaster) return;

    try {
      final state = await _pc!.getSignalingState();
      RTCSessionDescription? offer;

      if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer && !restartIce) {
        // Reuse current valid local offer that hasn't been answered yet
        offer = await _pc!.getLocalDescription();
      } else {
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          try {
            await _pc!.setLocalDescription(RTCSessionDescription('', 'rollback'));
          } catch (_) {}
        }
        final rawOffer = await _pc!.createOffer({
          'offerToReceiveVideo': 0,
          'offerToReceiveAudio': 1,
          if (restartIce) 'iceRestart': true,
        });
        final mungedSdp = _preferCodec(rawOffer.sdp ?? '', 'VP8');
        offer = RTCSessionDescription(mungedSdp, rawOffer.type);
        await _pc!.setLocalDescription(offer);
      }

      if (offer != null) {
        await sendSignal({
          'type': 'screen_share_sdp',
          'sdp': {'type': offer.type, 'sdp': offer.sdp},
          'sourceTitle': _sourceTitle,
          'sourceType': _sourceType,
          'castCode': _activeCastCode,
        });

        // Forward all gathered ICE candidates to the viewer
        for (final cand in _cachedLocalIce) {
          await sendSignal({
            'type': 'screen_share_ice',
            'candidate': {
              'candidate': cand.candidate,
              'sdpMid': cand.sdpMid,
              'sdpMLineIndex': cand.sdpMLineIndex,
            },
            'castCode': _activeCastCode,
          });
        }
      }
    } catch (e) {
      debugPrint('[ScreenShareService] _sendOfferToViewer error: $e');
    }
  }

  /// Prioritize a specific video codec (e.g. VP8) in SDP for universal browser decoding
  String _preferCodec(String sdp, String codec) {
    if (sdp.isEmpty) return sdp;
    final lines = sdp.split('\r\n');
    final mVideoIndex = lines.indexWhere((l) => l.startsWith('m=video '));
    if (mVideoIndex == -1) return sdp;

    final codecPtRegex = RegExp(
      r'^a=rtpmap:(\d+)\s+' + RegExp.escape(codec) + r'/',
      caseSensitive: false,
    );
    final pts = <String>[];
    for (final line in lines) {
      final match = codecPtRegex.firstMatch(line);
      if (match != null) {
        pts.add(match.group(1)!);
      }
    }
    if (pts.isEmpty) return sdp;

    final parts = lines[mVideoIndex].split(' ');
    if (parts.length <= 3) return sdp;

    final header = parts.sublist(0, 3);
    final existingPts = parts.sublist(3);

    final newPts = <String>[...pts];
    for (final pt in existingPts) {
      if (!newPts.contains(pt)) {
        newPts.add(pt);
      }
    }

    lines[mVideoIndex] = '${header.join(' ')} ${newPts.join(' ')}';
    return lines.join('\r\n');
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
        _viewerCount = math.max(1, _viewerCount);
        notifyListeners();

        // If we are broadcasting, safely send offer & candidates to newly joined viewer
        if (_role == ScreenShareRole.broadcaster && _pc != null) {
          await _sendOfferToViewer(restartIce: false);
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
          await _setupPeerConnection(
            isBroadcaster: _role == ScreenShareRole.broadcaster,
          );
        }

        try {
          await _pc!.setRemoteDescription(desc);
          _remoteDescSet = true;
          await _flushPendingIce();

          if (sdpType == 'offer') {
            final answer = await _pc!.createAnswer();
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
            (iceMap['sdpMLineIndex'] as num?)?.toInt() ?? 0,
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

      case 'screen_share_reaction':
        final emoji = data['emoji'] as String?;
        if (emoji != null && emoji.isNotEmpty) {
          _reactionController.add(emoji);
        }
        break;

      case 'screen_share_chat':
        final msgData = data['message'] as Map<String, dynamic>?;
        if (msgData != null) {
          final msg = ChatMessage.fromJson(
            msgData,
            currentDeviceId: getCurrentDeviceId(),
          );
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
            _chatController.add(msg);
            _unreadCount++;
            notifyListeners();
            if (!kIsWeb && WebRTC.platformIsAndroid && isBroadcasting) {
              try {
                const MethodChannel('com.norns.eir/media_picker').invokeMethod(
                  'showScreenShareMessageNotification',
                  {'id': msg.id, 'sender': msg.senderName, 'text': msg.text},
                );
              } catch (e) {
                debugPrint(
                  '[ScreenShareService] showScreenShareMessageNotification error: $e',
                );
              }
            }
          }
        }
        break;

      case 'screen_share_camera_status':
        _isRemoteCameraActive = data['enabled'] as bool? ?? false;
        notifyListeners();
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
    if (!kIsWeb && WebRTC.platformIsAndroid) {
      try {
        const MethodChannel(
          'com.norns.eir/media_picker',
        ).invokeMethod('stopMediaProjectionService');
      } catch (e) {
        debugPrint('[ScreenShareService] stopMediaProjectionService error: $e');
      }
    }
    _durationTimer?.cancel();
    _handshakeWatchdogTimer?.cancel();
    _duration = Duration.zero;
    _viewerCount = 0;
    _pendingIce.clear();
    _cachedLocalIce.clear();
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

    _cameraStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _cameraStream?.dispose();
    _cameraStream = null;
    _cameraSender = null;
    _isCameraEnabled = false;
    _isRemoteCameraActive = false;

    if (_cameraRenderersInitialized) {
      localCameraRenderer.srcObject = null;
      remoteCameraRenderer.srcObject = null;
    }

    _pc?.close();
    _pc = null;
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _handshakeWatchdogTimer?.cancel();
    _duration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _duration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  /// Set remote audio volume (0.0 to 1.0)
  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    _companionVolume = _volume;
    _isMuted = _volume == 0.0;
    notifyListeners();
  }

  /// Set companion media volume (0.0 to 1.0)
  void setCompanionVolume(double val) {
    _companionVolume = val.clamp(0.0, 1.0);
    _volume = _companionVolume;
    _isMuted = _companionVolume == 0.0;
    notifyListeners();
  }

  /// Set voice chat volume (0.0 to 2.0 with gain boost)
  void setVoiceVolume(double val) {
    _voiceVolume = val.clamp(0.0, 2.0);
    notifyListeners();
  }

  /// Toggle audio ducking (lower media volume when speaking)
  void setAudioDucking(bool enabled) {
    _isAudioDuckingEnabled = enabled;
    notifyListeners();
  }

  /// Toggle aspect ratio (Contain vs Cover)
  void toggleAspectMode() {
    _isCoverMode = !_isCoverMode;
    notifyListeners();
  }

  /// Broadcast reaction emoji to peers
  Future<void> sendReaction(String emoji) async {
    _reactionController.add(emoji);
    try {
      await sendSignal({
        'type': 'screen_share_reaction',
        'emoji': emoji,
        'castCode': _activeCastCode,
      });
    } catch (_) {}
  }

  /// Toggle mute state
  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  /// Toggle system audio sharing during screen cast
  void toggleAudio() {
    _isAudioEnabled = !_isAudioEnabled;
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = _isAudioEnabled;
    }
    notifyListeners();
  }

  /// Toggle microphone talkback during screen share with WebRTC 3A echo cancellation
  Future<void> toggleMic() async {
    _isMicEnabled = !_isMicEnabled;
    if (_isMicEnabled) {
      try {
        _micStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'highpassFilter': true,
          },
          'video': false,
        });
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

  /// Send chat message in screen share
  Future<void> sendChatMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final msg = ChatMessage(
      id: const Uuid().v4(),
      senderDeviceId: getCurrentDeviceId(),
      senderName: getCurrentDisplayName(),
      senderAvatar: getCurrentAvatar(),
      text: trimmed,
      timestamp: DateTime.now(),
      isSelf: true,
    );

    _messages.add(msg);
    _chatController.add(msg);
    notifyListeners();

    try {
      await sendSignal({
        'type': 'screen_share_chat',
        'message': msg.toJson(),
        'castCode': _activeCastCode,
      });
    } catch (e) {
      debugPrint('[ScreenShareService] sendChatMessage error: $e');
    }
  }

  /// Toggle camera for video talkback (Picture-in-Picture)
  Future<void> toggleCamera() async {
    if (_isCameraEnabled) {
      _isCameraEnabled = false;
      if (_cameraSender != null && _pc != null) {
        try {
          await _pc!.removeTrack(_cameraSender!);
        } catch (_) {}
        _cameraSender = null;
      }
      _cameraStream?.getTracks().forEach((track) {
        try {
          track.stop();
        } catch (_) {}
      });
      _cameraStream?.dispose();
      _cameraStream = null;
      localCameraRenderer.srcObject = null;
      await sendSignal({
        'type': 'screen_share_camera_status',
        'enabled': false,
        'castCode': _activeCastCode,
      });
      notifyListeners();
    } else {
      await initCameraRenderers();
      try {
        final constraints = <String, dynamic>{
          'audio': false,
          'video': {
            'facingMode': _isFrontCamera ? 'user' : 'environment',
            'width': {'ideal': 640},
            'height': {'ideal': 480},
            'frameRate': {'ideal': 30},
          },
        };
        _cameraStream = await navigator.mediaDevices.getUserMedia(constraints);
        localCameraRenderer.srcObject = _cameraStream;
        _isCameraEnabled = true;

        if (_pc != null && _cameraStream != null) {
          for (final track in _cameraStream!.getVideoTracks()) {
            _cameraSender = await _pc!.addTrack(track, _cameraStream!);
          }
        }

        await sendSignal({
          'type': 'screen_share_camera_status',
          'enabled': true,
          'castCode': _activeCastCode,
        });
        notifyListeners();
      } catch (e) {
        debugPrint('[ScreenShareService] toggleCamera error: $e');
        _isCameraEnabled = false;
        notifyListeners();
      }
    }
  }

  /// Switch between front and rear cameras
  Future<void> switchCamera() async {
    if (!_isCameraEnabled || _cameraStream == null) return;
    _isFrontCamera = !_isFrontCamera;
    try {
      final videoTrack = _cameraStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        await Helper.switchCamera(videoTrack);
      }
    } catch (e) {
      debugPrint('[ScreenShareService] switchCamera error: $e');
    }
    notifyListeners();
  }

  void _setupNativeMethodCallHandler() {
    if (!kIsWeb && WebRTC.platformIsAndroid) {
      try {
        const MethodChannel('com.norns.eir/media_picker').setMethodCallHandler((
          call,
        ) async {
          if (call.method == 'onNotificationReply' ||
              call.method == 'onOverlayChatSend') {
            final text = call.arguments?['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              await sendChatMessage(text.trim());
            }
          }
        });
      } catch (e) {
        debugPrint(
          '[ScreenShareService] _setupNativeMethodCallHandler error: $e',
        );
      }
    }
  }

  @override
  void dispose() {
    _cleanup();
    _reactionController.close();
    _chatController.close();
    if (_renderersInitialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    if (_cameraRenderersInitialized) {
      localCameraRenderer.dispose();
      remoteCameraRenderer.dispose();
    }
    super.dispose();
  }
}

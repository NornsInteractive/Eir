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
  final Future<RTCPeerConnection> Function(Map<String, dynamic> config)?
      createPeerConnectionOverride;
  final Future<MediaStream?> Function(Map<String, dynamic> constraints)?
      getDisplayMediaOverride;
  final bool Function()? platformIsAndroid;
  final Future<bool> Function()? requestCapturePermissionOverride;
  final Future<Object?> Function(String method, [Object? arguments])?
      platformMethodInvoker;
  final Duration statsInterval;

  ScreenShareService({
    required this.sendSignal,
    required this.getCurrentDeviceId,
    required this.getCurrentDisplayName,
    required this.getCurrentAvatar,
    this.getIceServers,
    this.createPeerConnectionOverride,
    this.getDisplayMediaOverride,
    this.platformIsAndroid,
    this.requestCapturePermissionOverride,
    this.platformMethodInvoker,
    this.statsInterval = const Duration(seconds: 2),
  }) {
    _setupNativeMethodCallHandler();
  }

  static const String _mediaPickerChannel = 'com.norns.eir/media_picker';

  int _generation = 0;
  bool _disposed = false;

  bool get _isAndroid =>
      (platformIsAndroid ?? (() => !kIsWeb && WebRTC.platformIsAndroid))();

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
  bool _cameraRenderersUnavailable = false;
  bool get cameraRenderersInitialized => _cameraRenderersInitialized;

  MediaStream? _cameraStream;
  RTCRtpSender? _cameraSender;

  // Stream health statistics sampled from RTCPeerConnection.getStats().
  // Null means the platform did not expose that metric; it is never faked as 0.
  int? _rttMs;
  int? get rttMs => _rttMs;
  double? _bitrateMbps;
  double? get bitrateMbps => _bitrateMbps;
  double? _packetLoss;
  double? get packetLoss => _packetLoss;
  bool _statsAvailable = false;
  bool get statsAvailable => _statsAvailable;
  Timer? _statsTimer;

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
  bool _renderersUnavailable = false;
  bool get renderersInitialized => _renderersInitialized;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _micStream;

  bool get hasRemoteStream => _remoteStream != null;

  final List<RTCIceCandidate> _pendingIce = [];
  final List<RTCIceCandidate> _cachedLocalIce = [];
  bool _remoteDescSet = false;

  /// Initialize video renderers for local preview and remote playback
  Future<void> initRenderers() async {
    if (_renderersInitialized || _renderersUnavailable) return;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
      notifyListeners();
    } catch (e) {
      _renderersUnavailable = true;
      debugPrint('[ScreenShareService] initRenderers error: $e');
    }
  }

  /// Initialize camera video renderers
  Future<void> initCameraRenderers() async {
    if (_cameraRenderersInitialized || _cameraRenderersUnavailable) return;
    try {
      await localCameraRenderer.initialize();
      await remoteCameraRenderer.initialize();
      _cameraRenderersInitialized = true;
      notifyListeners();
    } catch (e) {
      _cameraRenderersUnavailable = true;
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
    if (_disposed) return false;
    final generation = ++_generation;
    await _releaseResources();
    if (!_isCurrent(generation)) return false;

    _state = ScreenShareState.connecting;
    _role = ScreenShareRole.broadcaster;
    _activeCastCode = castCode;
    _targetFps = targetFps;
    _isAudioEnabled = shareAudio;
    _sourceTitle =
        customTitle ?? source?.name ?? (source == null ? 'Entire Screen' : 'App Window');
    _sourceType = source?.type == SourceType.Window ? 'window' : 'screen';
    _lastError = null;
    notifyListeners();

    await initRenderers();
    if (!_isCurrent(generation)) return false;

    try {
      // Platform-specific capture permission handling & Android MediaProjection Foreground Service
      if (_isAndroid) {
        // In Android 14+ (API 34+), the system screen capture prompt must be granted
        // BEFORE starting the MediaProjection foreground service to avoid SecurityException.
        bool granted = false;
        try {
          granted = await (requestCapturePermissionOverride ??
              Helper.requestCapturePermission)();
        } catch (e) {
          debugPrint(
            '[ScreenShareService] Android capture permission error: $e',
          );
        }
        if (!_isCurrent(generation)) return false;
        if (!granted) {
          debugPrint('[ScreenShareService] Screen capture permission denied by user.');
          _state = ScreenShareState.idle;
          _role = ScreenShareRole.none;
          _lastError = 'Screen capture permission denied or cancelled by user';
          await _releaseResources();
          if (_isCurrent(generation)) notifyListeners();
          return false;
        }

        try {
          await _invokePlatform('startMediaProjectionService', {
            'enableFloatingChat': enableFloatingChat,
          });
        } catch (e) {
          debugPrint(
            '[ScreenShareService] startMediaProjectionService error: $e',
          );
          if (_isCurrent(generation)) {
            _state = ScreenShareState.error;
            _lastError = e.toString();
            await _releaseResources();
            notifyListeners();
          }
          return false;
        }
        if (!_isCurrent(generation)) {
          // Stop arrived while the service was starting; release it now.
          await _stopAndroidProjectionService();
          return false;
        }
      }

      // Platform-tailored constraints avoiding Android MediaProjection black screen
      final mediaConstraints = _isAndroid
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

      MediaStream? acquired;
      try {
        acquired = await _getDisplayMedia(mediaConstraints);
      } catch (e) {
        if (!_isCurrent(generation)) return false;
        // Fallback for environments where getDisplayMedia with constraints fails
        acquired = await _getDisplayMedia({
          'video': true,
          'audio': shareAudio,
        });
      }

      if (!_isCurrent(generation)) {
        // A stop/restart happened while capture was pending. The late stream
        // belongs to the cancelled generation and must be released here.
        await _disposeStream(acquired);
        return false;
      }

      _localStream = acquired;
      if (_localStream != null) {
        if (_renderersInitialized) localRenderer.srcObject = _localStream;
        // Listen for user stopping sharing via system UI
        for (final track in _localStream!.getVideoTracks()) {
          track.onEnded = () {
            if (_isCurrent(generation)) {
              stop(reason: 'user_ended_from_system');
            }
          };
        }
      }

      await _setupPeerConnection(
        isBroadcaster: true,
        generation: generation,
      );
      if (!_isCurrent(generation)) return false;

      _state = ScreenShareState.active;
      _startedAt = DateTime.now();
      _startDurationTimer();
      _startStatsSampling(generation);
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
      if (!_isCurrent(generation)) return false;
      debugPrint('[ScreenShareService] startBroadcasting error: $e');
      _state = ScreenShareState.error;
      _lastError = e.toString();
      await _releaseResources();
      if (_isCurrent(generation)) notifyListeners();
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
    if (_disposed) return false;
    final generation = ++_generation;
    await _releaseResources();
    if (!_isCurrent(generation)) return false;

    _state = ScreenShareState.connecting;
    _role = ScreenShareRole.viewer;
    _activeCastCode = castCode;
    _lastError = null;
    notifyListeners();

    await initRenderers();
    if (!_isCurrent(generation)) return false;

    try {
      await _setupPeerConnection(
        isBroadcaster: false,
        generation: generation,
      );
      if (!_isCurrent(generation)) return false;

      _state = ScreenShareState.active;
      _startedAt = DateTime.now();
      _startDurationTimer();
      _startStatsSampling(generation);
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
        if (!_isCurrent(generation)) return;
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
      if (!_isCurrent(generation)) return false;
      debugPrint('[ScreenShareService] startViewing error: $e');
      _state = ScreenShareState.error;
      _lastError = e.toString();
      await _releaseResources();
      if (_isCurrent(generation)) notifyListeners();
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
  Future<void> _setupPeerConnection({
    required bool isBroadcaster,
    required int generation,
  }) async {
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

    final pc = await (createPeerConnectionOverride ?? createPeerConnection)(
      rtcConfig,
    );
    if (!_isCurrent(generation)) {
      await _closePeerConnection(pc);
      return;
    }
    _pc = pc;
    bool stillCurrent() => _isCurrent(generation) && identical(_pc, pc);

    pc.onIceCandidate = (candidate) {
      if (!stillCurrent()) return;
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

    pc.onConnectionState = (state) {
      if (!stillCurrent()) return;
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

    pc.onIceConnectionState = (state) {
      if (!stillCurrent()) return;
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

    pc.onTrack = (event) async {
      if (!stillCurrent()) return;
      debugPrint(
        '[ScreenShareService] onTrack kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}',
      );
      if (event.track.kind == 'video') {
        // If main remote stream has no video track yet, bind this track as primary screen canvas
        if (_remoteStream == null || _remoteStream!.getVideoTracks().isEmpty) {
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
          } else {
            final stream = await createLocalMediaStream('remote_screen_stream');
            if (!stillCurrent()) {
              await _disposeStream(stream);
              return;
            }
            _remoteStream ??= stream;
            await _remoteStream!.addTrack(event.track);
          }
          if (_renderersInitialized) remoteRenderer.srcObject = _remoteStream;
        } else {
          // Additional video track -> remote camera PiP
          _isRemoteCameraActive = true;
          if (event.streams.isNotEmpty) {
            if (_cameraRenderersInitialized) {
              remoteCameraRenderer.srcObject = event.streams.first;
            }
          } else {
            final camStream = await createLocalMediaStream('remote_camera_stream');
            if (!stillCurrent()) {
              await _disposeStream(camStream);
              return;
            }
            await camStream.addTrack(event.track);
            if (_cameraRenderersInitialized) {
              remoteCameraRenderer.srcObject = camStream;
            }
          }
        }
        if (stillCurrent()) notifyListeners();
      } else if (event.track.kind == 'audio') {
        if (_remoteStream == null) {
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
          } else {
            final stream = await createLocalMediaStream('remote_screen_stream');
            if (!stillCurrent()) {
              await _disposeStream(stream);
              return;
            }
            _remoteStream = stream;
            await _remoteStream!.addTrack(event.track);
          }
        } else {
          await _remoteStream!.addTrack(event.track);
        }
        if (!stillCurrent()) return;
        if (_remoteStream!.getVideoTracks().isNotEmpty &&
            _renderersInitialized) {
          remoteRenderer.srcObject = _remoteStream;
        }
        notifyListeners();
      }
    };

    if (!isBroadcaster) {
      try {
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      } catch (e) {
        debugPrint('[ScreenShareService] addTransceiver error: $e');
      }
    }

    if (isBroadcaster && _localStream != null) {
      for (final track in _localStream!.getTracks()) {
        if (!stillCurrent()) return;
        await pc.addTrack(track, _localStream!);
      }
      if (!stillCurrent()) return;
      await _sendOfferToViewer(restartIce: false, generation: generation);
    }
  }

  /// Safely generate, munge, set local description, send offer, and forward all cached ICE candidates
  Future<void> _sendOfferToViewer({
    bool restartIce = false,
    int? generation,
  }) async {
    final pc = _pc;
    if (pc == null) return;
    final expectedGeneration = generation ?? _generation;
    bool stillCurrent() =>
        identical(_pc, pc) &&
        _isCurrent(expectedGeneration) &&
        _role == ScreenShareRole.broadcaster;
    if (!stillCurrent()) return;

    try {
      final state = await pc.getSignalingState();
      if (!stillCurrent()) return;
      RTCSessionDescription? offer;

      if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer && !restartIce) {
        // Reuse current valid local offer that hasn't been answered yet
        offer = await pc.getLocalDescription();
      } else {
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          try {
            await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
          } catch (_) {}
        }
        final rawOffer = await pc.createOffer({
          'offerToReceiveVideo': 0,
          'offerToReceiveAudio': 1,
          if (restartIce) 'iceRestart': true,
        });
        if (!stillCurrent()) return;
        final mungedSdp = _preferCodec(rawOffer.sdp ?? '', 'VP8');
        offer = RTCSessionDescription(mungedSdp, rawOffer.type);
        await pc.setLocalDescription(offer);
      }

      if (offer != null && stillCurrent()) {
        await sendSignal({
          'type': 'screen_share_sdp',
          'sdp': {'type': offer.type, 'sdp': offer.sdp},
          'sourceTitle': _sourceTitle,
          'sourceType': _sourceType,
          'castCode': _activeCastCode,
        });

        // Forward all gathered ICE candidates to the viewer
        for (final cand in List<RTCIceCandidate>.from(_cachedLocalIce)) {
          if (!stillCurrent()) return;
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
    final signalCastCode = data['castCode'] as String?;
    final matchesCast = signalCastCode == null ||
        _activeCastCode == null ||
        signalCastCode == _activeCastCode;
    final roleActive = _role != ScreenShareRole.none;

    switch (type) {
      case 'screen_share_started':
        _sourceTitle = data['sourceTitle'] as String? ?? _sourceTitle;
        _sourceType = data['sourceType'] as String? ?? _sourceType;
        _targetFps = (data['targetFps'] as num?)?.toInt() ?? _targetFps;
        notifyListeners();
        break;

      case 'screen_share_viewer_join':
        if (!matchesCast || !roleActive) return;
        _viewerCount = math.max(1, _viewerCount);
        notifyListeners();

        // If we are broadcasting, safely send offer & candidates to newly joined viewer
        if (_role == ScreenShareRole.broadcaster && _pc != null) {
          await _sendOfferToViewer(restartIce: false);
        }
        break;

      case 'screen_share_sdp':
        if (!matchesCast || !roleActive) return;
        final sdpMap = data['sdp'] as Map<String, dynamic>?;
        if (sdpMap == null) return;
        final sdpType = sdpMap['type'] as String?;
        final sdpDesc = sdpMap['sdp'] as String?;
        if (sdpType == null || sdpDesc == null) return;

        final desc = RTCSessionDescription(sdpDesc, sdpType);
        final generation = _generation;
        if (_pc == null) {
          await _setupPeerConnection(
            isBroadcaster: _role == ScreenShareRole.broadcaster,
            generation: generation,
          );
        }
        final pc = _pc;
        if (pc == null || !_isCurrent(generation) || !identical(_pc, pc)) {
          return;
        }

        try {
          await pc.setRemoteDescription(desc);
          if (!_isCurrent(generation) || !identical(_pc, pc)) return;
          _remoteDescSet = true;
          await _flushPendingIce();
          if (!_isCurrent(generation) || !identical(_pc, pc)) return;

          if (sdpType == 'offer') {
            final answer = await pc.createAnswer();
            if (!_isCurrent(generation) || !identical(_pc, pc)) return;
            await pc.setLocalDescription(answer);
            if (!_isCurrent(generation) || !identical(_pc, pc)) return;
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
        if (!matchesCast || !roleActive) return;
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
          if (_isAndroid && isBroadcasting) {
            unawaited(_invokePlatformBestEffort(
              'showScreenShareReaction',
              {'emoji': emoji},
            ));
          }
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
            if (_isAndroid && isBroadcasting) {
              unawaited(_invokePlatformBestEffort(
                'showScreenShareMessageNotification',
                {'id': msg.id, 'sender': msg.senderName, 'text': msg.text},
              ));
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
    if (_disposed) {
      _generation++;
      return;
    }
    if (_state == ScreenShareState.idle && _role == ScreenShareRole.none) {
      // Still fences any startBroadcasting/startViewing that is waiting on
      // permission or media before it has switched the visible state.
      _generation++;
      return;
    }

    final generation = ++_generation;
    final stopCastCode = _activeCastCode;
    try {
      await sendSignal({
        'type': 'screen_share_stop',
        'reason': reason ?? 'user_action',
        'castCode': stopCastCode,
      });
    } catch (_) {}
    if (generation != _generation) return;

    await _releaseResources();
    if (generation != _generation) return;

    _state = ScreenShareState.idle;
    _role = ScreenShareRole.none;
    _activeCastCode = null;
    if (!_disposed) notifyListeners();
  }

  Future<MediaStream?> _getDisplayMedia(Map<String, dynamic> constraints) {
    final override = getDisplayMediaOverride;
    if (override != null) return override(constraints);
    return navigator.mediaDevices.getDisplayMedia(constraints);
  }

  Future<Object?> _invokePlatform(String method, [Object? arguments]) {
    final override = platformMethodInvoker;
    if (override != null) return override(method, arguments);
    return const MethodChannel(_mediaPickerChannel)
        .invokeMethod<Object?>(method, arguments);
  }

  Future<void> _invokePlatformBestEffort(
    String method, [
    Object? arguments,
  ]) async {
    try {
      await _invokePlatform(method, arguments);
    } catch (e) {
      debugPrint('[ScreenShareService] $method error: $e');
    }
  }

  Future<void> _stopAndroidProjectionService() async {
    if (!_isAndroid) return;
    try {
      await _invokePlatform('stopMediaProjectionService');
    } catch (e) {
      // The native foreground service may already be gone; report instead of
      // silently pretending the cleanup succeeded.
      debugPrint('[ScreenShareService] stopMediaProjectionService error: $e');
    }
  }

  Future<void> _closePeerConnection(RTCPeerConnection? pc) async {
    if (pc == null) return;
    try {
      await pc.close();
    } catch (e) {
      debugPrint('[ScreenShareService] peer connection close error: $e');
    }
  }

  Future<void> _disposeStream(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (e) {
        debugPrint('[ScreenShareService] track stop error: $e');
      }
    }
    try {
      await stream.dispose();
    } catch (e) {
      debugPrint('[ScreenShareService] stream dispose error: $e');
    }
  }

  Future<void> _releaseResources() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _durationTimer?.cancel();
    _handshakeWatchdogTimer?.cancel();
    _duration = Duration.zero;
    _viewerCount = 0;
    _statsAvailable = false;
    _rttMs = null;
    _bitrateMbps = null;
    _packetLoss = null;
    _lastStatsAt = null;
    _lastStatsBytes = null;
    _pendingIce.clear();
    _cachedLocalIce.clear();
    _remoteDescSet = false;

    if (!_disposed) {
      if (_renderersInitialized) {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      }
      if (_cameraRenderersInitialized) {
        localCameraRenderer.srcObject = null;
        remoteCameraRenderer.srcObject = null;
      }
    }

    final localStream = _localStream;
    _localStream = null;
    final micStream = _micStream;
    _micStream = null;
    final remoteStream = _remoteStream;
    _remoteStream = null;
    final cameraStream = _cameraStream;
    _cameraStream = null;
    final pc = _pc;
    _pc = null;
    _cameraSender = null;
    _isCameraEnabled = false;
    _isRemoteCameraActive = false;

    await Future.wait(<Future<void>>[
      _disposeStream(localStream),
      _disposeStream(micStream),
      _disposeStream(remoteStream),
      _disposeStream(cameraStream),
      _closePeerConnection(pc),
      _stopAndroidProjectionService(),
    ]);
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation;

  void _startDurationTimer() {
    if (_disposed) return;
    _durationTimer?.cancel();
    _handshakeWatchdogTimer?.cancel();
    _duration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _duration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  DateTime? _lastStatsAt;
  num? _lastStatsBytes;

  void _startStatsSampling(int generation) {
    _statsTimer?.cancel();
    if (statsInterval <= Duration.zero) return;
    _statsTimer = Timer.periodic(statsInterval, (_) {
      if (!_isCurrent(generation)) {
        _statsTimer?.cancel();
        _statsTimer = null;
        return;
      }
      unawaited(refreshStats());
    });
  }

  void _markStatsUnavailable() {
    _statsAvailable = false;
    _rttMs = null;
    _bitrateMbps = null;
    _packetLoss = null;
    _lastStatsAt = null;
    _lastStatsBytes = null;
  }

  /// Samples the active RTCPeerConnection. Metrics stay null when the platform
  /// does not expose them instead of being reported as a fake zero.
  Future<void> refreshStats() async {
    final pc = _pc;
    if (pc == null) {
      _markStatsUnavailable();
      return;
    }
    try {
      final reports = await pc.getStats();
      if (!identical(_pc, pc) || _disposed) return;
      _applyStats(reports);
      notifyListeners();
    } catch (e) {
      debugPrint('[ScreenShareService] getStats error: $e');
      if (identical(_pc, pc) && !_disposed) {
        _markStatsUnavailable();
        notifyListeners();
      }
    }
  }

  static num? _statNum(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  void _applyStats(List<StatsReport> reports) {
    var sawStats = false;
    num? bytes;
    num? inboundLost = 0;
    num? inboundReceived = 0;
    num? sent;
    num? remoteLost = 0;
    num? fractionLost;
    num? rttSeconds;

    for (final report in reports) {
      final values = report.values;
      final type = (values['type'] ?? report.type) as Object?;
      if (type is! String) continue;
      switch (type) {
        case 'inbound-rtp':
          sawStats = true;
          final received = _statNum(values['bytesReceived']);
          if (received != null) {
            bytes = (bytes ?? 0) + received;
          }
          final packetsLost = _statNum(values['packetsLost']);
          final packetsReceived = _statNum(values['packetsReceived']);
          if (packetsLost != null) inboundLost = (inboundLost ?? 0) + packetsLost;
          if (packetsReceived != null) {
            inboundReceived = (inboundReceived ?? 0) + packetsReceived;
          }
          break;
        case 'outbound-rtp':
          sawStats = true;
          final bytesSent = _statNum(values['bytesSent']);
          if (bytesSent != null) bytes = (bytes ?? 0) + bytesSent;
          final packetsSent = _statNum(values['packetsSent']);
          if (packetsSent != null) sent = (sent ?? 0) + packetsSent;
          break;
        case 'remote-inbound-rtp':
          sawStats = true;
          final rtt = _statNum(values['roundTripTime']);
          if (rtt != null) rttSeconds = rtt;
          final packetsLost = _statNum(values['packetsLost']);
          if (packetsLost != null) remoteLost = (remoteLost ?? 0) + packetsLost;
          final fraction = _statNum(values['fractionLost']);
          if (fraction != null) fractionLost = fraction;
          break;
        case 'candidate-pair':
          final state = values['state'];
          if (state == 'succeeded' || values['nominated'] == true) {
            final rtt = _statNum(values['currentRoundTripTime']);
            if (rtt != null) rttSeconds = rtt;
          }
          break;
        case 'transport':
          final rtt = _statNum(values['roundTripTime']);
          if (rtt != null) rttSeconds = rtt;
          break;
      }
    }

    if (!sawStats) {
      _markStatsUnavailable();
      return;
    }

    _statsAvailable = true;
    if (rttSeconds != null) {
      final ms = rttSeconds > 10 ? rttSeconds : rttSeconds * 1000;
      _rttMs = ms.round();
    } else {
      _rttMs = null;
    }

    final now = DateTime.now();
    if (bytes != null &&
        _lastStatsAt != null &&
        _lastStatsBytes != null) {
      final elapsedSeconds =
          now.difference(_lastStatsAt!).inMilliseconds / 1000.0;
      final delta = bytes - _lastStatsBytes!;
      if (elapsedSeconds > 0 && delta >= 0) {
        _bitrateMbps = (delta * 8) / elapsedSeconds / 1000000.0;
      } else {
        _bitrateMbps = null;
      }
    } else {
      _bitrateMbps = null;
    }
    _lastStatsAt = now;
    _lastStatsBytes = bytes;

    final inboundTotal = (inboundLost ?? 0) + (inboundReceived ?? 0);
    if (inboundTotal > 0) {
      _packetLoss =
          ((inboundLost ?? 0) / inboundTotal).clamp(0.0, 1.0).toDouble();
    } else if (remoteLost != null && sent != null && sent > 0) {
      _packetLoss = (remoteLost / sent).clamp(0.0, 1.0).toDouble();
    } else if (fractionLost != null) {
      _packetLoss = fractionLost.clamp(0.0, 1.0).toDouble();
    } else {
      _packetLoss = null;
    }
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
    final generation = _generation;
    if (_isMicEnabled) {
      MediaStream? acquired;
      try {
        acquired = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'highpassFilter': true,
          },
          'video': false,
        });
        if (!_isCurrent(generation)) {
          await _disposeStream(acquired);
          return;
        }
        _micStream = acquired;
        final pc = _pc;
        if (pc != null && _micStream != null) {
          for (final track in _micStream!.getAudioTracks()) {
            if (!_isCurrent(generation) || !identical(_pc, pc)) {
              await _disposeStream(acquired);
              if (identical(_micStream, acquired)) _micStream = null;
              return;
            }
            await pc.addTrack(track, _micStream!);
          }
        }
      } catch (e) {
        debugPrint('[ScreenShareService] Mic enable error: $e');
        if (identical(_micStream, acquired) || acquired == null) {
          _isMicEnabled = false;
        }
        await _disposeStream(acquired);
      }
    } else {
      final micStream = _micStream;
      _micStream = null;
      await _disposeStream(micStream);
    }
    if (_isCurrent(generation)) notifyListeners();
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

    if (_isAndroid && isBroadcasting) {
      unawaited(_invokePlatformBestEffort(
        'addChatMessageToOverlay',
        {
          'id': msg.id,
          'sender': msg.senderName,
          'text': msg.text,
          'isMe': true,
        },
      ));
    }

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
    final generation = _generation;
    if (_isCameraEnabled) {
      _isCameraEnabled = false;
      if (_cameraSender != null && _pc != null) {
        try {
          await _pc!.removeTrack(_cameraSender!);
        } catch (_) {}
        _cameraSender = null;
      }
      final cameraStream = _cameraStream;
      _cameraStream = null;
      if (_cameraRenderersInitialized) {
        localCameraRenderer.srcObject = null;
      }
      await _disposeStream(cameraStream);
      if (!_isCurrent(generation)) return;
      await sendSignal({
        'type': 'screen_share_camera_status',
        'enabled': false,
        'castCode': _activeCastCode,
      });
      if (_isCurrent(generation)) notifyListeners();
    } else {
      await initCameraRenderers();
      if (!_isCurrent(generation)) return;
      MediaStream? acquired;
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
        acquired = await navigator.mediaDevices.getUserMedia(constraints);
        if (!_isCurrent(generation)) {
          await _disposeStream(acquired);
          return;
        }
        _cameraStream = acquired;
        if (_cameraRenderersInitialized) {
          localCameraRenderer.srcObject = acquired;
        }
        _isCameraEnabled = true;

        final pc = _pc;
        if (pc != null && _cameraStream != null) {
          for (final track in _cameraStream!.getVideoTracks()) {
            if (!_isCurrent(generation) || !identical(_pc, pc)) {
              await _disposeStream(acquired);
              if (identical(_cameraStream, acquired)) _cameraStream = null;
              return;
            }
            _cameraSender = await pc.addTrack(track, _cameraStream!);
          }
        }

        if (!_isCurrent(generation)) return;
        await sendSignal({
          'type': 'screen_share_camera_status',
          'enabled': true,
          'castCode': _activeCastCode,
        });
        if (_isCurrent(generation)) notifyListeners();
      } catch (e) {
        debugPrint('[ScreenShareService] toggleCamera error: $e');
        if (identical(_cameraStream, acquired) || acquired == null) {
          _isCameraEnabled = false;
        }
        if (identical(_cameraStream, acquired)) _cameraStream = null;
        await _disposeStream(acquired);
        if (_isCurrent(generation)) notifyListeners();
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
    if (_isAndroid) {
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
    if (_disposed) return;
    _generation++;
    final cleanup = _releaseResources();
    _disposed = true;
    _reactionController.close();
    _chatController.close();
    unawaited(cleanup.whenComplete(() {
      if (_renderersInitialized) {
        unawaited(localRenderer.dispose());
        unawaited(remoteRenderer.dispose());
      }
      if (_cameraRenderersInitialized) {
        unawaited(localCameraRenderer.dispose());
        unawaited(remoteCameraRenderer.dispose());
      }
    }));
    super.dispose();
  }
}

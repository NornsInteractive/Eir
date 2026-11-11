import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:uuid/uuid.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_settings.dart';
import '../media/local_media_service.dart';
import '../media/media_format.dart' show resolveMediaMime;
import '../media/media_limits.dart'
    show kMediaChunkSize, kMediaMaxMessageBytes, MediaException;
import '../media/media_manifest.dart' show isHex64;
import '../platform/dtls_fingerprint.dart';
import '../platform/signaling_client.dart';
import '../platform/video_surface_ready.dart';
import 'url_probe.dart';
import 'clock.dart';
import 'commit_log.dart';
import 'identity.dart';
import 'invite.dart';
import 'protocol.dart';

export '../platform/signaling_client.dart' show SignalingClient;
export 'identity.dart'
    show
        DeviceIdentity,
        DeviceIdentityStore,
        SecureKeyValueStore,
        InMemorySecureKeyValueStore,
        FlutterSecureStorageStore,
        IdentityStoreCorrupted;
export 'package:cross_file/cross_file.dart' show XFile;
export '../media/local_media_common.dart'
    show MediaCacheTelemetrySnapshot;

enum RoomRole { owner, admin, member }

enum RoomConnectionState { disconnected, connecting, connected, reconnecting }

enum PlaybackMode { playing, paused }

class DeviceIdentityInfo {
  DeviceIdentityInfo({required this.deviceId, required this.publicKeyBase64});
  final String deviceId;
  final String publicKeyBase64;
}

class RoomMember {
  RoomMember({
    required this.deviceId,
    required this.displayName,
    required this.role,
    this.online = true,
    this.avatar = '',
    int? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String deviceId;
  final String displayName;
  final RoomRole role;
  final bool online;
  final String avatar;
  final int joinedAt;

  RoomMember copyWith({
    String? displayName,
    RoomRole? role,
    bool? online,
    String? avatar,
    int? joinedAt,
  }) =>
      RoomMember(
        deviceId: deviceId,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        online: online ?? this.online,
        avatar: avatar ?? this.avatar,
        joinedAt: joinedAt ?? this.joinedAt,
      );
}

class PlaylistItem {
  PlaylistItem({
    required this.itemId,
    required this.title,
    required this.sourceType,
    this.url,
    this.localMediaId,
    this.localPath,
    this.duration,
    this.sizeBytes,
  });
  final String itemId;
  final String title;
  final String sourceType; // url | local
  final String? url;
  final String? localMediaId;
  final String? localPath;
  final Duration? duration;
  final int? sizeBytes;

  Map<String, Object?> toMap() => <String, Object?>{
        'itemId': itemId,
        'title': title,
        'sourceType': sourceType,
        if (url != null) 'url': url,
        if (localMediaId != null) 'localMediaId': localMediaId,
        if (localPath != null) 'localPath': localPath,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
      };

  static PlaylistItem fromMap(Map<String, Object?> m) {
    final itemId = m['itemId'];
    final title = m['title'];
    final sourceType = m['sourceType'];
    if (itemId is! String || title is! String || sourceType is! String) {
      throw const FormatException('invalid playlist item');
    }
    final durationMs = m['durationMs'];
    final sizeBytes = m['sizeBytes'];
    return PlaylistItem(
      itemId: itemId,
      title: title,
      sourceType: sourceType,
      url: m['url'] as String?,
      localMediaId: m['localMediaId'] as String?,
      localPath: m['localPath'] as String?,
      duration:
          durationMs is int ? Duration(milliseconds: durationMs) : null,
      sizeBytes: sizeBytes is int ? sizeBytes : null,
    );
  }
}

class PlaybackState {
  PlaybackState({
    this.itemId,
    this.mode = PlaybackMode.paused,
    this.position = Duration.zero,
    this.rate = 1.0,
    DateTime? effectiveAt,
    this.seq = 0,
    this.anchorSharedMs = 0,
    this.rateMilli = 1000,
  }) : effectiveAt = effectiveAt ?? DateTime.now();

  final String? itemId;
  final PlaybackMode mode;

  /// Position at [anchorSharedMs] (the commit that last set PlaybackState).
  final Duration position;
  final double rate;

  /// Wall-clock time this state was created (display only; not used for sync).
  final DateTime effectiveAt;
  final int seq;

  /// Leader-monotonic timestamp (shared timeline) of [position].
  final int anchorSharedMs;
  final int rateMilli;

  /// Expected position at shared-time [sharedNowMs].
  Duration expectedPositionAt(int sharedNowMs) {
    if (mode != PlaybackMode.playing || sharedNowMs <= anchorSharedMs) {
      return position;
    }
    final elapsed = ((sharedNowMs - anchorSharedMs) * rateMilli) ~/ 1000;
    return position + Duration(milliseconds: elapsed);
  }
}

class MemberTelemetry {
  MemberTelemetry({
    required this.deviceId,
    required this.itemId,
    required this.itemSeq,
    required this.positionMs,
    required this.buffering,
    required this.sharedMs,
  });

  final String deviceId;
  final String? itemId;
  final int itemSeq;
  final int positionMs;
  final bool buffering;
  final int sharedMs;
}

const List<String> kStableErrorCodes = <String>[
  'signaling_unavailable',
  'invalid_invite',
  'invite_expired',
  'invite_consumed',
  'room_full',
  'room_not_found',
  'unsupported_media',
  'media_probe_failed',
  'media_unavailable',
  'permission_denied',
  'commit_rejected',
  'handshake_failed',
  'protocol_violation',
  'chunk_hash_mismatch',
  'source_offline',
];

enum PlaybackLoopMode {
  loopAll,
  loopOne,
  sequential,
}

class DanmakuMessage {
  DanmakuMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.colorHex,
  });

  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final String? colorHex;
}

class RoomSession extends ChangeNotifier {
  RoomSession({
    DeviceIdentityStore? identityStore,
    SignalingClient? signaling,
    Player? player,
    String? Function(String url)? urlProbe,
  })  : _identityStore = identityStore ?? DeviceIdentityStore(),
        _signaling = signaling ?? SignalingClient(),
        _injectedPlayer = player,
        _urlProbeOverride = urlProbe;

  final DeviceIdentityStore _identityStore;
  final SignalingClient _signaling;
  final Player? _injectedPlayer;
  final String? Function(String url)? _urlProbeOverride;
  _LifecycleObserver? _lifecycleObserver;

  static const List<String> iceServers = <String>[
    'stun:stun.miwifi.com:3478',
    'stun:stun.chat.bilibili.com:3478',
    'stun:stun.hitv.com:3478',
    'stun:stun.cloudflare.com:3478',
    'stun:stun1.l.google.com:19302',
    'stun:stun.l.google.com:19302',
  ];
  static const Duration inviteLifetime = Duration(hours: 72);
  static const Duration handshakeTimeout = Duration(seconds: 10);
  static const Duration requestTimeout = Duration(seconds: 8);
  static const Duration timeSyncInterval = Duration(seconds: 10);
  static const Duration statusInterval = Duration(seconds: 2);
  static const Duration driftCheckInterval = Duration(seconds: 2);

  /// V1-PRD §2: a room playlist is capped at 200 entries.
  static const int kMaxPlaylistItems = 200;

  /// Manifests larger than this travel as a bounded `media_manifest_chunk`
  /// stream keyed by the compact source-signed root (`manifestSource` +
  /// `manifestSignature` carried in the commit); smaller manifests ride
  /// inline in the commit envelope. 8 KiB keeps the 65 MiB reference fixture's
  /// (~17 KiB) manifest on the chunked path while small clips stay inline.
  static const int kMaxInlineManifestBytes = 8 * 1024;

  DeviceKeyPair? _keyPair;

  DeviceIdentityInfo get identity => DeviceIdentityInfo(
        deviceId: _keyPair?.identity.deviceId ?? '',
        publicKeyBase64: _keyPair?.identity.publicKeyBase64 ?? '',
      );

  RoomConnectionState _connectionState = RoomConnectionState.disconnected;
  RoomConnectionState get connectionState => _connectionState;

  String? _roomId;
  String? get roomId => _roomId;

  String? _roomCode;
  String? get roomCode => _roomCode;

  String? _inviteText;
  String? get inviteText => _inviteText;

  /// Role is always derived from the confirmed room ACL (owner is a
  /// property of the room, not of local state), so there is a single
  /// source of truth.
  RoomRole get role {
    final self = _selfId;
    if (self == null) return RoomRole.member;
    return _roleFor(self);
  }

  final List<RoomMember> _members = <RoomMember>[];
  List<RoomMember> get members => List<RoomMember>.unmodifiable(_members);

  final List<PlaylistItem> _playlist = <PlaylistItem>[];
  List<PlaylistItem> get playlist => List<PlaylistItem>.unmodifiable(_playlist);

  int _roomGeneration = 0;
  String? _currentItemId;
  String? get currentItemId => _currentItemId;

  PlaybackState _playback = PlaybackState();
  PlaybackState get playback => _playback;

  String? _lastErrorCode;
  String? _offlineMediaId;
  String? get lastErrorCode => _lastErrorCode;

  final Map<String, MemberTelemetry> _telemetry = <String, MemberTelemetry>{};
  Map<String, MemberTelemetry> get memberTelemetry =>
      Map<String, MemberTelemetry>.unmodifiable(_telemetry);

  bool _peerVerified = false;
  bool get peerVerified => _peerVerified;

  /// Access to the lazily-created P2P media service for integration tests.
  @visibleForTesting
  LocalMediaService? get debugMediaService => _media;

  Player? _player;
  Player get player {
    final p = _player;
    if (p == null) {
      throw StateError(
        'RoomSession.init() must complete before RoomSession.player is used',
      );
    }
    return p;
  }

  // --- internal state ---
  final _uuid = const Uuid();
  final LeaderClock _clock = LeaderClock();
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  String? _peerDeviceId;
  String? _peerPublicKey;
  /// Highest `baseSeq` we have ever seen in a control request from the current
  /// peer. Used to detect genuinely *regressed* requests (a request whose view
  /// is older than one the peer has already demonstrated it holds) and reject
  /// them as `stale_state`. Concurrent requests sent from the same fresh view
  /// carry equal `baseSeq`, so they are NOT flagged — only a true regression
  /// (or a replay of an already-superseded request) trips this. Contrast with
  /// the old blanket `baseSeq < _chain.lastSeq` check, which wrongly dropped
  /// the second of two concurrent same-view requests merely because the chain
  /// advanced while they were in flight.
  int _peerBaseSeqHigh = 0;
  String? _localChallenge;
  String? _signalingUrl;
  String? _configuredSignalingUrl;
  String? _sessionId;
  Map<String, Object?>? _genesis;
  String? _genesisHash;
  String? _ownerPublicKey;
  int _inviteEpoch = 1;

  LocalMediaService? _media;
  final Set<String> _knownLocalMediaIds = <String>{};
  final Map<String, String> _knownLocalMediaSources = <String, String>{};
  final Map<String, String> _localMediaPaths = <String, String>{};

  /// Our own manifest signatures, used only when embedding manifests in
  /// snapshots so peers can verify them against this device.
  final Map<String, String> _manifestSignatures = <String, String>{};
  late CommitChain _chain = CommitChain(genesisHash: _genesisHash ?? '');
  late RoomAcl _acl = RoomAcl(ownerDeviceId: _keyPair?.identity.deviceId ?? '');

  Completer<void>? _roomCreated;
  Completer<void>? _joinAccepted;
  Completer<Map<String, dynamic>>? _roomCodeQuery;
  /// Single-flight publisher pipeline: every commit creation is serialized
  /// through this future chain so overlapping callers never observe the
  /// same (seq, prevHash) pair and a revocation is visible to any request
  /// that runs after it in the same chain.
  Future<void> _publishQueue = Future<void>.value();

  /// Serializes all commit-side-effect application (local publish path and
  /// network-received commits) so the room state machine never applies two
  /// commits concurrently.
  Future<void> _commitApplyQueue = Future<void>.value();

  final Map<String, Completer<void>> _pendingRequests =
      <String, Completer<void>>{};
  final Map<String, int> _requestToCommitSeq = <String, int>{};

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  Timer? _handshakeTimer;
  Timer? _syncTimer;
  Timer? _statusTimer;
  Timer? _driftTimer;
  Timer? _parkedSweepTimer;
  bool _closing = false;
  String? _loadedItemId;
  /// Item id for which the player is currently the authoritative source of
  /// errors. Used to drop async player errors that arrive for a previous,
  /// already-unloaded item (stale-media pollution).
  String? _errorItemId;
  DateTime _lastResyncRequest = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<bool>? _mediaCompletedSub;
  StreamSubscription<String>? _mediaErrorSub;
  bool _reconnecting = false;
  bool _retryInFlight = false;
  /// True once the bounded automatic reconnect gave up. While set, socket
  /// callbacks must not restart the loop: only an explicit [retry] (or a new
  /// room) may try again.
  bool _reconnectExhausted = false;
  bool _microRateAdjusted = false;
  int _lastSeekMonoMs = 0;
  int? _peerLastSeenMonoMs;

  String? get _selfId => _keyPair?.identity.deviceId;

  int get _sharedNowMs => _clock.sharedNowMs();

  // ---------------------------------------------------------------- init

  static bool _mediaKitReady = false;

  Future<void> init() async {
    if (_keyPair != null) return;
    try {
      if (!_mediaKitReady) {
        MediaKit.ensureInitialized();
        _mediaKitReady = true;
      }
    } catch (e) {
      _lastErrorCode = 'media_unavailable';
      notifyListeners();
      throw StateError('MediaKit.ensureInitialized failed: $e');
    }
    // Load the device identity BEFORE constructing the media Player so that a
    // secure-store failure on retry cannot leak a second undisposed Player
    // (the old order created the Player first, then awaited loadOrCreate).
    try {
      _keyPair = await _identityStore.loadOrCreate();
    } catch (e) {
      _lastErrorCode = 'identity_unavailable';
      notifyListeners();
      throw StateError('identity store loadOrCreate failed: $e');
    }
    _acl = RoomAcl(ownerDeviceId: _keyPair!.identity.deviceId);
    _chain = CommitChain(genesisHash: _genesisHash ?? '0' * 64);
    _player = _injectedPlayer ??
        Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
          ),
        );
    _mediaCompletedSub = _player!.stream.completed.listen(_onPlayerCompleted);
    _mediaErrorSub = _player!.stream.error.listen(_onPlayerError);
    _signaling.messages.listen(_onSignalingMessage);
    _signaling.connection.listen(_onConnectionState);
    AppSettings.instance.addListener(updateLocalProfile);
    _lifecycleObserver = _LifecycleObserver(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  void _handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_roomId != null && !_closing && !_signaling.isConnected) {
        if (_connectionState != RoomConnectionState.reconnecting) {
          _connectionState = RoomConnectionState.reconnecting;
          notifyListeners();
        }
        unawaited(retry());
      }
    }
  }

  void updateLocalProfile() {
    final self = _selfId ?? _keyPair?.identity.deviceId;
    if (self == null) return;
    final localName = AppSettings.instance.effectiveDisplayName;
    final localAvatar = AppSettings.instance.avatar;
    final idx = _members.indexWhere((m) => m.deviceId == self);
    if (idx >= 0) {
      _members[idx] = _members[idx].copyWith(
        displayName: localName.isNotEmpty ? localName : _shortId(self),
        avatar: localAvatar,
      );
      notifyListeners();
    }
  }

  Future<void> setSignalingUrl(String url) async {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      throw ArgumentError('signaling URL must be ws:// or wss://');
    }
    _configuredSignalingUrl = clean;
    // An active room's invitations and reconnects retain its original server.
    if (_roomId == null) _signalingUrl = clean;
  }

  // ------------------------------------------------------------- keep alive & offline checks

  bool _keepAliveActive = false;

  Future<void> syncKeepAlive([bool? forceEnabled]) async {
    final enabled = forceEnabled ?? AppSettings.instance.backgroundKeepAlive;
    final inActiveRoom = _roomId != null && _connectionState != RoomConnectionState.disconnected;
    final shouldHold = enabled && inActiveRoom;

    if (shouldHold == _keepAliveActive) return;
    _keepAliveActive = shouldHold;

    try {
      if (shouldHold) {
        if (!kIsWeb) {
          try {
            await WakelockPlus.enable();
          } catch (_) {}
          if (defaultTargetPlatform == TargetPlatform.android) {
            const channel = MethodChannel('com.norns.eir/media_picker');
            await channel.invokeMethod<bool>('acquireKeepAliveLock');
          }
        }
      } else {
        if (!kIsWeb) {
          try {
            await WakelockPlus.disable();
          } catch (_) {}
          if (defaultTargetPlatform == TargetPlatform.android) {
            const channel = MethodChannel('com.norns.eir/media_picker');
            await channel.invokeMethod<bool>('releaseKeepAliveLock');
          }
        }
      }
    } catch (_) {}
  }

  bool isItemSourceOffline(PlaylistItem item) {
    if (item.sourceType != 'local') return false;
    final mediaId = item.localMediaId;
    if (mediaId == null) return false;
    final sourceId = _knownLocalMediaSources[mediaId];
    if (sourceId == null) return false;
    if (sourceId == _selfId) return false;
    final member = _members.firstWhere(
      (m) => m.deviceId == sourceId,
      orElse: () => RoomMember(
        deviceId: sourceId,
        displayName: '',
        role: RoomRole.member,
        online: false,
      ),
    );
    return !member.online;
  }

  PlaybackLoopMode _loopMode = PlaybackLoopMode.loopAll;
  PlaybackLoopMode get loopMode => _loopMode;
  void setLoopMode(PlaybackLoopMode mode) {
    _loopMode = mode;
    notifyListeners();
  }

  final StreamController<DanmakuMessage> _danmakuController =
      StreamController<DanmakuMessage>.broadcast();
  Stream<DanmakuMessage> get danmakuStream => _danmakuController.stream;

  void sendDanmaku(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final senderName = AppSettings.instance.nickname.isNotEmpty
        ? AppSettings.instance.nickname
        : (_keyPair?.identity.deviceId.substring(0, 6) ?? 'User');
    final msg = DanmakuMessage(
      id: _uuid.v4(),
      sender: senderName,
      text: trimmed,
      timestamp: DateTime.now(),
    );
    _danmakuController.add(msg);
    final payload = <String, dynamic>{
      'type': 'danmaku_msg',
      'id': msg.id,
      'sender': msg.sender,
      'text': msg.text,
      'timestamp': msg.timestamp.toIso8601String(),
    };
    unawaited(_sendDc(payload));
    if (_roomId != null) {
      _signaling.send({
        'type': 'signal',
        'roomId': _roomId,
        'kind': 'danmaku',
        'payload': payload,
      });
    }
  }

  void _handleIncomingDanmaku(Map<String, dynamic> msg) {
    final text = msg['text'] as String?;
    final sender = msg['sender'] as String? ?? 'Peer';
    final id = msg['id'] as String? ?? _uuid.v4();
    final timeStr = msg['timestamp'] as String?;
    final time = timeStr != null
        ? (DateTime.tryParse(timeStr) ?? DateTime.now())
        : DateTime.now();
    if (text != null && text.trim().isNotEmpty) {
      _danmakuController.add(DanmakuMessage(
        id: id,
        sender: sender,
        text: text.trim(),
        timestamp: time,
      ));
    }
  }

  PlaylistItem? _findNextPlayableItem([String? fromItemId]) {
    if (_playlist.isEmpty) return null;
    final startIndex = fromItemId != null
        ? _playlist.indexWhere((it) => it.itemId == fromItemId)
        : -1;
    final count = _playlist.length;
    for (var i = 1; i <= count; i++) {
      final index = (startIndex + i) % count;
      final candidate = _playlist[index];
      if (candidate.itemId == fromItemId) continue;
      if (!isItemSourceOffline(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  // ------------------------------------------------------------- rooms

  Future<void> createRoom() async {
    _signalingUrl = _configuredSignalingUrl ?? _signalingUrl;
    if (_keyPair == null || _signalingUrl == null) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    _resetRoomState(full: true);
    _connectionState = RoomConnectionState.connecting;
    notifyListeners();

    final roomId = _uuid.v4();
    final sessionId = _uuid.v4();
    final token = generateInviteToken();
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    _genesis = buildGenesis(
      roomId: roomId,
      sessionId: sessionId,
      ownerPublicKey: _keyPair!.identity.publicKeyBase64,
      createdAtMs: createdAtMs,
    );
    _genesisHash = genesisHashHex(_genesis!);
    _sessionId = sessionId;
    _roomId = roomId;
    _inviteEpoch = 1;
    _ownerPublicKey = _keyPair!.identity.publicKeyBase64;
    _chain = CommitChain(genesisHash: _genesisHash!);
    _acl = RoomAcl(ownerDeviceId: _keyPair!.identity.deviceId);

    try {
      await _signaling.connect(_signalingUrl!);
    } catch (_) {
      _lastErrorCode = 'signaling_unavailable';
      _connectionState = RoomConnectionState.disconnected;
      _resetRoomState(full: true);
      notifyListeners();
      return;
    }

    _roomCreated = Completer<void>();
    await _signaling.send({
      'type': 'create_room',
      'protocolVersion': kProtocolVersion,
      'roomId': roomId,
      'token': token,
      'deviceId': _keyPair!.identity.deviceId,
      'ownerPublicKey': _keyPair!.identity.publicKeyBase64,
      'sessionId': sessionId,
      'genesisHash': _genesisHash,
      'inviteEpoch': _inviteEpoch,
    });
    try {
      await _roomCreated!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _lastErrorCode = 'signaling_unavailable';
      _connectionState = RoomConnectionState.disconnected;
      await _signaling.disconnect();
      _resetRoomState(full: true);
      notifyListeners();
      return;
    } catch (_) {
      await _signaling.disconnect();
      await _teardownPeer();
      _resetRoomState(full: true);
      _connectionState = RoomConnectionState.disconnected;
      notifyListeners();
      return; // Preserve the server's rejection code.
    }

    final localName = AppSettings.instance.effectiveDisplayName;
    _members.add(RoomMember(
      deviceId: _keyPair!.identity.deviceId,
      displayName: localName.isNotEmpty
          ? localName
          : _shortId(_keyPair!.identity.deviceId),
      role: RoomRole.owner,
      avatar: AppSettings.instance.avatar,
    ));
    _clock.forceOffset(Duration.zero);
    final invite = InviteData(
      signalingUrl: _signalingUrl!,
      roomId: roomId,
      sessionId: sessionId,
      inviteEpoch: _inviteEpoch,
      token: token,
      ownerPublicKey: _keyPair!.identity.publicKeyBase64,
      genesisHash: _genesisHash!,
      expiresAtMs:
          DateTime.now().add(inviteLifetime).millisecondsSinceEpoch,
    );
    _inviteText = await buildSignedInvite(
      invite,
      _keyPair!,
      identityStore: _identityStore,
    );
    _cachedToken = token;
    _connectionState = RoomConnectionState.connected;
    _lastErrorCode = null;
    unawaited(syncKeepAlive());
    notifyListeners();
  }

  Future<void> joinRoomByCode(String code) async {
    final cleanCode = code.replaceAll(RegExp(r'\s+'), '').trim();
    if (_keyPair == null) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    _signalingUrl = _configuredSignalingUrl ?? _signalingUrl ?? AppSettings.instance.signalingUrl;
    if (_signalingUrl == null || _signalingUrl!.isEmpty) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    _resetRoomState(full: true);
    _connectionState = RoomConnectionState.connecting;
    notifyListeners();

    try {
      await _signaling.connect(_signalingUrl!);
    } catch (_) {
      _lastErrorCode = 'signaling_unavailable';
      _connectionState = RoomConnectionState.disconnected;
      _resetRoomState(full: true);
      notifyListeners();
      return;
    }

    _roomCodeQuery = Completer<Map<String, dynamic>>();
    await _signaling.send({
      'type': 'query_room_code',
      'roomCode': cleanCode,
    });

    final Map<String, dynamic> info;
    try {
      info = await _roomCodeQuery!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _lastErrorCode = 'room_not_found';
      _connectionState = RoomConnectionState.disconnected;
      await _signaling.disconnect();
      _resetRoomState(full: true);
      notifyListeners();
      return;
    } catch (_) {
      _lastErrorCode = 'room_not_found';
      _connectionState = RoomConnectionState.disconnected;
      await _signaling.disconnect();
      _resetRoomState(full: true);
      notifyListeners();
      return;
    }

    final roomId = info['roomId'] as String?;
    final token = info['token'] as String?;
    final ownerPublicKey = info['ownerPublicKey'] as String?;
    final sessionId = info['sessionId'] as String?;
    final genesisHash = info['genesisHash'] as String?;
    final inviteEpoch = (info['inviteEpoch'] as int?) ?? 1;

    if (roomId == null || token == null || ownerPublicKey == null || sessionId == null || genesisHash == null) {
      _lastErrorCode = 'invalid_invite';
      _connectionState = RoomConnectionState.disconnected;
      await _signaling.disconnect();
      _resetRoomState(full: true);
      notifyListeners();
      return;
    }

    _roomCode = cleanCode;
    _cachedToken = token;
    _peerDeviceId = deviceIdFromPublicKey(ownerPublicKey);
    _roomId = roomId;
    _sessionId = sessionId;
    _genesisHash = genesisHash;
    _genesis = null;
    _inviteEpoch = inviteEpoch;
    _ownerPublicKey = ownerPublicKey;
    _chain = CommitChain(genesisHash: genesisHash);
    _acl = RoomAcl(ownerDeviceId: _peerDeviceId!);

    _joinAccepted = Completer<void>();
    await _signaling.send({
      'type': 'join_room',
      'protocolVersion': kProtocolVersion,
      'roomId': roomId,
      'token': token,
      'deviceId': _keyPair!.identity.deviceId,
      'publicKey': _keyPair!.identity.publicKeyBase64,
      'inviteEpoch': inviteEpoch,
    });

    try {
      await _joinAccepted!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _lastErrorCode = 'signaling_unavailable';
      _connectionState = RoomConnectionState.disconnected;
      await _signaling.disconnect();
      _resetRoomState(full: true);
      notifyListeners();
      return;
    } catch (_) {
      await _signaling.disconnect();
      await _teardownPeer();
      _resetRoomState(full: true);
      _connectionState = RoomConnectionState.disconnected;
      notifyListeners();
      return;
    }

    _connectionState = RoomConnectionState.connected;
    _lastErrorCode = null;
    unawaited(syncKeepAlive());
    notifyListeners();
  }

  Future<void> joinRoom(String inviteText) async {
    final trimmed = inviteText.trim();
    final digitsOnly = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^\d{6}$').hasMatch(digitsOnly)) {
      return joinRoomByCode(digitsOnly);
    }
    final codeUriMatch = RegExp(r'[?&]code=(\d{6})').firstMatch(trimmed);
    if (codeUriMatch != null) {
      return joinRoomByCode(codeUriMatch.group(1)!);
    }

    if (_keyPair == null) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    _resetRoomState(full: true);
    final InviteData invite;
    try {
      invite = await decodeAndVerifyInvite(
        inviteText,
        identityStore: _identityStore,
      );
    } on InviteException catch (e) {
      _lastErrorCode = e.code;
      _connectionState = RoomConnectionState.disconnected;
      notifyListeners();
      return;
    }

    _cachedToken = invite.token;
    _peerDeviceId = invite.ownerDeviceId;
    _signalingUrl = invite.signalingUrl;
    _roomId = invite.roomId;
    _sessionId = invite.sessionId;
    _genesisHash = invite.genesisHash;
    _genesis = null; // guests never see the genesis, only its hash
    _inviteEpoch = invite.inviteEpoch;
    _ownerPublicKey = invite.ownerPublicKey;
    _chain = CommitChain(genesisHash: invite.genesisHash);
    _acl = RoomAcl(ownerDeviceId: invite.ownerDeviceId);
    _connectionState = RoomConnectionState.connecting;
    notifyListeners();

    try {
      await _signaling.connect(_signalingUrl!);
    } catch (_) {
      _lastErrorCode = 'signaling_unavailable';
      _connectionState = RoomConnectionState.disconnected;
      _resetRoomState(full: true);
      notifyListeners();
      return;
    }

    _joinAccepted = Completer<void>();
    await _signaling.send({
      'type': 'join_room',
      'protocolVersion': kProtocolVersion,
      'roomId': invite.roomId,
      'token': invite.token,
      'deviceId': _keyPair!.identity.deviceId,
      'publicKey': _keyPair!.identity.publicKeyBase64,
      'inviteEpoch': invite.inviteEpoch,
    });
    try {
      await _joinAccepted!.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _lastErrorCode = 'signaling_unavailable';
      _connectionState = RoomConnectionState.disconnected;
      await _signaling.disconnect();
      _resetRoomState(full: true);
      notifyListeners();
      return;
    } catch (_) {
      await _signaling.disconnect();
      await _teardownPeer();
      _resetRoomState(full: true);
      _connectionState = RoomConnectionState.disconnected;
      notifyListeners();
      return;
    }
    // Members draw synchronously from room creation; chain already seeded.
    _connectionState = RoomConnectionState.connected;
    _lastErrorCode = null;
    unawaited(syncKeepAlive());
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    unawaited(_player?.stop() ?? Future<void>.value());
    if (_roomId == null) {
      await _signaling.disconnect();
      _resetRoomState(full: true);
      _connectionState = RoomConnectionState.disconnected;
      notifyListeners();
      return;
    }
    final roomId = _roomId;
    try {
      await _signaling.send({'type': 'leave', 'roomId': roomId});
    } catch (_) {}
    await _signaling.disconnect();
    await _teardownPeer();
    _resetRoomState(full: true);
    _connectionState = RoomConnectionState.disconnected;
    notifyListeners();
  }

  /// Owner-only. Publishes a signed `room_close` commit, disbands the room
  /// on the signaling server and resets local room state.
  Future<void> closeRoom() async {
    if (_keyPair == null) return;
    if (role != RoomRole.owner) {
      _lastErrorCode = 'permission_denied';
      notifyListeners();
      return;
    }
    final roomId = _roomId;
    if (roomId != null) {
      await _publishCommit(
        requestId: _uuid.v4(),
        action: 'room_close',
        params: const <String, Object?>{},
      );
      try {
        await _signaling.send({'type': 'disband', 'roomId': roomId});
      } catch (_) {}
    }
    _teardownPeer();
    await _signaling.disconnect();
    _resetRoomState(full: true);
    _connectionState = RoomConnectionState.disconnected;
    notifyListeners();
  }

  void _resetRoomState({bool full = false}) {
    if (full) {
      unawaited(syncKeepAlive(false));
    }
    _roomGeneration++;
    _publishQueue = Future<void>.value();
    _commitApplyQueue = Future<void>.value();
    _clock.resetEstimate();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _reconnecting = false;
    _reconnectExhausted = false;
    _microRateAdjusted = false;
    _lastSeekMonoMs = 0;
    _peerLastSeenMonoMs = null;
    _iceRestartAttempts = 0;
    _roomCreated = null;
    _joinAccepted = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('room reset'));
      }
    }
    _pendingRequests.clear();
    _requestToCommitSeq.clear();
    _members.clear();
    _playlist.clear();
    _telemetry.clear();
    _currentItemId = null;
    _offlineMediaId = null;
      _loadedItemId = null;
      _errorItemId = null;
      _playback = PlaybackState();
    _peerVerified = false;
    _peerDeviceId = null;
    _peerPublicKey = null;
    _peerBaseSeqHigh = 0;
    _localChallenge = null;
    if (full) {
      _knownLocalMediaIds.clear();
      _knownLocalMediaSources.clear();
      _localMediaPaths.clear();
      _manifestSignatures.clear();
      final media = _media;
      _media = null;
      if (media != null) {
        unawaited(media.dispose());
      }
      _inviteText = null;
      _roomCode = null;
      _roomId = null;
      _sessionId = null;
      _genesis = null;
      _genesisHash = null;
      _ownerPublicKey = null;
      _inviteEpoch = 1;
      _chain = CommitChain(genesisHash: '0' * 64);
      _acl = RoomAcl(ownerDeviceId: '');
    }
    if (_keyPair != null && full) {
      }
  }

  static String _shortId(String deviceId) =>
      deviceId.length <= 12 ? deviceId : deviceId.substring(0, 12);

  // ----------------------------------------------------- signaling plane

  void _onConnectionState(bool connected) {
    if (connected || _roomId == null || _closing) return;
    // `disconnected` is terminal until an explicit retry(): a stray socket
    // callback after the bounded loop gave up must not revive it.
    if (_connectionState == RoomConnectionState.disconnected) return;
    if (_reconnectExhausted || _retryInFlight) return;
    // One cycle is already running; its failed attempts report `false` here.
    // Ignoring those keeps the attempt count deterministic and prevents a
    // second timer from being scheduled from inside an in-flight attempt.
    if (_reconnecting &&
        _connectionState == RoomConnectionState.reconnecting) {
      return;
    }
    _connectionState = RoomConnectionState.reconnecting;
    notifyListeners();
    _scheduleReconnect(initial: true);
  }

  void _scheduleReconnect({bool initial = false}) {
    _reconnectTimer?.cancel();
    _reconnecting = true;
    const delays = [1100, 2100, 4200];
    final delay = delays[_reconnectAttempt.clamp(0, 2)];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(milliseconds: delay), () async {
      if (_roomId == null || _closing || _reconnectExhausted) return;
      try {
        await _signaling.connect(_signalingUrl!);
        await _reconnectRegisterAndSettle();
      } catch (_) {
        if (_reconnectAttempt < 3) {
          _scheduleReconnect();
        } else {
          // Bounded auto-retry is over: expose a real terminal state so the
          // UI can offer the manual retry entry, and stop the loop. Room,
          // identity, playlist and a surviving data channel are kept.
          _reconnectExhausted = true;
          _reconnecting = false;
          _connectionState = RoomConnectionState.disconnected;
          _lastErrorCode = 'signaling_unavailable';
          notifyListeners();
        }
        return;
      }
    });
  }

  /// Re-registers the current room/identity with signaling and restores the
  /// data channel if needed. Shared by auto-reconnect (`_scheduleReconnect`)
  /// and the public manual `retry()`. Owner rotates the invite epoch only when
  /// the registration is a reconnect (so an old invite is invalidated after a
  /// signaling restart that wiped the room), and syncs back to the server's
  /// epoch on an idempotent re-join.
  Future<void> _reconnectRegisterAndSettle() async {
    await _registerWithSignaling();
    _reconnectAttempt = 0;
    _reconnectExhausted = false;
    _iceRestartAttempts = 0;
    // A completed reconnect makes the earlier connectivity error stale; other
    // error codes (media, invite, …) are left untouched.
    if (_lastErrorCode == 'signaling_unavailable' ||
        _lastErrorCode == 'connection_failed') {
      _lastErrorCode = null;
    }
    if (_dc == null || _dcStateOpen() != true) {
      await _teardownPeer();
      if (role == RoomRole.owner) {
        await _startWebRtc(isOwner: true);
      }
      // members wait for the owner's fresh offer
    } else {
      _connectionState = RoomConnectionState.connected;
      notifyListeners();
      unawaited(_requestResync(force: true));
    }
  }

  Future<void> _registerWithSignaling() async {
    if (role == RoomRole.owner) {
      if (_reconnecting) {
        // Rotate the invite epoch so any invite distributed before a signaling
        // restart (which wiped the room) is invalidated. Members must obtain a
        // fresh invite to (re)join the recreated room. On an idempotent
        // re-join to a still-alive room, the server returns `rejoined:true`
        // and we sync back to its epoch in the room_created handler.
        _inviteEpoch += 1;
      }
      final payload = <String, Object?>{
        'type': 'create_room',
        'protocolVersion': kProtocolVersion,
        'roomId': _roomId,
        'token': _cachedToken ?? generateInviteToken(),
        'deviceId': _keyPair!.identity.deviceId,
        'ownerPublicKey': _keyPair!.identity.publicKeyBase64,
        'sessionId': _sessionId,
        'genesisHash': _genesisHash,
        'inviteEpoch': _inviteEpoch,
      };
      if (_roomCode != null && _roomCode!.isNotEmpty) {
        payload['roomCode'] = _roomCode;
      }
      await _signaling.send(payload);
    } else {
      await _signaling.send({
        'type': 'join_room',
        'protocolVersion': kProtocolVersion,
        'roomId': _roomId,
        'token': await _lastInviteToken(),
        'deviceId': _keyPair!.identity.deviceId,
        'publicKey': _keyPair!.identity.publicKeyBase64,
        'inviteEpoch': _inviteEpoch,
      });
    }
  }

  bool? _dcStateOpen() {
    final s = _dc?.state;
    if (s == null) return null;
    return s == RTCDataChannelState.RTCDataChannelOpen;
  }

  /// Regenerates the invite text after the room was recreated with a rotated
  /// epoch (signaling restart). The data channel is left intact if it
  /// survived the drop; we just refresh the shareable invite and resync.
  Future<void> _finalizeRecreatedRoom() async {
    try {
      _inviteText = await buildSignedInvite(
        InviteData(
          signalingUrl: _signalingUrl!,
          roomId: _roomId!,
          sessionId: _sessionId!,
          inviteEpoch: _inviteEpoch,
          token: _cachedToken ?? '',
          ownerPublicKey: _keyPair!.identity.publicKeyBase64,
          genesisHash: _genesisHash!,
          expiresAtMs:
              DateTime.now().add(inviteLifetime).millisecondsSinceEpoch,
        ),
        _keyPair!,
        identityStore: _identityStore,
      );
    } catch (_) {
      _lastErrorCode = 'identity_unavailable';
      notifyListeners();
      return;
    }
    unawaited(_requestResync(force: true));
  }

  // The invite token is intentionally not kept beyond inviteText creation;
  // re-join uses the same identity and is idempotent on the server, but the
  // token itself is required to re-consume. We therefore retain it only in
  // memory for the room's lifetime.
  String? _cachedToken;
  Future<String> _lastInviteToken() async => _cachedToken ?? '';

  void _onSignalingMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'room_created':
        final rejoined = msg['rejoined'] == true;
        final serverEpoch = msg['inviteEpoch'] as int?;
        final serverCode = msg['roomCode'] as String?;
        if (serverCode != null && serverCode.isNotEmpty) {
          _roomCode = serverCode;
        }
        if (rejoined) {
          // Idempotent re-registration to a still-alive room: no epoch change.
          _reconnecting = false;
          if (serverEpoch != null) _inviteEpoch = serverEpoch;
          _connectionState = RoomConnectionState.connected;
          notifyListeners();
        } else if (_reconnecting) {
          // Signaling had lost the room: it was recreated with the rotated
          // epoch we sent. Regenerate the invite text so previously shared
          // invites (old epoch) are now invalid, then resync. The data channel
          // is left intact if it survived the drop.
          _reconnecting = false;
          if (serverEpoch != null) _inviteEpoch = serverEpoch;
          _connectionState = RoomConnectionState.connected;
          notifyListeners();
          unawaited(_finalizeRecreatedRoom());
        }
        final created = _roomCreated;
        if (created != null && !created.isCompleted) {
          created.complete();
        }
        return;
      case 'room_code_info':
        final query = _roomCodeQuery;
        if (query != null && !query.isCompleted) {
          query.complete(msg);
        }
        return;
      case 'join_accepted':
        final joined = _joinAccepted;
        if (joined != null && !joined.isCompleted) {
          joined.complete();
        } else {
          _connectionState = RoomConnectionState.connected;
          notifyListeners();
        }
        return;
      case 'member_joined':
        _handleMemberJoined(msg);
        return;
      case 'member_left':
        _handleMemberLeft(msg);
        return;
      case 'owner_changed':
        _handleOwnerChanged(msg);
        return;
      case 'disbanded':
        _handleDisbanded();
        return;
      case 'signal':
        unawaited(_handleSignal(msg));
        return;
      case 'error':
        _handleServerError(msg);
        return;
      default:
        return;
    }
  }

  void _handleMemberJoined(Map<String, dynamic> msg) {
    final deviceId = msg['deviceId'] as String?;
    if (deviceId == null || deviceId == _selfId) return;
    if (role == RoomRole.owner) {
      _peerDeviceId ??= deviceId;
    }
    _upsertMember(deviceId, online: true, joinedAt: msg['joinedAt'] as int?);
    if (role == RoomRole.owner &&
        (!_peerVerified || _dcStateOpen() != true)) {
      unawaited(_startWebRtc(isOwner: true));
    }
    notifyListeners();
  }

  void _handleOwnerChanged(Map<String, dynamic> msg) {
    final newOwner = (msg['newOwnerDeviceId'] ?? msg['newOwner']) as String?;
    if (newOwner == null || newOwner.isEmpty) return;
    _acl.transferOwnership(newOwner);
    _refreshMemberRoles();
    if (newOwner == _selfId) {
      _startRoomTimers();
      if (!_peerVerified || _dcStateOpen() != true) {
        unawaited(_startWebRtc(isOwner: true));
      }
      final currentItemId = _playback.itemId;
      if (currentItemId != null) {
        final currentItem = _playlist.firstWhere(
          (it) => it.itemId == currentItemId,
          orElse: () => PlaylistItem(itemId: '', title: '', sourceType: 'none'),
        );
        if (isItemSourceOffline(currentItem)) {
          final nextItem = _findNextPlayableItem(currentItemId);
          if (nextItem != null) {
            unawaited(_publishCommit(
              requestId: _uuid.v4(),
              action: 'switch_item',
              params: <String, Object?>{
                'itemId': nextItem.itemId,
                'positionMs': 0,
                'mode': 'playing',
              },
            ));
          }
        }
      }
    }
    notifyListeners();
  }

  void _handleMemberLeft(Map<String, dynamic> msg) {
    final deviceId = msg['deviceId'] as String?;
    if (deviceId == null) return;
    final idx = _members.indexWhere((m) => m.deviceId == deviceId);
    if (idx >= 0) {
      _members[idx] = _members[idx].copyWith(online: false);
    }
    if (_peerDeviceId == deviceId) {
      _peerVerified = false;
      _handshakeTimer?.cancel();
    }
    _telemetry.remove(deviceId);

    // If leaving member was the owner, succession rule:
    // admin first, then earliest joinedAt
    if (_acl.ownerDeviceId == deviceId) {
      final candidates = _members.where((m) => m.online && m.deviceId != deviceId).toList();
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) {
          final aAdmin = a.role == RoomRole.admin ? 1 : 0;
          final bAdmin = b.role == RoomRole.admin ? 1 : 0;
          if (aAdmin != bAdmin) return bAdmin.compareTo(aAdmin);
          return a.joinedAt.compareTo(b.joinedAt);
        });
        final successor = candidates.first;
        _acl.transferOwnership(successor.deviceId);
        _refreshMemberRoles();
        if (successor.deviceId == _selfId) {
          _startRoomTimers();
          if (!_peerVerified || _dcStateOpen() != true) {
            unawaited(_startWebRtc(isOwner: true));
          }
        }
      }
    }

    // If currently playing item was provided by this member, owner automatically switches to next playable item
    if (role == RoomRole.owner) {
      final currentItemId = _playback.itemId;
      if (currentItemId != null) {
        final currentItem = _playlist.firstWhere(
          (it) => it.itemId == currentItemId,
          orElse: () => PlaylistItem(itemId: '', title: '', sourceType: 'none'),
        );
        if (currentItem.sourceType == 'local' &&
            _knownLocalMediaSources[currentItem.localMediaId] == deviceId) {
          final nextItem = _findNextPlayableItem(currentItemId);
          if (nextItem != null) {
            unawaited(_publishCommit(
              requestId: _uuid.v4(),
              action: 'switch_item',
              params: <String, Object?>{
                'itemId': nextItem.itemId,
                'positionMs': 0,
                'mode': 'playing',
              },
            ));
          } else {
            unawaited(_publishCommit(
              requestId: _uuid.v4(),
              action: 'pause',
              params: <String, Object?>{
                'positionMs': 0,
              },
            ));
          }
        }
      }
    }

    notifyListeners();
  }

  void _handleDisbanded() {
    _teardownPeer();
    _resetRoomState(full: true);
    _connectionState = RoomConnectionState.disconnected;
    _lastErrorCode = null;
    unawaited(_player?.stop() ?? Future<void>.value());
    notifyListeners();
  }

  void _handleServerError(Map<String, dynamic> msg) {
    final code = msg['code'] as String? ?? 'signaling_unavailable';
    final mapped = const {
      'invalid_invite': 'invalid_invite',
      'invite_consumed': 'invite_consumed',
      'invite_stale': 'invalid_invite',
      'room_full': 'room_full',
      'room_not_found': 'room_not_found',
      'rate_limited': 'signaling_unavailable',
      'protocol_version': 'protocol_violation',
      'message_too_large': 'protocol_violation',
      'invalid_message': 'protocol_violation',
      'permission_denied': 'permission_denied',
    }[code] ??
        'signaling_unavailable';
    _lastErrorCode = mapped;
    final query = _roomCodeQuery;
    if (query != null && !query.isCompleted) {
      query.completeError(StateError(mapped));
    }
    final created = _roomCreated;
    if (created != null && !created.isCompleted) {
      created.completeError(StateError(mapped));
    }
    final joined = _joinAccepted;
    if (joined != null && !joined.isCompleted) {
      joined.completeError(StateError(mapped));
    }
    if (_connectionState != RoomConnectionState.connected) {
      _connectionState = RoomConnectionState.disconnected;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ WebRTC

  Future<void> _startWebRtc({required bool isOwner}) async {
    await _teardownPeer();
    _peerVerified = false;
    _handshakeTimer?.cancel();
    final Map<String, dynamic> config = {
      'iceServers': [
        {'urls': iceServers},
      ],
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);
    _pc = pc;
    _pendingIce.clear();
    _remoteDescriptionSet = false;

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (!identical(_pc, pc)) return;
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      unawaited(_signaling.send({
        'type': 'signal',
        'roomId': _roomId,
        'kind': 'ice',
        'candidate': candidate.toMap(),
      }));
    };
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (!identical(_pc, pc)) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _onIceFailed(isOwner);
      }
    };

    if (isOwner) {
      final dc = await pc.createDataChannel(
        'eir',
        RTCDataChannelInit()..ordered = true,
      );
      _wireDataChannel(dc);
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      await _signaling.send({
        'type': 'signal',
        'roomId': _roomId,
        'kind': 'offer',
        'sdp': offer.toMap(),
      });
    } else {
      pc.onDataChannel = (RTCDataChannel channel) {
        if (!identical(_pc, pc)) return;
        _wireDataChannel(channel);
      };
    }
  }

  int _iceRestartAttempts = 0;

  Future<void> _onIceFailed(bool isOwner) async {
    if (_closing) return;
    if (_dcStateOpen() == true) return; // surviving channel: keep it
    if (!isOwner) {
      if (_iceRestartAttempts >= 3) {
        _lastErrorCode = 'connection_failed';
        notifyListeners();
        return;
      }
      _iceRestartAttempts += 1;
      await Future<void>.delayed(const Duration(seconds: 4));
      if (_closing || _roomId == null) return;
      if (_dcStateOpen() != true && !_peerVerified) {
        _lastErrorCode = 'connection_failed';
        notifyListeners();
      }
      return;
    }
    if (_iceRestartAttempts >= 3) {
      _lastErrorCode = 'connection_failed';
      notifyListeners();
      return;
    }
    _iceRestartAttempts += 1;
    await Future<void>.delayed(
      Duration(milliseconds: [1100, 2100, 4200][(_iceRestartAttempts - 1) % 3]),
    );
    if (_closing || _roomId == null) return;
    await _teardownPeer();
    await _startWebRtc(isOwner: true);
  }

  final List<RTCIceCandidate> _pendingIce = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;

  Future<void> _handleSignal(Map<String, dynamic> msg) async {
    final kind = msg['kind'] as String?;
    final pc = _pc;
    if (kind == 'offer') {
      if (role == RoomRole.owner) {
        // Glare avoidance: only the owner offers. Ignore rogue offers.
        return;
      }
      if (pc == null) {
        await _startWebRtc(isOwner: false);
      }
      final offerMap = (msg['sdp'] as Map?)?.cast<String, dynamic>();
      final descSdp = offerMap?['sdp'] as String?;
      if (descSdp == null) return;
      final pcNow = _pc!;
      await pcNow.setRemoteDescription(
        RTCSessionDescription(descSdp, 'offer'),
      );
      _remoteDescriptionSet = true;
      await _flushPendingIce();
      final answer = await pcNow.createAnswer({});
      await pcNow.setLocalDescription(answer);
      await _signaling.send({
        'type': 'signal',
        'roomId': _roomId,
        'kind': 'answer',
        'sdp': answer.toMap(),
      });
      return;
    }
    if (kind == 'answer') {
      if (pc == null || role != RoomRole.owner) return;
      final answerMap = (msg['sdp'] as Map?)?.cast<String, dynamic>();
      final descSdp = answerMap?['sdp'] as String?;
      if (descSdp == null) return;
      await pc.setRemoteDescription(RTCSessionDescription(descSdp, 'answer'));
      _remoteDescriptionSet = true;
      await _flushPendingIce();
      return;
    }
    if (kind == 'danmaku') {
      final payload = (msg['payload'] as Map?)?.cast<String, dynamic>();
      if (payload != null) {
        _handleIncomingDanmaku(payload);
      }
      return;
    }
    if (kind == 'ice') {
      final candMap = (msg['candidate'] as Map?)?.cast<String, dynamic>();
      if (candMap == null) return;
      final candidate = RTCIceCandidate(
        candMap['candidate'] as String?,
        candMap['sdpMid'] as String?,
        (candMap['sdpMLineIndex'] as num?)?.toInt(),
      );
      if (_remoteDescriptionSet && pc != null) {
        try {
          await pc.addCandidate(candidate);
        } catch (_) {}
      } else {
        if (_pendingIce.length < 64) _pendingIce.add(candidate);
      }
      return;
    }
  }

  Future<void> _flushPendingIce() async {
    final pc = _pc;
    if (pc == null) return;
    final queued = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();
    for (final c in queued) {
      try {
        await pc.addCandidate(c);
      } catch (_) {}
    }
  }

  void _wireDataChannel(RTCDataChannel channel) {
    _dc = channel;
    channel.onDataChannelState = (state) {
      if (!identical(_dc, channel)) return;
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        unawaited(_onDataChannelOpen());
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _peerVerified = false;
        _stopRoomTimers();
        if (!_closing && _roomId != null) {
          if (role == RoomRole.owner) {
            unawaited(_onIceFailed(true));
          } else {
            _lastErrorCode = 'connection_failed';
          }
        }
        notifyListeners();
      }
    };
    channel.onMessage = (msg) {
      if (!identical(_dc, channel)) return;
      _peerLastSeenMonoMs = _clock.localMonoMs();
      if (msg.isBinary) {
        if (!_peerVerified) return;
        _media?.onBinary(msg.binary);
        return;
      }
      final text = msg.text;
      // Bound incoming text frames BEFORE jsonDecode. Binary frames are
      // already bounded by the media frame parser; here we stop a hostile or
      // malformed oversized text envelope from being parsed at all.
      if (text.length > kMaxEnvelopeBytes) {
        _flagProtocolViolation();
        return;
      }
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          unawaited(_handleDcMessage(Map<String, Object?>.from(decoded)));
        }
      } catch (e) {
        _flagProtocolViolation();
      }
    };
  }

  Future<void> _teardownPeer() async {
    _handshakeTimer?.cancel();
    _stopRoomTimers();
    final dc = _dc;
    _dc = null;
    final pc = _pc;
    _pc = null;
    _remoteDescriptionSet = false;
    _pendingIce.clear();
    _peerVerified = false;
    try {
      await dc?.close();
    } catch (_) {}
    try {
      await pc?.close();
    } catch (_) {}
    _handshakeTimer = null;
  }

  // ------------------------------------------------------ local media

  void _sendMediaControl(Map<String, dynamic> message) {
    if (!_peerVerified || _roomId == null || _sessionId == null) return;
    unawaited(_sendDc(<String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      ...message,
    }));
  }

  Future<void> _sendMediaBinary(Uint8List frame) async {
    final dc = _dc;
    if (dc == null || !_peerVerified) {
      throw MediaException('source_offline', 'media channel unavailable');
    }
    try {
      await dc.send(RTCDataChannelMessage.fromBinary(frame));
    } catch (_) {
      throw MediaException('source_offline', 'media channel send failed');
    }
  }

  /// Manifests arriving via the chunked transfer path are accepted only
  /// when a signed commit/snapshot in THIS room already referenced the
  /// exact mediaId, and the source is the local peer (or us). Everything
  /// else is denied.
  Future<bool> _authorizeManifest(MediaManifest manifest) async {
    if (!_knownLocalMediaIds.contains(manifest.mediaId)) return false;
    final src = manifest.sourceDeviceId;
    // The commit/snapshot chain is authoritative for WHICH device owns a
    // mediaId; the manifest transfer must present the same source device.
    if (_knownLocalMediaSources[manifest.mediaId] != src) return false;
    if (src == _selfId) return true;
    if (src != _peerDeviceId) return false;
    return _acl.isAdmitted(src);
  }

  Future<bool> _authorizeMediaRequest(String mediaId) async {
    return _knownLocalMediaIds.contains(mediaId) && _peerVerified;
  }

  Future<LocalMediaService> _ensureMediaService() async {
    final existing = _media;
    if (existing != null) return existing;
    final generation = _roomGeneration;
    final self = _selfId!;
    final service = LocalMediaService(
      sendControl: (message) {
        if (_roomGeneration == generation) _sendMediaControl(message);
      },
      sendBinary: (frame) async {
        if (_roomGeneration != generation) throw MediaException('source_offline');
        await _sendMediaBinary(frame);
      },
      bufferedAmount: () => _dc?.getBufferedAmount() ?? 0,
      maxMessageBytes: () => kMediaMaxMessageBytes,
      localDeviceId: self,
      manifestAuthorizer: _authorizeManifest,
      requestAuthorizer: _authorizeMediaRequest,
      onSourceOffline: (mediaId) {
        if (_roomGeneration != generation) return;
        if (_closing || _itemById(_currentItemId ?? '')?.localMediaId != mediaId) return;
        _offlineMediaId = mediaId;
        _lastErrorCode = 'source_offline';
        notifyListeners();
      },
      onSourceAvailable: (mediaId) {
        if (_roomGeneration != generation) return;
        if (_closing ||
            _offlineMediaId != mediaId ||
            _itemById(_currentItemId ?? '')?.localMediaId != mediaId) {
          return;
        }
        _offlineMediaId = null;
        if (_lastErrorCode == 'source_offline') {
          _lastErrorCode = null;
          notifyListeners();
        }
      },
      // F5/A17: a real native disk-full/quota error surfaces immediately on
      // the existing error channel. clearUnprotectedCache() clears the media
      // latch/code; we mirror that on the core side after a successful clear.
      onStorageError: (code) {
        if (_roomGeneration != generation) return;
        _lastErrorCode = code; // 'storage_full'
        notifyListeners();
      },
    );
    _media = service;
    await service.start();
    return service;
  }

  Future<void> _handleManifestRequest(Map<String, Object?> msg) async {
    if (!_peerVerified) return;
    final sender = msg['senderId'] as String?;
    final mediaId = msg['mediaId'];
    if (sender != _peerDeviceId) return;
    if (mediaId is! String || !isHex64(mediaId)) return;
    if (!_knownLocalMediaIds.contains(mediaId)) return;
    try {
      await _media?.writeManifestChunksFor(mediaId);
    } catch (_) {}
  }

  // -------------------------------------------------------- handshake

  Future<void> _onDataChannelOpen() async {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer(handshakeTimeout, () {
      _peerVerified = false;
      _lastErrorCode = 'handshake_failed';
      unawaited(_teardownPeer());
      notifyListeners();
    });
    _localChallenge = base64Encode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final fp = await localDtlsFingerprint(_pc!);
    if (fp == null) {
      // Explicit blocker: cannot bind the handshake to the DTLS transport.
      _failHandshake('handshake_failed');
      return;
    }
    final self = _keyPair!.identity;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': self.deviceId,
      'publicKey': self.publicKeyBase64,
      'challenge': _localChallenge,
      'fingerprint': fp,
      'genesisHash': _genesisHash,
    };
    final signature = await signDomain(
      'handshake_hello',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'handshake_hello', 'signature': signature}));
  }

  void _failHandshake(String code) {
    _peerVerified = false;
    _lastErrorCode = code;
    _handshakeTimer?.cancel();
    unawaited(_teardownPeer());
    notifyListeners();
  }

  Future<void> _handleDcMessage(Map<String, Object?> msg) async {
    final type = msg['type'];
    if (type is! String) return;
    if (_roomId == null || _sessionId == null) return;
    final isMedia = type.startsWith('media_');
    if (!isRoomScopedMessage(
      msg,
      roomId: _roomId!,
      sessionId: _sessionId!,
      expectedSenderId: isMedia ? _peerDeviceId : null,
    )) {
      if (type == 'handshake_hello' || type == 'handshake_done' || type == 'commit') {
        _flagProtocolViolation();
      }
      return;
    }
    if (isMedia && !_peerVerified) {
      return;
    }
    switch (type) {
      case 'danmaku_msg':
        _handleIncomingDanmaku(msg);
        return;
      case 'handshake_hello':
        await _handleHandshakeHello(msg);
        return;
      case 'handshake_done':
        await _handleHandshakeDone(msg);
        return;
      case 'commit':
        await _handleCommitWire(msg);
        return;
      case 'control_request':
        await _handleControlRequest(msg);
        return;
      case 'request_denied':
        await _handleRequestDenied(msg);
        return;
      case 'request_result':
        await _handleRequestResult(msg);
        return;
      case 'resync_request':
        await _handleResyncRequest(msg);
        return;
      case 'snapshot':
        await _handleSnapshot(msg);
        return;
      case 'peer_status':
        await _handlePeerStatus(msg);
        return;
      case 'time_ping':
        await _handleTimePing(msg);
        return;
      case 'time_pong':
        await _handleTimePong(msg);
        return;
      case 'media_manifest_request':
        await _handleManifestRequest(msg);
        return;
      case 'media_manifest_chunk':
        final service = _media;
        if (service == null) return;
        try {
          final manifest = await service.handleManifestChunk(msg);
          if (manifest == null || !identical(_media, service)) return;
          await _enqueueCommitApply(() async {
            final item = _itemById(_currentItemId ?? '');
            if (item == null || item.localMediaId != manifest.mediaId ||
                _loadedItemId == item.itemId) {
              return;
            }
            await _ensureMediaLoaded(item.itemId, seekTo: _expectedPositionNow());
            if (!identical(_media, service)) return;
            await _applyPlayerForCommit(_playback.mode, _playback.rateMilli);
            notifyListeners();
          });
        } catch (_) {
          // Malformed or unauthorized manifests never trigger a player load.
        }
        return;
      default:
        // media_range_request / media_range_cancel /
        // media_error are routed to the local media service.
        if (type.startsWith('media_')) {
          _media?.onControl(msg);
        }
        return;
    }
  }

  Future<bool> _verifySignedMessage(
    Map<String, Object?> msg,
    String purpose,
    String publicKeyBase64,
  ) async {
    final signature = msg['signature'];
    if (signature is! String) return false;
    final unsigned = Map<String, Object?>.from(msg)..remove('signature')..remove('type');
    return verifyDomain(
      purpose,
      unsigned,
      signature,
      publicKeyBase64,
      identityStore: _identityStore,
    );
  }

  Future<void> _handleHandshakeHello(Map<String, Object?> msg) async {
    Map<String, Object?> hello;
    try {
      hello = parseRestrictedMap(msg, '\$hello');
    } catch (_) {
      _flagProtocolViolation();
      return;
    }
    final senderId = hello['senderId'] as String?;
    final publicKey = hello['publicKey'] as String?;
    final challenge = hello['challenge'] as String?;
    final peerFingerprint = hello['fingerprint'] as String?;
    if (senderId == null ||
        publicKey == null ||
        challenge == null ||
        peerFingerprint == null ||
        hello['genesisHash'] != _genesisHash) {
      _failHandshake('handshake_failed');
      return;
    }
    if (!publicKeyMatchesDeviceId(publicKey, senderId)) {
      _failHandshake('handshake_failed');
      return;
    }
    if (role == RoomRole.member &&
        _ownerPublicKey != null &&
        senderId != deviceIdFromPublicKey(_ownerPublicKey!)) {
      // guests only accept the invited owner
      _failHandshake('handshake_failed');
      return;
    }
    if (role == RoomRole.owner &&
        _peerDeviceId != null &&
        senderId != _peerDeviceId) {
      _failHandshake('handshake_failed');
      return;
    }
    final ok = await verifyDomain(
      'handshake_hello',
      {
        ...Map<String, Object?>.from(hello)..remove('signature')..remove('type'),
      },
      hello['signature'] as String,
      publicKey,
      identityStore: _identityStore,
    );
    if (!ok) {
      _failHandshake('handshake_failed');
      return;
    }
    // Bind the claimed fingerprint to the actual DTLS transport.
    final remoteFp = await remoteDtlsFingerprint(_pc!);
    if (remoteFp == null ||
        !_fingerprintsMatch(remoteFp, peerFingerprint)) {
      _failHandshake('handshake_failed');
      return;
    }
    _peerDeviceId = senderId;
    _peerPublicKey = publicKey;
    _upsertMember(senderId, online: true);

    // Respond with our own authenticated done message, signing BOTH challenges.
    final localFp = await localDtlsFingerprint(_pc!);
    if (localFp == null) {
      _failHandshake('handshake_failed');
      return;
    }
    final donePayload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'publicKey': _keyPair!.identity.publicKeyBase64,
      'challenge': _localChallenge,
      'echoChallenge': challenge,
      'localFingerprint': localFp,
      'peerFingerprint': peerFingerprint,
      'genesisHash': _genesisHash,
    };
    final doneSignature = await signDomain(
      'handshake_done',
      donePayload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...donePayload, 'type': 'handshake_done', 'signature': doneSignature}));
  }

  Future<void> _handleHandshakeDone(Map<String, Object?> msg) async {
    Map<String, Object?> done;
    try {
      done = parseRestrictedMap(msg, '\$done');
    } catch (_) {
      _flagProtocolViolation();
      return;
    }
    final senderId = done['senderId'] as String?;
    final publicKey = done['publicKey'] as String?;
    final echoChallenge = done['echoChallenge'] as String?;
    final peerFingerprint = done['localFingerprint'] as String?;
    final claimedPeerFp = done['peerFingerprint'] as String?;
    if (senderId == null ||
        publicKey == null ||
        echoChallenge == null ||
        peerFingerprint == null ||
        claimedPeerFp == null) {
      _failHandshake('handshake_failed');
      return;
    }
    if (_peerDeviceId != null && senderId != _peerDeviceId) {
      _failHandshake('handshake_failed');
      return;
    }
    if (echoChallenge != _localChallenge) {
      // The peer must echo OUR exact challenge; anything else is a replay.
      _failHandshake('handshake_failed');
      return;
    }
    if (!publicKeyMatchesDeviceId(publicKey, senderId)) {
      _failHandshake('handshake_failed');
      return;
    }
    if (role == RoomRole.member &&
        _ownerPublicKey != null &&
        senderId != deviceIdFromPublicKey(_ownerPublicKey!)) {
      _failHandshake('handshake_failed');
      return;
    }
    final ok = await verifyDomain(
      'handshake_done',
      {
        ...Map<String, Object?>.from(done)..remove('signature')..remove('type'),
      },
      done['signature'] as String? ?? '',
      publicKey,
      identityStore: _identityStore,
    );
    if (!ok) {
      _failHandshake('handshake_failed');
      return;
    }
    // Peer's local fingerprint must equal our measured remote fingerprint.
    final remoteFp = await remoteDtlsFingerprint(_pc!);
    if (remoteFp == null || !_fingerprintsMatch(remoteFp, peerFingerprint)) {
      _failHandshake('handshake_failed');
      return;
    }
    // Peer's claimed view of OUR fingerprint must match our actual local one.
    final localFp = await localDtlsFingerprint(_pc!);
    if (localFp == null || !_fingerprintsMatch(localFp, claimedPeerFp)) {
      _failHandshake('handshake_failed');
      return;
    }
    _handshakeTimer?.cancel();
    _peerDeviceId = senderId;
    _peerPublicKey = publicKey;
    _peerVerified = true;
    _iceRestartAttempts = 0;
    _upsertMember(senderId, online: true);
    if (_selfId != null && !_members.any((m) => m.deviceId == _selfId)) {
      _upsertMember(_selfId!, online: true);
    }
    _startRoomTimers();
    notifyListeners();
    if (role == RoomRole.owner) {
      unawaited(_publishCommit(
        requestId: _uuid.v4(),
        action: 'member_admit',
        params: <String, Object?>{'memberId': senderId, 'role': 'member'},
      ));
    }
    unawaited(_requestResync(force: true));
    unawaited(_sendTimePing());
  }

  bool _fingerprintsMatch(String a, String b) {
    String norm(String s) =>
        s.replaceAll(':', '').replaceAll('-', '').toLowerCase();
    return norm(a) == norm(b);
  }

  void _flagProtocolViolation() {
    _lastErrorCode = 'protocol_violation';
    notifyListeners();
  }

  Future<bool> _sendDc(Map<String, Object?> message) async {
    final dc = _dc;
    if (dc == null) return false;
    try {
      await dc.send(RTCDataChannelMessage(jsonEncode(message)));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------- timer

  void _startRoomTimers() {
    _stopRoomTimers();
    if (role != RoomRole.owner) {
      _syncTimer = Timer.periodic(timeSyncInterval, (_) => _sendTimePing());
    }
    _statusTimer = Timer.periodic(statusInterval, (_) => _sendPeerStatus());
    _driftTimer = Timer.periodic(driftCheckInterval, (_) => _correctDrift());
  }

  void _stopRoomTimers() {
    _syncTimer?.cancel();
    _statusTimer?.cancel();
    _driftTimer?.cancel();
    _syncTimer = null;
    _statusTimer = null;
    _driftTimer = null;
  }

  Future<void> _sendTimePing() async {
    if (!_peerVerified) return;
    final probeId = _uuid.v4();
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'probeId': probeId,
      't1': _clock.localMonoMs(),
    };
    final signature = await signDomain(
      'time_ping',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'time_ping', 'signature': signature}));
  }

  Future<void> _handleTimePing(Map<String, Object?> msg) async {
    final receivedAt = _clock.localMonoMs();
    // Owner answers; both sides may receive pings but only leaders serve time.
    if (role != RoomRole.owner || !_peerVerified) return;
    final sender = msg['senderId'];
    if (sender is! String || sender != _peerDeviceId) return;
    if (!await _verifySignedMessage(msg, 'time_ping', _peerPublicKey!)) return;
    _markPeerActive(sender);
    final probeId = msg['probeId'];
    final t1 = msg['t1'];
    if (probeId is! String || t1 is! int) return;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'probeId': probeId,
      't1': t1,
      't2': receivedAt,
      't3': _clock.localMonoMs(),
    };
    final signature = await signDomain(
      'time_pong',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'time_pong', 'signature': signature}));
  }

  Future<void> _handleTimePong(Map<String, Object?> msg) async {
    final generation = _roomGeneration;
    final receivedAt = _clock.localMonoMs();
    if (role == RoomRole.owner || !_peerVerified) return;
    if (!await _verifySignedMessage(msg, 'time_pong', _ownerPublicKey!)) return;
    if (_roomGeneration != generation) return;
    if (_peerDeviceId != null) _markPeerActive(_peerDeviceId!);
    final t1 = msg['t1'];
    final t2 = msg['t2'];
    final t3 = msg['t3'];
    if (t1 is! int || t2 is! int || t3 is! int) return;
    _clock.addSample(t1: t1, t2: t2, t3: t3, t4: receivedAt);
  }

  Future<void> _sendPeerStatus() async {
    if (!_peerVerified) return;
    final player = _player;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'itemId': _currentItemId,
      'itemSeq': _playback.seq,
      'positionMs': player?.state.position.inMilliseconds ?? 0,
      'buffering': player?.state.buffering ?? false,
      'sharedMs': _sharedNowMs,
    };
    final signature = await signDomain(
      'peer_status',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'peer_status', 'signature': signature}));
    _selfTelemetry();
    _checkPeerLiveness();
  }

  void _markPeerActive(String peerId) {
    _peerLastSeenMonoMs = _clock.localMonoMs();
    final idx = _members.indexWhere((m) => m.deviceId == peerId);
    if (idx >= 0 && !_members[idx].online) {
      _members[idx] = _members[idx].copyWith(online: true);
      if (_offlineMediaId != null &&
          _itemById(_currentItemId ?? '')?.localMediaId == _offlineMediaId) {
        _offlineMediaId = null;
        if (_lastErrorCode == 'source_offline') {
          _lastErrorCode = null;
        }
      }
      notifyListeners();
    }
  }

  void _checkPeerLiveness() {
    final peerId = _peerDeviceId;
    if (!_peerVerified || peerId == null || _closing) return;
    final lastSeen = _peerLastSeenMonoMs;
    if (lastSeen != null && _clock.localMonoMs() - lastSeen > 12000) {
      final idx = _members.indexWhere((m) => m.deviceId == peerId);
      if (idx >= 0 && _members[idx].online) {
        _members[idx] = _members[idx].copyWith(online: false);
        final cur = _itemById(_currentItemId ?? '');
        if (cur?.localMediaId != null &&
            cur?.sourceType == 'local' &&
            _knownLocalMediaSources[cur!.localMediaId] == peerId) {
          _offlineMediaId = cur.localMediaId;
          _lastErrorCode = 'source_offline';
        }
        notifyListeners();
      }
    }
  }

  void _selfTelemetry() {
    if (_selfId == null) return;
    final player = _player;
    _telemetry[_selfId!] = MemberTelemetry(
      deviceId: _selfId!,
      itemId: _currentItemId,
      itemSeq: _playback.seq,
      positionMs: player?.state.position.inMilliseconds ?? 0,
      buffering: player?.state.buffering ?? false,
      sharedMs: _sharedNowMs,
    );
    notifyListeners();
  }

  Future<void> _handlePeerStatus(Map<String, Object?> msg) async {
    final sender = msg['senderId'];
    if (sender is! String || sender != _peerDeviceId) return;
    if (!await _verifySignedMessage(msg, 'peer_status', _peerPublicKey!)) return;
    _markPeerActive(sender);
    final itemId = msg['itemId'];
    final itemSeq = msg['itemSeq'];
    final positionMs = msg['positionMs'];
    final buffering = msg['buffering'];
    final sharedMs = msg['sharedMs'];
    if (itemSeq is! int || positionMs is! int || sharedMs is! int) return;
    _telemetry[sender] = MemberTelemetry(
      deviceId: sender,
      itemId: itemId is String ? itemId : null,
      itemSeq: itemSeq,
      positionMs: positionMs,
      buffering: buffering == true,
      sharedMs: sharedMs,
    );
    notifyListeners();
  }

  // ------------------------------------------------------------ commits

  Future<String> _requestResyncNow() async {
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'lastSeq': _chain.lastSeq,
    };
    final signature = await signDomain(
      'resync_request',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'resync_request', 'signature': signature}));
    return '';
  }

  Future<void> _requestResync({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastResyncRequest) < const Duration(seconds: 1)) {
      return;
    }
    _lastResyncRequest = now;
    if (!_peerVerified && !force) return;
    await _requestResyncNow();
  }

  void _scheduleParkedSweep() {
    _parkedSweepTimer?.cancel();
    _parkedSweepTimer = Timer(const Duration(milliseconds: 800), () {
      _enqueueCommitApply(() async {
        final ready = _chain.drainReady();
        if (ready.isNotEmpty) {
          for (final c in ready) {
            await _applyCommitSideEffects(c);
          }
          notifyListeners();
          return;
        }
        if (_chain.pendingCount > 0) {
          await _requestResync();
        }
      });
    });
  }

  Future<void> _handleCommitWire(Map<String, Object?> msg) {
    return _enqueueCommitApply(() => _handleCommitWireInner(msg));
  }

  /// Pure parse + room-scope + signature verification stay outside the
  /// apply queue; chain classification and all mutations run inside it.
  Future<void> _handleCommitWireInner(Map<String, Object?> msg) async {
    final generation = _roomGeneration;
    final ownerKey = _ownerPublicKey;
    if (ownerKey == null) {
      _flagProtocolViolation();
      return;
    }
    RoomCommit commit;
    try {
      commit = RoomCommit.fromMap(msg);
    } on FormatException {
      _flagProtocolViolation();
      return;
    } catch (_) {
      _flagProtocolViolation();
      return;
    }
    if (commit.roomId != _roomId || commit.sessionId != _sessionId) {
      _flagProtocolViolation();
      return;
    }
    final verified = await verifyDomain(
      CommitChain.signaturePurpose,
      commit.toUnsignedMap(),
      commit.signature ?? '',
      ownerKey,
      identityStore: _identityStore,
    );
    if (_roomGeneration != generation) return;
    if (!verified) {
      // Unsigned or forged commits are never applied.
      _flagProtocolViolation();
      return;
    }
    final cls = _chain.classify(commit);
    switch (cls) {
      case CommitClass.duplicate:
        _completePendingForCommit(commit);
        return;
      case CommitClass.chainRejected:
        _requestResync();
        return;
      case CommitClass.outOfOrder:
        _chain.park(commit);
        _scheduleParkedSweep();
        return;
      case CommitClass.ready:
        break;
    }
    await _applyCommitSideEffectsGuarded(commit);
    if (_roomGeneration != generation) return;
    _chain.markApplied(commit);
    while (true) {
      final ready = _chain.drainReady();
      if (ready.isEmpty) break;
      for (final c in ready) {
        await _applyCommitSideEffectsGuarded(c);
        if (_roomGeneration != generation) return;
      }
    }
    _completePendingForCommit(commit);
    notifyListeners();
  }

  Future<void> _enqueueCommitApply(Future<void> Function() task) {
    final generation = _roomGeneration;
    final done = Completer<void>();
    _commitApplyQueue = _commitApplyQueue.then((_) async {
      if (_roomGeneration == generation) await task();
    }).catchError((_) {
      // A failing apply must not wedge the queue for everyone behind it.
      if (_roomGeneration == generation) _lastErrorCode ??= 'commit_rejected';
    });
    _commitApplyQueue.whenComplete(() {
      if (!done.isCompleted) done.complete();
    });
    // Publishing the next sequence must wait for this commit to be applied.
    return done.future;
  }

  /// Side-effect application is best-effort per commit: the chain must
  /// still advance to keep the room consistent for every participant, so a
  /// failing side effect surfaces as a stable error code instead of
  /// crashing the message handler or silently dropping the commit.
  Future<void> _applyCommitSideEffectsGuarded(RoomCommit commit) async {
    final generation = _roomGeneration;
    try {
      await _applyCommitSideEffects(commit);
    } catch (_) {
      if (_roomGeneration == generation) _lastErrorCode = 'commit_rejected';
    }
  }

  void _completePendingForCommit(RoomCommit commit) {
    final requestId = commit.requestId;
    if (requestId == null) return;
    _requestToCommitSeq[requestId] = commit.seq;
    final completer = _pendingRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<RoomCommit?> _publishCommit({
    required String requestId,
    required String action,
    required Map<String, Object?> params,
    String? actorDeviceId,
  }) {
    final generation = _roomGeneration;
    final previous = _publishQueue;
    final task = previous.then<RoomCommit?>((_) async {
      if (_roomGeneration != generation) return null;
      return _publishCommitNow(
        requestId: requestId,
        action: action,
        params: params,
        actorDeviceId: actorDeviceId,
      );
    });
    _publishQueue = task.then((_) {}, onError: (_) {});
    return task;
  }

  Future<RoomCommit?> _publishCommitNow({
    required String requestId,
    required String action,
    required Map<String, Object?> params,
    String? actorDeviceId,
  }) async {
    final generation = _roomGeneration;
    try {
      if (role != RoomRole.owner || _keyPair == null) {
        return null;
      }
      if (actorDeviceId != null && actorDeviceId != _selfId) {
        // Authorization is re-checked at transaction execution time, not
        // at request arrival time: an ACL revocation committed earlier in
        // this same queue wins over a stale permission snapshot.
        final isOwnerOnly = kOwnerOnlyActions.contains(action);
        if (isOwnerOnly || !_acl.canControl(actorDeviceId)) {
          _lastErrorCode = 'permission_denied';
          notifyListeners();
          return null;
        }
      }
      final error = _validateActionParams(action, params);
      if (error != null) {
        _lastErrorCode = error;
        notifyListeners();
        return null;
      }
      if (action == 'add_local') {
        // When the manifest body is omitted it travels via the bounded chunked
        // transfer; the receiver verifies it against the inline signature once
        // it lands. Only inline manifests are verifiable here.
        if (params['manifest'] is Map) {
          final verified = await _verifyAddLocalManifest(params);
          if (_roomGeneration != generation) return null;
          if (!verified) {
            _lastErrorCode = 'permission_denied';
            notifyListeners();
            return null;
          }
        }
      }
      final unsigned = <String, Object?>{
      'seq': _chain.lastSeq + 1,
      'prevHash': _chain.lastHash,
      'requestId': requestId,
      'aclVersion': _acl.version,
      'action': action,
      'params': params,
      'effectiveSharedMs': _sharedNowMs,
      'roomId': _roomId,
      'sessionId': _sessionId,
    };
    final draft = RoomCommit(
      seq: unsigned['seq']! as int,
      prevHash: unsigned['prevHash']! as String,
      requestId: requestId,
      aclVersion: _acl.version,
      action: action,
      params: params,
      effectiveSharedMs: unsigned['effectiveSharedMs']! as int,
      roomId: _roomId!,
      sessionId: _sessionId!,
    );
    final signature = await signDomain(
      CommitChain.signaturePurpose,
      draft.toUnsignedMap(),
      _keyPair!,
      identityStore: _identityStore,
    );
    if (_roomGeneration != generation) return null;
    final signed = RoomCommit(
      seq: draft.seq,
      prevHash: draft.prevHash,
      requestId: draft.requestId,
      aclVersion: draft.aclVersion,
      action: draft.action,
      params: draft.params,
      effectiveSharedMs: draft.effectiveSharedMs,
      roomId: draft.roomId,
      sessionId: draft.sessionId,
      signature: signature,
    );
      if (_dcStateOpen() == true) {
        await _sendDc(signed.toWireMap());
      }
      if (_roomGeneration != generation) return null;
      await _handleCommitWire(Map<String, Object?>.from(signed.toWireMap()));
      return signed;
    } catch (_) {
      if (_roomGeneration != generation) return null;
      _lastErrorCode = 'commit_rejected';
      notifyListeners();
      return null;
    }
  }

  /// Validates parameters for [action]; returns a stable error code or null.
  String? _validateActionParams(String action, Map<String, Object?> params) {
    int? reqPos(Map<String, Object?> p, String key) {
      final v = p[key];
      if (v is! int || v < 0) return null;
      return v;
    }

    int? optRateMilli(Map<String, Object?> p) {
      final v = p['rateMilli'];
      if (v == null) return 1000;
      if (v is! int || v < 100 || v > 8000) return null;
      return v;
    }

    String? optItemId(Map<String, Object?> p) {
      final v = p['itemId'];
      if (v == null) return '';
      if (v is! String || v.isEmpty || v.length > 64) return null;
      return v;
    }

    switch (action) {
      case 'play':
      case 'pause':
        if (reqPos(params, 'positionMs') == null) return 'commit_rejected';
        if (optRateMilli(params) == null) return 'commit_rejected';
        if (params['itemId'] is! String || (params['itemId'] as String).isEmpty) {
          return 'commit_rejected';
        }
        return null;
      case 'seek':
        if (reqPos(params, 'positionMs') == null) return 'commit_rejected';
        return null;
      case 'rate':
        if (optRateMilli(params) == null) return 'commit_rejected';
        return null;
      case 'add_url':
        if (_playlist.length >= kMaxPlaylistItems) return 'commit_rejected';
        final item = params['item'];
        if (item is! Map) return 'commit_rejected';
        try {
          final parsed =
              PlaylistItem.fromMap(item.cast<String, Object?>());
          if (!_isAllowedMediaUrl(parsed.url ?? '')) {
            return 'unsupported_media';
          }
        } catch (_) {
          return 'commit_rejected';
        }
        return null;
      case 'remove':
        if (optItemId(params) == null || optItemId(params)!.isEmpty) {
          return 'commit_rejected';
        }
        return null;
      case 'reorder':
        if (optItemId(params) == null || optItemId(params)!.isEmpty) {
          return 'commit_rejected';
        }
        final index = params['newIndex'];
        if (index is! int || index < 0 || index > 10000) {
          return 'commit_rejected';
        }
        return null;
      case 'replace':
        if (optItemId(params) == null || optItemId(params)!.isEmpty) {
          return 'commit_rejected';
        }
        final url = params['url'];
        if (url != null && (url is! String || !_isAllowedMediaUrl(url))) {
          return 'unsupported_media';
        }
        return null;
      case 'switch_item':
        if (optItemId(params) == null || optItemId(params)!.isEmpty) {
          return 'commit_rejected';
        }
        if (reqPos(params, 'positionMs') == null) return 'commit_rejected';
        final mode = params['mode'];
        if (mode != 'playing' && mode != 'paused') return 'commit_rejected';
        return null;
      case 'add_local':
        if (_playlist.length >= kMaxPlaylistItems) return 'commit_rejected';
        final itemRaw = params['item'];
        if (itemRaw is! Map) return 'commit_rejected';
        final PlaylistItem parsed;
        try {
          parsed = PlaylistItem.fromMap(itemRaw.cast<String, Object?>());
        } catch (_) {
          return 'commit_rejected';
        }
        if (parsed.sourceType != 'local') return 'commit_rejected';
        final mediaId = parsed.localMediaId;
        if (mediaId == null || !isHex64(mediaId)) return 'commit_rejected';
        final source = params['manifestSource'];
        if (source is! String || !isHex64(source)) return 'commit_rejected';
        if (!_acl.isAdmitted(source)) return 'permission_denied';
        final sig = params['manifestSignature'];
        if (sig is! String || sig.isEmpty || sig.length > 128) {
          return 'commit_rejected';
        }
        // The manifest body may be omitted when it exceeds
        // [kMaxInlineManifestBytes]; it then arrives over the bounded chunked
        // `media_manifest_chunk` protocol and is verified against [sig] on
        // receipt. When present inline, validate the mediaId/source binding.
        final manifestRaw = params['manifest'];
        if (manifestRaw is Map) {
          MediaManifest manifest;
          try {
            manifest =
                MediaManifest.fromJson(manifestRaw.cast<String, dynamic>());
          } catch (_) {
            return 'commit_rejected';
          }
          if (manifest.mediaId != mediaId) return 'commit_rejected';
          if (manifest.sourceDeviceId != source) return 'commit_rejected';
        }
        return null;
      case 'ended_stop':
        if (params.containsKey('positionMs') && reqPos(params, 'positionMs') == null) {
          return 'commit_rejected';
        }
        return null;
      case 'member_admit':
      case 'grant_admin':
      case 'revoke_admin':
        final memberId = params['memberId'];
        if (memberId is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(memberId)) {
          return 'commit_rejected';
        }
        return null;
      case 'room_close':
        return null;
      default:
        return 'commit_rejected';
    }
  }

  /// Verifies the source signature over [manifestJson] in [params]
  /// (purpose domain separation `media_manifest`). The signer must match
  /// `manifestSource`, and the mediaId binding is re-checked by
  /// MediaManifest.fromJson. Fails closed on any error.
  Future<bool> _verifyAddLocalManifest(Map<String, Object?> params) async {
    final source = params['manifestSource'];
    final signature = params['manifestSignature'];
    final manifestRaw = params['manifest'];
    if (source is! String || signature is! String || manifestRaw is! Map) {
      return false;
    }
    final manifestMap = manifestRaw.cast<String, dynamic>();
    try {
      final manifest = MediaManifest.fromJson(manifestMap);
      if (manifest.sourceDeviceId != source) return false;
      final committed = _knownLocalMediaSources[manifest.mediaId];
      if (committed != null && committed != source) return false;
      final key = source == _selfId
          ? _keyPair!.identity.publicKeyBase64
          : (source == _peerDeviceId ? _peerPublicKey : null);
      if (key == null) return false;
      return verifyDomain(
        'media_manifest',
        manifestMap,
        signature,
        key,
        identityStore: _identityStore,
      );
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------- apply commits

  Future<void> _applyCommitSideEffects(RoomCommit commit) async {
    final generation = _roomGeneration;
    bool stillCurrent() => _roomGeneration == generation &&
        _sessionId == commit.sessionId && _roomId == commit.roomId;
    if (!stillCurrent()) return;
    final params = commit.params;
    final sharedMs = commit.effectiveSharedMs;
    final anchor = sharedMs;

    switch (commit.action) {
      case 'play':
      case 'pause':
        final mode =
            commit.action == 'play' ? PlaybackMode.playing : PlaybackMode.paused;
        final itemId = (params['itemId'] as String?) ?? _currentItemId;
        final positionMs = params['positionMs'] as int? ?? 0;
        final rateMilli = params['rateMilli'] as int? ?? 1000;
        _playback = PlaybackState(
          itemId: itemId,
          mode: mode,
          position: Duration(milliseconds: positionMs),
          rate: rateMilli / 1000.0,
          effectiveAt: DateTime.now(),
          seq: commit.seq,
          anchorSharedMs: anchor,
          rateMilli: rateMilli,
        );
        _currentItemId = itemId;
        if (itemId != null) {
          await _ensureMediaLoaded(itemId, seekTo: Duration(milliseconds: positionMs));
        }
        if (!stillCurrent()) return;
        await _applyPlayerForCommit(mode, rateMilli);
        break;
      case 'seek':
        final positionMs = params['positionMs'] as int? ?? 0;
        final rateMilli = _playback.rateMilli;
        _playback = PlaybackState(
          itemId: _playback.itemId,
          mode: _playback.mode,
          position: Duration(milliseconds: positionMs),
          rate: rateMilli / 1000.0,
          effectiveAt: DateTime.now(),
          seq: commit.seq,
          anchorSharedMs: anchor,
          rateMilli: rateMilli,
        );
        if (_player != null) {
          if (_player!.state.completed && _currentItemId != null) {
            await _player!.seek(Duration(milliseconds: positionMs));
            if (!stillCurrent()) return;
            await _applyPlayerForCommit(_playback.mode, rateMilli);
          } else {
            await _player!.seek(Duration(milliseconds: positionMs));
          }
        }
        break;
      case 'rate':
        final rateMilli = params['rateMilli'] as int? ?? 1000;
        _playback = PlaybackState(
          itemId: _playback.itemId,
          mode: _playback.mode,
          position: _expectedPositionNow(),
          rate: rateMilli / 1000.0,
          effectiveAt: DateTime.now(),
          seq: commit.seq,
          anchorSharedMs: anchor,
          rateMilli: rateMilli,
        );
        await _player?.setRate(rateMilli / 1000.0);
        break;
      case 'add_local':
        final item = PlaylistItem.fromMap(
          (params['item'] as Map).cast<String, Object?>(),
        );
        if (item.localMediaId != null) {
          _knownLocalMediaIds.add(item.localMediaId!);
        }
        final source = params['manifestSource'] as String?;
        if (item.localMediaId != null && source != null) {
          _knownLocalMediaSources[item.localMediaId!] = source;
        }
        final manifestRaw = params['manifest'];
        if (source != null && manifestRaw is Map && source != _selfId) {
          final trusted = await _verifyAddLocalManifest(params);
          if (!stillCurrent()) return;
          if (trusted) {
            try {
              final svc = await _ensureMediaService();
              if (!stillCurrent()) return;
              await svc.registerRemoteManifest(
                manifestRaw.cast<String, dynamic>(),
                trustedByCore: true,
              );
              if (!stillCurrent()) return;
            } catch (_) {
              if (!stillCurrent()) return;
              _lastErrorCode = 'unsupported_media';
            }
          } else {
            _lastErrorCode = 'permission_denied';
          }
        }
        if (_playlist.any((e) => e.itemId == item.itemId)) break;
        _playlist.add(item);
        // A remote source may omit the inline manifest body (large manifest →
        // bounded chunked transfer). Pull it now; _requestMissingManifests
        // starts the media service on demand and skips items it already has.
        if (source != null && source != _selfId && item.localMediaId != null) {
          unawaited(_requestMissingManifests());
        }
        break;
      case 'add_url':
        final item = PlaylistItem.fromMap(
          (params['item'] as Map).cast<String, Object?>(),
        );
        if (_playlist.any((e) => e.itemId == item.itemId)) break;
        _playlist.add(item);
        break;
      case 'remove':
        final itemId = params['itemId'] as String;
        final wasCurrent = _currentItemId == itemId;
        final removedIndex = _playlist.indexWhere((e) => e.itemId == itemId);
        _playlist.removeWhere((e) => e.itemId == itemId);
        if (wasCurrent) {
          if (_playlist.isNotEmpty) {
            // V1-PRD §6: deleting the current item selects its former NEXT,
            // pauses it (awaiting a play command) and keeps it loaded; only an
            // now-empty list stops playback fully and clears the current item.
            final nextIndex = removedIndex.clamp(0, _playlist.length - 1);
            final next = _playlist[nextIndex];
            _currentItemId = next.itemId;
            _loadedItemId = null;
            _playback = PlaybackState(
              itemId: next.itemId,
              mode: PlaybackMode.paused,
              position: Duration.zero,
              rate: _playback.rate,
              effectiveAt: DateTime.now(),
              seq: commit.seq,
              anchorSharedMs: anchor,
              rateMilli: _playback.rateMilli,
            );
            await _ensureMediaLoaded(next.itemId, seekTo: Duration.zero);
            if (!stillCurrent()) return;
            await _player?.pause();
          } else {
            _currentItemId = null;
            _loadedItemId = null;
            _playback = PlaybackState(
              itemId: null,
              mode: PlaybackMode.paused,
              seq: commit.seq,
              effectiveAt: DateTime.now(),
              anchorSharedMs: anchor,
              rateMilli: _playback.rateMilli,
            );
            unawaited(_player?.pause() ?? Future<void>.value());
          }
        }
        break;
      case 'reorder':
        final itemId = params['itemId'] as String;
        final newIndex = params['newIndex'] as int;
        final idx = _playlist.indexWhere((e) => e.itemId == itemId);
        if (idx >= 0) {
          final item = _playlist.removeAt(idx);
          _playlist.insert(newIndex.clamp(0, _playlist.length), item);
        }
        break;
      case 'replace':
        final itemId = params['itemId'] as String;
        final idx = _playlist.indexWhere((e) => e.itemId == itemId);
        if (idx >= 0) {
          final old = _playlist[idx];
          final isCurrent = _currentItemId == itemId;
          _playlist[idx] = PlaylistItem(
            itemId: old.itemId,
            title: (params['title'] as String?) ?? old.title,
            sourceType: params['url'] != null ? 'url' : old.sourceType,
            url: (params['url'] as String?) ?? old.url,
            localMediaId: (params['localMediaId'] as String?) ?? old.localMediaId,
            duration: old.duration,
            sizeBytes: old.sizeBytes,
          );
          if (isCurrent) {
            _loadedItemId = null;
            _playback = PlaybackState(
              itemId: itemId,
              mode: PlaybackMode.paused,
              position: Duration.zero,
              rate: _playback.rate,
              seq: commit.seq,
              anchorSharedMs: anchor,
              rateMilli: _playback.rateMilli,
            );
            await _ensureMediaLoaded(itemId, seekTo: Duration.zero);
            if (!stillCurrent()) return;
            await _player?.pause();
          }
        }
        break;
      case 'switch_item':
        final itemId = params['itemId'] as String;
        final modeName = params['mode'] as String? ?? 'paused';
        final mode = modeName == 'playing'
            ? PlaybackMode.playing
            : PlaybackMode.paused;
        _currentItemId = itemId;
        _playback = PlaybackState(
          itemId: itemId,
          mode: mode,
          position: Duration.zero,
          rate: _playback.rate,
          seq: commit.seq,
          anchorSharedMs: anchor,
          rateMilli: _playback.rateMilli,
        );
        await _ensureMediaLoaded(itemId, seekTo: Duration.zero);
        if (!stillCurrent()) return;
        await _applyPlayerForCommit(mode, _playback.rateMilli);
        break;
      case 'ended_stop':
        _playback = PlaybackState(
          itemId: _playback.itemId,
          mode: PlaybackMode.paused,
          position: Duration(milliseconds: params['positionMs'] as int? ??
              _playback.position.inMilliseconds),
          rate: _playback.rate,
          seq: commit.seq,
          anchorSharedMs: anchor,
          rateMilli: _playback.rateMilli,
        );
        await _player?.pause();
        break;
      case 'member_admit':
      case 'grant_admin':
      case 'revoke_admin':
        _acl.applyCommit(commit.action, params);
        _refreshMemberRoles();
        break;
      case 'room_close':
        _handleIncomingClose();
        break;
      default:
        _flagProtocolViolation();
        return;
    }
  }

  Future<void> _applyPlayerForCommit(PlaybackMode mode, int rateMilli) async {
    final player = _player;
    if (player == null) return;
    final generation = _roomGeneration;
    final itemId = _currentItemId;
    bool stillCurrent() => !_closing && identical(_player, player) &&
        _roomGeneration == generation && _currentItemId == itemId;
    if (mode == PlaybackMode.playing) {
      if (itemId == null || _loadedItemId != itemId) return;
      if (kIsWeb) {
        try {
          await _waitForWebVideoSurface(player);
        } catch (_) {
          if (!stillCurrent()) return;
          _lastErrorCode ??= 'media_probe_failed';
          notifyListeners();
          return;
        }
      }
      if (!stillCurrent()) return;
      await player.setRate(rateMilli / 1000.0);
      if (stillCurrent()) await player.play();
    } else {
      await player.pause();
    }
  }

  Future<void> _waitForWebVideoSurface(Player player) async {
    final ready = Completer<void>();
    void check() {
      if (!ready.isCompleted &&
          (player.state.width ?? 0) > 0 &&
          (player.state.height ?? 0) > 0) {
        ready.complete();
      }
    }

    final width = player.stream.width.listen((_) => check());
    final height = player.stream.height.listen((_) => check());
    try {
      check();
      await ready.future.timeout(requestTimeout);
      // media_kit_video unmounts its HtmlElementView while dimensions are
      // null. Let its metadata-driven rebuild finish before pending play().
      await SchedulerBinding.instance.endOfFrame.timeout(requestTimeout);
      await waitForVideoSurface(requestTimeout);
    } finally {
      await width.cancel();
      await height.cancel();
    }
  }

  Duration _expectedPositionNow() {
    if (role != RoomRole.owner && !_clock.hasEstimate) return _playback.position;
    return _playback.expectedPositionAt(_sharedNowMs);
  }

  Future<void> _ensureMediaLoaded(String itemId, {required Duration seekTo}) async {
    final generation = _roomGeneration;
    final player = _player;
    bool stillCurrent() => _roomGeneration == generation &&
        identical(_player, player) && _currentItemId == itemId;
    final item = _itemById(itemId);
    if (item == null) {
      _lastErrorCode = 'source_offline';
      notifyListeners();
      return;
    }
    if (player == null || !stillCurrent()) return;
    // A seek clears media_kit's completed flag before native play can
    // restart the ended playlist entry. Reopen completed media instead.
    final restartingAtEnd = seekTo == Duration.zero &&
        player.state.duration > const Duration(milliseconds: 250) &&
        player.state.position >=
            player.state.duration - const Duration(milliseconds: 250);
    if (_loadedItemId == itemId && !player.state.completed && !restartingAtEnd &&
        _lastErrorCode != 'media_probe_failed' &&
        _lastErrorCode != 'source_offline') {
      final current = player.state.position;
      if ((current - seekTo).abs() > const Duration(seconds: 2)) {
        await player.seek(seekTo);
      }
      return;
    }
    if (_offlineMediaId != item.localMediaId || item.localMediaId == null) {
      _offlineMediaId = null;
      _lastErrorCode = null;
    }
    final media = await _mediaForItemAsync(item);
    if (!stillCurrent()) return;
    if (media == null) {
      _lastErrorCode = 'source_offline';
      notifyListeners();
      return;
    }
    try {
      // media_kit.open already resets the previous media under its lock.
      // Let media_kit apply the initial position when the file loads.
      await player.open(
        !kIsWeb && seekTo > Duration.zero ? media.copyWith(start: seekTo) : media,
        play: false,
      );
      if (!stillCurrent()) return;
      if (kIsWeb && seekTo > Duration.zero) {
        // Web Media.start clamps all later position updates to that bound.
        await _waitForWebVideoSurface(player);
        if (!stillCurrent()) return;
        await player.seek(seekTo);
        if (!stillCurrent()) return;
      }
      _loadedItemId = itemId;
      _errorItemId = itemId;
      // A successful load clears any prior async playback error so a resolved
      // item does not keep showing a stale failure.
      if (_lastErrorCode != 'source_offline') _lastErrorCode = null;
    } catch (_) {
      if (!stillCurrent()) return;
      // The Player no longer holds a usable entry after a failed open; clear
      // the loaded marker so a later switch re-opens instead of merely
      // seeking on an empty player.
      _loadedItemId = null;
      if (_lastErrorCode != 'source_offline') {
        _lastErrorCode = 'media_probe_failed';
      }
      notifyListeners();
    }
  }

  Future<Media?> _mediaForItemAsync(PlaylistItem item) async {
    if (item.sourceType == 'url' && item.url != null) {
      return Media(item.url!);
    }
    if (item.sourceType == 'local') {
      // 1. Direct path / URI reference: ONLY if this device actually possesses the file locally!
      final hasLocalPath = _localMediaPaths.containsKey(item.itemId) ||
          (item.localMediaId != null && _localMediaPaths.containsKey(item.localMediaId!));
      final source = item.localMediaId != null ? _knownLocalMediaSources[item.localMediaId!] : null;
      final isLocalSource = source != null && _keyPair != null && source == _keyPair!.identity.deviceId;

      if (hasLocalPath || isLocalSource) {
        final localRef = _localMediaPaths[item.itemId] ??
            (item.localMediaId != null ? _localMediaPaths[item.localMediaId!] : null) ??
            item.localPath;
        if (localRef != null && localRef.isNotEmpty) {
          return Media(localRef);
        }
      }

      // 2. Remote peer: NEVER open host's localPath directly! Stream via P2P local media service
      if (item.localMediaId != null) {
        final service = await _ensureMediaService();
        try {
          final uri = await service.openMediaUri(item.localMediaId!);
          return Media(uri);
        } catch (e) {
          return null;
        }
      }
    }
    return null;
  }

  PlaylistItem? _itemById(String itemId) {
    for (final item in _playlist) {
      if (item.itemId == itemId) return item;
    }
    return null;
  }

  void _refreshMemberRoles() {
    for (var i = 0; i < _members.length; i++) {
      final m = _members[i];
      _members[i] = m.copyWith(role: _roleFor(m.deviceId));
    }
  }

  RoomRole _roleFor(String deviceId) {
    switch (_acl.roleOf(deviceId)) {
      case 'owner':
        return RoomRole.owner;
      case 'admin':
        return RoomRole.admin;
      default:
        return RoomRole.member;
    }
  }

  void _upsertMember(String deviceId, {required bool online, int? joinedAt}) {
    final isMe = _selfId == deviceId ||
        (_keyPair != null && _keyPair!.identity.deviceId == deviceId);
    final localName = isMe ? AppSettings.instance.effectiveDisplayName : '';
    final localAvatar = isMe ? AppSettings.instance.avatar : '';
    final idx = _members.indexWhere((m) => m.deviceId == deviceId);
    if (idx >= 0) {
      _members[idx] = _members[idx].copyWith(
        online: online,
        role: _roleFor(deviceId),
        displayName: (isMe && localName.isNotEmpty) ? localName : null,
        avatar: (isMe && localAvatar.isNotEmpty) ? localAvatar : null,
        joinedAt: joinedAt,
      );
      return;
    }
    _members.add(RoomMember(
      deviceId: deviceId,
      displayName:
          (isMe && localName.isNotEmpty) ? localName : _shortId(deviceId),
      role: _roleFor(deviceId),
      online: online,
      avatar: localAvatar,
      joinedAt: joinedAt,
    ));
  }

  void _handleIncomingClose() {
    _teardownPeer();
    final keepError = _lastErrorCode;
    _resetRoomState(full: true);
    _connectionState = RoomConnectionState.disconnected;
    _lastErrorCode = keepError;
    unawaited(_player?.stop() ?? Future<void>.value());
  }

  void _onPlayerError(String message) {
    if (_closing || _player == null || _loadedItemId == null) return;
    // Avoid stale-media pollution: the player error stream carries no item id,
    // so once the loaded item has changed since this open the error belongs to
    // a previous item and must be dropped.
    if (_loadedItemId != _errorItemId) return;
    if (_lastErrorCode == 'source_offline') return;
    _lastErrorCode = 'media_probe_failed';
    notifyListeners();
  }

  void _onPlayerCompleted(bool completed) {
    if (!completed) return;
    if (role != RoomRole.owner || _currentItemId == null) return;
    if (_playback.mode != PlaybackMode.playing) return;

    if (_loopMode == PlaybackLoopMode.loopOne) {
      unawaited(_publishCommit(
        requestId: _uuid.v4(),
        action: 'switch_item',
        params: <String, Object?>{
          'itemId': _currentItemId,
          'positionMs': 0,
          'mode': 'playing',
        },
      ));
      return;
    }

    final currentIndex =
        _playlist.indexWhere((e) => e.itemId == _currentItemId);

    PlaylistItem? nextItem;
    if (currentIndex >= 0 && _playlist.isNotEmpty) {
      for (var offset = 1; offset < _playlist.length; offset++) {
        final targetIdx = (currentIndex + offset) % _playlist.length;
        if (_loopMode == PlaybackLoopMode.sequential &&
            currentIndex + offset >= _playlist.length) {
          break; // end reached in sequential mode
        }
        final candidate = _playlist[targetIdx];
        if (!isItemSourceOffline(candidate)) {
          nextItem = candidate;
          break;
        }
      }
    }

    if (nextItem != null) {
      unawaited(_publishCommit(
        requestId: _uuid.v4(),
        action: 'switch_item',
        params: <String, Object?>{
          'itemId': nextItem.itemId,
          'positionMs': 0,
          'mode': 'playing',
        },
      ));
    } else {
      unawaited(_publishCommit(
        requestId: _uuid.v4(),
        action: 'ended_stop',
        params: <String, Object?>{
          'positionMs': (_player!.state.duration > Duration.zero
                  ? _player!.state.duration
                  : _player!.state.position)
              .inMilliseconds,
        },
      ));
    }
  }

  Future<void> _correctDrift() async {
    if (!_peerVerified || _player == null || _playback.itemId == null) return;
    if (!_clock.hasEstimate || _loadedItemId != _currentItemId) return;
    if (_playback.mode != PlaybackMode.playing) {
      if (_microRateAdjusted) {
        _microRateAdjusted = false;
        await _player!.setRate(_playback.rate);
      }
      return;
    }
    // Guard against buffer thrashing: if the player is actively buffering
    // network chunks, do not interrupt it with hard seeks.
    if (_player!.state.buffering) return;

    final expected = _expectedPositionNow();
    final actual = _player!.state.position;
    final diffMs = expected.inMilliseconds - actual.inMilliseconds;

    // 1. Large drift (> 1500ms): perform a hard seek with cooldown.
    if (diffMs.abs() > 1500) {
      final nowMono = _clock.localMonoMs();
      if (nowMono - _lastSeekMonoMs >= 3000) {
        _lastSeekMonoMs = nowMono;
        await _player!.seek(expected);
      }
      if (_microRateAdjusted) {
        _microRateAdjusted = false;
        await _player!.setRate(_playback.rate);
      }
      return;
    }

    // 2. Tightly in-sync (within 50ms): restore standard rate if adjusted.
    if (diffMs.abs() <= 50) {
      if (_microRateAdjusted) {
        _microRateAdjusted = false;
        await _player!.setRate(_playback.rate);
      }
      return;
    }

    // 3. Smooth micro-rate drift correction (150ms ~ 1500ms):
    // If lagging behind: speed up slightly (+4%).
    // If running ahead: slow down slightly (-4%).
    if (diffMs > 150) {
      _microRateAdjusted = true;
      await _player!.setRate((_playback.rate * 1.04).clamp(0.1, 8.0));
    } else if (diffMs < -150) {
      _microRateAdjusted = true;
      await _player!.setRate((_playback.rate * 0.96).clamp(0.1, 8.0));
    }
  }

  // ------------------------------------------- member -> owner requests

  static const Set<String> kOwnerOnlyActions = <String>{
    'member_admit',
    'grant_admin',
    'revoke_admin',
    'room_close',
  };

  static const Set<String> kControllableActions = <String>{
    'play',
    'pause',
    'seek',
    'rate',
    'add_url',
    'add_local',
    'remove',
    'reorder',
    'replace',
    'switch_item',
    'ended_stop',
  };

  /// Returns the playlist itemId a list-modifying control action targets, or
  /// null when the action is not item-targeted (add*, playback controls). Used
  /// for targeted staleness detection: acting on a now-absent item means the
  /// requester's view is outdated (V1-PRD §6).
  String? _referencedItemId(String? action, Map<String, Object?> params) {
    switch (action) {
      case 'remove':
      case 'reorder':
      case 'replace':
      case 'switch_item':
        final id = params['itemId'];
        return id is String ? id : null;
      default:
        return null;
    }
  }

  Future<void> _handleControlRequest(Map<String, Object?> msg) async {
    if (role != RoomRole.owner || !_peerVerified) return;
    Map<String, Object?> request;
    try {
      request = parseRestrictedMap(msg, '\$control_request');
    } catch (_) {
      _flagProtocolViolation();
      return;
    }
    final senderId = request['senderId'] as String?;
    final action = request['action'] as String?;
    final requestId = request['requestId'] as String?;
    if (senderId == null ||
        action == null ||
        requestId == null ||
        senderId != _peerDeviceId) {
      return;
    }
    final baseSeq = request['baseSeq'];
    if (baseSeq is! int || baseSeq < 0) return;
    final paramsRaw = request['params'];
    if (paramsRaw is! Map) return;
    Map<String, Object?> params;
    try {
      params = parseRestrictedMap(paramsRaw, 'params');
    } catch (_) {
      await _sendRequestDenied(senderId, requestId, 'commit_rejected');
      return;
    }
    final ok = await verifyDomain(
      'control_request',
      {
        ...Map<String, Object?>.from(request)
          ..remove('signature')
          ..remove('type'),
      },
      request['signature'] as String? ?? '',
      _peerPublicKey!,
      identityStore: _identityStore,
    );
    if (!ok) {
      _flagProtocolViolation();
      return;
    }
    // Idempotent retry: a member re-sends a request we already committed.
    if (_chain.hasAppliedRequest(requestId)) {
      await _sendRequestResult(senderId, requestId, 'applied',
          _chain.seqForRequest(requestId) ?? 0);
      return;
    }
    // Stale member state (V1-PRD §6: stale list modifications are rejected and
    // refreshed; play/pause/seek execute on the latest confirmed state).
    //
    // We do NOT use a blanket `baseSeq < _chain.lastSeq` check: a member firing
    // several control requests from the same up-to-date view stamps each with the
    // SAME baseSeq, and the chain advances as each is applied. Rejecting the
    // later ones would drop legitimately-concurrent (non-stale) requests.
    //
    // Instead we detect a *genuine regression*: the peer has previously reported
    // a baseSeq at least as high as this one, yet now claims an older view
    // (replay of a superseded request, or acting on state it already advanced
    // past). Only that is rejected as `stale_state` and triggers a resync.
    if (baseSeq < _peerBaseSeqHigh) {
      unawaited(_sendSnapshot());
      await _sendRequestDenied(senderId, requestId, 'stale_state');
      return;
    }
    _peerBaseSeqHigh = baseSeq > _peerBaseSeqHigh ? baseSeq : _peerBaseSeqHigh;
    // Targeted list staleness: a list-modifying action that references an item
    // no longer present in the current playlist is operating on an outdated
    // view and must be rejected and refreshed.
    final referencedItem = _referencedItemId(action, params);
    if (referencedItem != null && !_playlist.any((e) => e.itemId == referencedItem)) {
      unawaited(_sendSnapshot());
      await _sendRequestDenied(senderId, requestId, 'stale_state');
      return;
    }
    if (kOwnerOnlyActions.contains(action)) {
      // Only the owner may drive these; a member asking is a violation.
      await _sendRequestDenied(senderId, requestId, 'permission_denied');
      return;
    }
    if (action == 'add_local' && params['manifestSource'] != senderId) {
      // A member may only add files it owns; the manifest signature must
      // prove that end to end.
      await _sendRequestDenied(senderId, requestId, 'permission_denied');
      return;
    }
    if (!kControllableActions.contains(action)) {
      await _sendRequestDenied(senderId, requestId, 'commit_rejected');
      return;
    }
    if (!_acl.canControl(senderId)) {
      // The member's ACL role at this moment governs, even if an ACL update
      // commit is in flight elsewhere; revocation is enforced here.
      await _sendRequestDenied(senderId, requestId, 'permission_denied');
      return;
    }
    final error = _validateActionParams(action, params);
    if (error != null) {
      await _sendRequestDenied(senderId, requestId, error);
      return;
    }
    final commit = await _publishCommit(
      requestId: requestId,
      action: action,
      params: params,
      actorDeviceId: senderId,
    );
    if (commit != null) {
      await _sendRequestResult(senderId, requestId, 'applied', commit.seq);
    } else {
      await _sendRequestDenied(senderId, requestId, 'permission_denied');
    }
  }

  Future<void> _sendRequestDenied(
    String targetDeviceId,
    String requestId,
    String code,
  ) async {
    if (!_peerVerified) return;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'requestId': requestId,
      'code': code,
    };
    final signature = await signDomain(
      'request_denied',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'request_denied', 'signature': signature}));
  }

  Future<void> _sendRequestResult(
    String targetDeviceId,
    String requestId,
    String status,
    int seq,
  ) async {
    if (!_peerVerified) return;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'requestId': requestId,
      'status': status,
      'seq': seq,
    };
    final signature = await signDomain(
      'request_result',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'request_result', 'signature': signature}));
  }

  Future<void> _handleRequestDenied(Map<String, Object?> msg) async {
    if (role == RoomRole.owner) return;
    final requestId = msg['requestId'] as String?;
    if (requestId == null) return;
    if (msg['senderId'] != _peerDeviceId) return;
    final ok = await _verifySignedMessage(msg, 'request_denied', _peerPublicKey!);
    if (!ok) {
      _flagProtocolViolation();
      return;
    }
    final completer = _pendingRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      final code = msg['code'] as String? ?? 'permission_denied';
      _lastErrorCode = code;
      notifyListeners();
      completer.complete();
    }
  }

  Future<void> _handleRequestResult(Map<String, Object?> msg) async {
    if (role == RoomRole.owner) return;
    final requestId = msg['requestId'] as String?;
    if (requestId == null) return;
    if (msg['senderId'] != _peerDeviceId) return;
    final ok = await _verifySignedMessage(msg, 'request_result', _peerPublicKey!);
    if (!ok) {
      _flagProtocolViolation();
      return;
    }
    final completer = _pendingRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// Sends a control request to the owner and waits for the commit to be
  /// applied locally. Completes on error paths too; check [lastErrorCode].
  Future<void> _requestControl(
    String action,
    Map<String, Object?> params,
  ) async {
    if (role == RoomRole.owner) {
      await _publishCommit(requestId: _uuid.v4(), action: action, params: params);
      return;
    }
    if (!_acl.canControl(_selfId ?? '')) {
      _lastErrorCode = 'permission_denied';
      notifyListeners();
      return;
    }
    if (!_peerVerified) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    final requestId = _uuid.v4();
    final completer = Completer<void>();
    _pendingRequests[requestId] = completer;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'requestId': requestId,
      'action': action,
      'params': params,
      'baseSeq': _chain.lastSeq,
      'aclVersion': _acl.version,
    };
    final signature = await signDomain(
      'control_request',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    final sent = await _sendDc(<String, Object?>{...payload, 'type': 'control_request', 'signature': signature});
    if (!sent) {
      _pendingRequests.remove(requestId);
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    try {
      await completer.future.timeout(requestTimeout);
    } on TimeoutException {
      _lastErrorCode = 'commit_rejected';
      _pendingRequests.remove(requestId);
      notifyListeners();
    }
  }

  // ------------------------------------------------------- snapshot

  Future<void> _handleResyncRequest(Map<String, Object?> msg) async {
    if (role != RoomRole.owner) return;
    final senderId = msg['senderId'] as String?;
    if (senderId != _peerDeviceId) return;
    Map<String, Object?> request;
    try {
      request = parseRestrictedMap(msg, '\$resync_request');
    } catch (_) {
      return;
    }
    final ok = await verifyDomain(
      'resync_request',
      {
        ...Map<String, Object?>.from(request)
          ..remove('signature')
          ..remove('type'),
      },
      request['signature'] as String? ?? '',
      _peerPublicKey!,
      identityStore: _identityStore,
    );
    if (!ok) return;
    await _sendSnapshot();
  }

  Future<void> _sendSnapshot() async {
    final playlist = _playlist.map((item) {
      final m = item.toMap();
      // Inline the manifest for small local media so the snapshot consumer
      // needs no extra round trip. Larger manifests are fetched lazily
      // through the chunked manifest protocol.
      if (item.sourceType == 'local' && item.localMediaId != null) {
        // The snapshot consumer binds each local item to its source device
        // from this field (covered by the snapshot signature) before it
        // will authorize the inline manifest or the chunked manifest
        // pull. Without it a guest joining after the item was added can
        // never install the manifest and the item stays source-offline.
        final manifestSource = _knownLocalMediaSources[item.localMediaId!];
        if (manifestSource != null) m['manifestSource'] = manifestSource;
        final manifest = _media?.manifestFor(item.localMediaId!);
        if (manifest != null) {
          final manifestJson = manifest.toJson();
          final signature = _manifestSignatures[manifest.mediaId];
          if (signature != null && jsonEncode(manifestJson).length <= 16000) {
            m['manifest'] = manifestJson;
            m['manifestSignature'] = signature;
          }
        }
      }
      return m;
    }).toList();
    final members = _members
        .map((m) => <String, Object?>{
              'deviceId': m.deviceId,
              'role': _roleName(m.role),
              'displayName': m.displayName,
              'online': m.online,
            })
        .toList();
    final pb = _playback;
    final payload = <String, Object?>{
      'protocolVersion': kProtocolVersion,
      'roomId': _roomId,
      'sessionId': _sessionId,
      'senderId': _selfId,
      'snapshotSeq': _chain.lastSeq,
      'prevHash': _chain.lastHash,
      'aclVersion': _acl.version,
      'acl': _acl.snapshot(),
      'members': members,
      'playlist': playlist,
      'currentItemId': _currentItemId,
      'playback': <String, Object?>{
        'itemId': pb.itemId,
        'mode': pb.mode == PlaybackMode.playing ? 'playing' : 'paused',
        'positionMs': pb.position.inMilliseconds,
        'rateMilli': pb.rateMilli,
        'anchorSharedMs': pb.anchorSharedMs,
        'seq': pb.seq,
      },
      'inviteEpoch': _inviteEpoch,
    };
    final signature = await signDomain(
      'room_snapshot',
      payload,
      _keyPair!,
      identityStore: _identityStore,
    );
    unawaited(_sendDc(<String, Object?>{...payload, 'type': 'snapshot', 'signature': signature}));
  }

  String _roleName(RoomRole role) {
    switch (role) {
      case RoomRole.owner:
        return 'owner';
      case RoomRole.admin:
        return 'admin';
      case RoomRole.member:
        return 'member';
    }
  }

  Future<void> _handleSnapshot(Map<String, Object?> msg) {
    return _enqueueCommitApply(() => _applySnapshot(msg));
  }

  Future<void> _applySnapshot(Map<String, Object?> msg) async {
    final generation = _roomGeneration;
    if (role == RoomRole.owner) return; // owner never consumes snapshots
    Map<String, Object?> snapshot;
    try {
      snapshot = parseRestrictedMap(msg, '\$snapshot');
    } catch (_) {
      _flagProtocolViolation();
      return;
    }
    if (snapshot['senderId'] != _peerDeviceId) {
      _flagProtocolViolation();
      return;
    }
    final ok = await verifyDomain(
      'room_snapshot',
      {
        ...Map<String, Object?>.from(snapshot)
          ..remove('signature')
          ..remove('type'),
      },
      snapshot['signature'] as String? ?? '',
      _peerPublicKey!,
      identityStore: _identityStore,
    );
    if (_roomGeneration != generation) return;
    if (!ok) {
      _flagProtocolViolation();
      return;
    }
    final seq = snapshot['snapshotSeq'];
    final prevHash = snapshot['prevHash'];
    final aclVersion = snapshot['aclVersion'];
    if (seq is! int || prevHash is! String || aclVersion is! int) return;
    if (seq < _chain.lastSeq) {
      return; // stale snapshot; keep our newer state
    }
    final aclRaw = snapshot['acl'];
    final roles = <String, String>{};
    if (aclRaw is Map) {
      aclRaw.forEach((k, v) {
        if (k is String && v is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(k)) {
          roles[k] = v;
        }
      });
    }
    _acl.loadSnapshot(roles, aclVersion);
    _chain.resetTo(seq, prevHash);

    final playlistRaw = snapshot['playlist'];
    _playlist.clear();
    if (playlistRaw is List) {
      for (final entry in playlistRaw) {
        if (entry is Map) {
          try {
            _playlist.add(
              PlaylistItem.fromMap(entry.cast<String, Object?>()),
            );
          } catch (_) {
            // Skip malformed items; the rest still forms a valid playlist.
          }
        }
      }
    }
    final membersRaw = snapshot['members'];
    _members.clear();
    if (membersRaw is List) {
      for (final entry in membersRaw) {
        if (entry is Map) {
          final id = entry['deviceId'];
          final role = _parseRole(entry['role']);
          if (id is String && kDeviceIdPattern.hasMatch(id)) {
            final isMe = id == _selfId;
            final localName = isMe ? AppSettings.instance.effectiveDisplayName : '';
            final localAvatar = isMe ? AppSettings.instance.avatar : '';
            _members.add(RoomMember(
              deviceId: id,
              displayName:
                  (isMe && localName.isNotEmpty) ? localName : _shortId(id),
              role: role,
              online: entry['online'] == true,
              avatar: localAvatar,
            ));
          }
        }
      }
    }
    if (!_members.any((m) => m.deviceId == _selfId) && _selfId != null) {
      final localName = AppSettings.instance.effectiveDisplayName;
      _members.add(RoomMember(
        deviceId: _selfId!,
        displayName:
            localName.isNotEmpty ? localName : _shortId(_selfId!),
        role: RoomRole.member,
        avatar: AppSettings.instance.avatar,
      ));
    }
    _refreshMemberRoles();

    final playbackRaw = snapshot['playback'];
    String? currentItemId = snapshot['currentItemId'] as String?;
    if (playbackRaw is Map) {
      final itemId = playbackRaw['itemId'] as String?;
      final mode = playbackRaw['mode'] == 'playing'
          ? PlaybackMode.playing
          : PlaybackMode.paused;
      final positionMs = (playbackRaw['positionMs'] as int?) ?? 0;
      final rateMilli = (playbackRaw['rateMilli'] as int?) ?? 1000;
      final anchor = (playbackRaw['anchorSharedMs'] as int?) ?? _sharedNowMs;
      final pseq = (playbackRaw['seq'] as int?) ?? seq;
      _playback = PlaybackState(
        itemId: itemId,
        mode: mode,
        position: Duration(milliseconds: positionMs),
        rate: rateMilli / 1000.0,
        seq: pseq,
        anchorSharedMs: anchor,
        rateMilli: rateMilli,
      );
      currentItemId = itemId;
    }
    _currentItemId = currentItemId;
    await _installInlineManifests(snapshot);
    if (_roomGeneration != generation) return;
    unawaited(_requestMissingManifests());
    if (currentItemId != null) {
      await _ensureMediaLoaded(
        currentItemId,
        seekTo: _expectedPositionNow(),
      );
      if (_roomGeneration != generation) return;
      await _applyPlayerForCommit(_playback.mode, _playback.rateMilli);
    }
    notifyListeners();
  }

  RoomRole _parseRole(Object? value) {
    switch (value) {
      case 'owner':
        return RoomRole.owner;
      case 'admin':
        return RoomRole.admin;
      default:
        return RoomRole.member;
    }
  }

  /// Installs manifests embedded inline in a snapshot (small files only).
  /// Verifies each against the item's declared manifestSource and the
  /// embedded source signature; untrusted or malformed entries are skipped.
  Future<void> _installInlineManifests(Map<String, Object?> snapshot) async {
    final generation = _roomGeneration;
    final playlistRaw = snapshot['playlist'];
    if (playlistRaw is! List) return;
    for (final entry in playlistRaw) {
      if (_roomGeneration != generation) return;
      if (entry is! Map) continue;
      final itemId = entry['localMediaId'];
      if (itemId is! String || !isHex64(itemId)) continue;
      final itemSource = entry['manifestSource'] as String?;
      if (itemSource != null && isHex64(itemSource)) {
        _knownLocalMediaIds.add(itemId);
        _knownLocalMediaSources[itemId] = itemSource;
      }
      final manifestRaw = entry['manifest'];
      final signature = entry['manifestSignature'] as String?;
      if (manifestRaw is! Map || signature == null || itemSource == null) {
        continue; // lazy path: fetched on demand via media_manifest_request
      }
      try {
        await _installRemoteManifest(
          manifestRaw.cast<String, dynamic>(),
          signature: signature,
          expectedSource: itemSource,
        );
      } catch (_) {}
    }
  }

  /// Installs a source-signed manifest. The signature must verify under
  /// the expected source device key (the peer identity verified at
  /// handshake). The mediaId binding is re-checked by MediaManifest.
  Future<void> _installRemoteManifest(
    Map<String, dynamic> manifestJson, {
    required String signature,
    required String expectedSource,
  }) async {
    final generation = _roomGeneration;
    final mediaId = manifestJson['mediaId'];
    if (mediaId is! String || !isHex64(mediaId)) {
      throw const FormatException('bad manifest mediaId');
    }
    if (manifestJson['sourceDeviceId'] != expectedSource) {
      throw const FormatException('manifest source mismatch');
    }
    // The source binding recorded from the signed commit/snapshot chain
    // wins; inline manifests cannot override it.
    final committed = _knownLocalMediaSources[mediaId];
    if (committed != null && committed != expectedSource) {
      throw const FormatException('manifest source conflicts with commit');
    }
    if (expectedSource == _selfId) {
      // Owner's own manifests are already registered at this device.
      _knownLocalMediaIds.add(mediaId);
      return;
    }
    if (expectedSource != _peerDeviceId || _peerPublicKey == null) {
      throw const FormatException('manifest source is not the peer');
    }
    final ok = await verifyDomain(
      'media_manifest',
      manifestJson,
      signature,
      _peerPublicKey!,
      identityStore: _identityStore,
    );
    if (_roomGeneration != generation) return;
    if (!ok) {
      throw const FormatException('manifest signature invalid');
    }
    final svc = await _ensureMediaService();
    if (_roomGeneration != generation) return;
    await svc.registerRemoteManifest(manifestJson, trustedByCore: true);
    if (_roomGeneration != generation) return;
    _knownLocalMediaIds.add(mediaId);
    _knownLocalMediaSources[mediaId] = expectedSource;
  }

  /// Sends a `media_manifest_request` for every local item whose manifest
  /// we have not registered yet. The source responds over the same
  /// channel with the chunked manifest protocol. The media service must be
  /// running to send these control frames, so it is started on demand here
  /// (it is otherwise only lazily started when media is first opened).
  Future<void> _requestMissingManifests() async {
    final generation = _roomGeneration;
    if (!_peerVerified) return;
    final svc = await _ensureMediaService();
    if (_roomGeneration != generation) return;
    for (final item in _playlist) {
      if (item.sourceType != 'local') continue;
      final mediaId = item.localMediaId;
      if (mediaId == null) continue;
      if (svc.manifestFor(mediaId) != null) continue;
      // Must travel as a room-scoped media control frame
      // (protocolVersion/roomId/sessionId/senderId are added by
      // _sendMediaControl); a bare _sendDc here fails isRoomScopedMessage
      // and the source never answers, leaving the chunked manifest unpulled.
      _sendMediaControl(<String, dynamic>{
        'type': 'media_manifest_request',
        'mediaId': mediaId,
      });
    }
  }

  // ------------------------------------------------------- public API

  Future<void> admitMember(String memberId) async {
    await _ownerOnlyAclAction('member_admit', memberId, 'member');
  }

  Future<void> grantAdmin(String memberId) async {
    await _ownerOnlyAclAction('grant_admin', memberId, null);
  }

  Future<void> revokeAdmin(String memberId) async {
    await _ownerOnlyAclAction('revoke_admin', memberId, null);
  }

  Future<void> _ownerOnlyAclAction(
    String action,
    String memberId,
    String? targetRole,
  ) async {
    if (role != RoomRole.owner) {
      _lastErrorCode = 'permission_denied';
      notifyListeners();
      return;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(memberId)) {
      _lastErrorCode = 'commit_rejected';
      notifyListeners();
      return;
    }
    final params = <String, Object?>{'memberId': memberId};
    if (targetRole != null) params['role'] = targetRole;
    await _publishCommit(requestId: _uuid.v4(), action: action, params: params);
  }

  Future<void> addUrl(String url, {String? title}) async {
    final cleanUrl = url.trim();
    if (!_isAllowedMediaUrl(cleanUrl)) {
      _lastErrorCode = 'unsupported_media';
      notifyListeners();
      return;
    }
    final probeError = _urlProbeOverride != null
        ? _urlProbeOverride(cleanUrl)
        : await probeMediaUrl(cleanUrl);
    if (probeError != null) {
      _lastErrorCode = probeError;
      notifyListeners();
      return;
    }
    final item = <String, Object?>{
      'itemId': _uuid.v4(),
      'title': (title == null || title.trim().isEmpty) ? cleanUrl : title.trim(),
      'sourceType': 'url',
      'url': cleanUrl,
    };
    await _requestControl('add_url', <String, Object?>{'item': item});
  }

  Future<void> pickAndAddLocalFile() async {
    try {
      String? path;
      String? name;
      int? size;
      XFile? file;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Native zero-copy SAF picker on Android: references original URI directly
        try {
          const channel = MethodChannel('com.norns.eir/media_picker');
          final res = await channel.invokeMethod<Map>('pickLocalVideo');
          if (res == null) return; // user cancelled
          path = res['path'] as String?;
          name = res['name'] as String?;
          size = (res['size'] as num?)?.toInt();
        } catch (e) {
          debugPrint('[RoomSession] Native SAF picker error: $e');
        }
      }

      if (path == null) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return; // user cancelled
        final picked = result.files.first;
        if (kIsWeb) {
          if (picked.bytes == null) return;
          file = XFile.fromData(picked.bytes!, name: picked.name);
          name = picked.name;
          size = picked.bytes!.length;
        } else {
          path = picked.path;
          name = picked.name;
          size = picked.size;
          if (path != null && path.isNotEmpty) {
            file = XFile(path, name: picked.name);
          }
        }
      }

      if (path == null && file == null) return;
      final effectiveTitle = name ?? (path != null ? path.split('/').last : 'video');
      await addDirectLocalMedia(
        path: path,
        file: file,
        title: effectiveTitle,
        sizeBytes: size,
      );
    } on MediaException catch (e) {
      _lastErrorCode = _mapMediaCode(e.code);
      notifyListeners();
    } catch (e, st) {
      debugPrint('[RoomSession] pickAndAddLocalFile error: $e\n$st');
      _lastErrorCode = 'media_unavailable';
      notifyListeners();
    }
  }

  /// Adds a direct local media reference to the playlist using a deterministic
  /// MediaManifest without copying whole files to temporary directories.
  Future<void> addDirectLocalMedia({
    String? path,
    XFile? file,
    required String title,
    int? sizeBytes,
  }) async {
    if (_keyPair == null) {
      _lastErrorCode = 'media_unavailable';
      notifyListeners();
      return;
    }

    final effectiveTitle = title.trim().isEmpty
        ? (file?.name ?? (path != null ? path.split('/').last : 'local_video'))
        : title.trim();

    final itemId = _uuid.v4();
    if (path != null && path.isNotEmpty) {
      _localMediaPaths[itemId] = path;
    }

    MediaManifest manifest;
    final svc = await _ensureMediaService();

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        path != null &&
        path.startsWith('content://')) {
      // Hardware-accelerated native manifest calculation with zero disk copying
      try {
        const channel = MethodChannel('com.norns.eir/media_picker');
        final resolvedMime = resolveMediaMime(
          magicMime: null,
          declaredMime: null,
          fileName: effectiveTitle,
        );
        final raw = await channel.invokeMethod<Map>('buildMediaManifest', {
          'uri': path,
          'title': effectiveTitle,
          'sourceDeviceId': _keyPair!.identity.deviceId,
          'mime': resolvedMime,
          'chunkSize': kMediaChunkSize,
        });
        if (raw == null) {
          throw MediaException('unsupported_media', 'native manifest failed');
        }
        final map = raw.cast<String, dynamic>();
        manifest = MediaManifest.fromJson(map);

        await svc.registerCustomSource(
          manifest: manifest,
          reader: (offset, length) async {
            final res = await channel.invokeMethod<Uint8List>('readContentChunk', {
              'uri': path,
              'offset': offset,
              'length': length,
            });
            return res ?? Uint8List(0);
          },
        );
      } catch (e, st) {
        debugPrint('[RoomSession] Native manifest calculation failed: $e\n$st');
        _lastErrorCode = 'unsupported_media';
        notifyListeners();
        return;
      }
    } else if (file != null) {
      manifest = await svc.registerFile(file, title: effectiveTitle);
    } else if (path != null && path.isNotEmpty && !kIsWeb) {
      manifest = await svc.registerFile(
        XFile(path, name: effectiveTitle),
        title: effectiveTitle,
      );
    } else {
      _lastErrorCode = 'unsupported_media';
      notifyListeners();
      return;
    }

    final realMediaId = manifest.mediaId;
    _localMediaPaths[realMediaId] = path ?? (file?.path ?? '');
    _localMediaPaths[itemId] = path ?? (file?.path ?? '');
    _knownLocalMediaIds.add(realMediaId);
    _knownLocalMediaSources[realMediaId] = _keyPair!.identity.deviceId;

    final signature = await signDomain(
      'media_manifest',
      manifest.toJson(),
      _keyPair!,
      identityStore: _identityStore,
    );
    _manifestSignatures[realMediaId] = signature;

    final item = <String, Object?>{
      'itemId': itemId,
      'title': effectiveTitle,
      'sourceType': 'local',
      'localMediaId': realMediaId,
      'localPath': path,
      'url': null,
      'sizeBytes': manifest.size,
      'manifestSource': _keyPair!.identity.deviceId,
    };

    final params = <String, Object?>{
      'item': item,
      'manifestSource': _keyPair!.identity.deviceId,
      'manifestSignature': signature,
      if (manifest.toJson().toString().length <= kMaxInlineManifestBytes)
        'manifest': manifest.toJson(),
    };

    if (_lastErrorCode != null) {
      _lastErrorCode = null;
      notifyListeners();
    }
    await _requestControl('add_local', params);
  }

  /// Registers [file] as shared P2P media: streams it chunk-by-chunk into
  /// the local media service (bounded memory), produces a signed SHA-256
  /// manifest bound to the source device, and submits an `add_local`
  /// commit (owner path publishes directly; members request the owner).
  Future<void> addLocalFile(XFile file, {String? title}) async {
    final effectiveTitle =
        (title == null || title.trim().isEmpty) ? file.name : title.trim();
    int? size;
    try {
      size = await file.length();
    } catch (_) {}
    await addDirectLocalMedia(
      path: file.path.isNotEmpty ? file.path : null,
      file: file,
      title: effectiveTitle,
      sizeBytes: size,
    );
  }

  static String _mapMediaCode(String code) {
    switch (code) {
      case 'unsupported_media':
        return 'unsupported_media';
      case 'source_offline':
        return 'source_offline';
      case 'chunk_hash_mismatch':
        return 'chunk_hash_mismatch';
      case 'storage_full':
        return 'storage_full';
      case 'untrusted_manifest':
      case 'invalid_manifest':
        return 'permission_denied';
      default:
        return 'unsupported_media';
    }
  }

  Future<void> removeItem(String itemId) async {
    await _requestControl('remove', <String, Object?>{'itemId': itemId});
  }

  Future<void> reorderItem(String itemId, int newIndex) async {
    await _requestControl('reorder',
        <String, Object?>{'itemId': itemId, 'newIndex': newIndex});
  }

  Future<void> replaceItem(String itemId, {String? url, XFile? file}) async {
    if (url != null && !_isAllowedMediaUrl(url.trim())) {
      _lastErrorCode = 'unsupported_media';
      notifyListeners();
      return;
    }
    final params = <String, Object?>{'itemId': itemId};
    if (url != null) params['url'] = url.trim();
    await _requestControl('replace', params);
  }

  Future<void> switchItem(String itemId) async {
    final target = _itemById(itemId);
    if (target == null) {
      _lastErrorCode = 'commit_rejected';
      notifyListeners();
      return;
    }
    final mode = _playback.mode == PlaybackMode.playing ? 'playing' : 'paused';
    await _requestControl('switch_item', <String, Object?>{
      'itemId': itemId,
      'positionMs': 0,
      'mode': mode,
    });
  }

  Future<void> play() async {
    final state = _player?.state;
    final atEnd = state != null &&
        (state.completed ||
            (state.duration > const Duration(milliseconds: 250) &&
                (state.position >= state.duration - const Duration(milliseconds: 250) ||
                    _playback.position >= state.duration - const Duration(milliseconds: 250))));
    final positionMs = atEnd
        ? 0
        : state?.position.inMilliseconds ?? _playback.position.inMilliseconds;
    await _requestControl('play', <String, Object?>{
      'itemId': _currentItemId,
      'positionMs': positionMs,
      'rateMilli': _playback.rateMilli,
    });
  }

  Future<void> pause() async {
    final positionMs = _player?.state.position.inMilliseconds ??
        _playback.position.inMilliseconds;
    await _requestControl('pause', <String, Object?>{
      'itemId': _currentItemId,
      'positionMs': positionMs,
      'rateMilli': _playback.rateMilli,
    });
  }

  Future<void> seek(Duration position) async {
    await _requestControl('seek', <String, Object?>{
      'positionMs': position.inMilliseconds,
    });
  }

  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(0.1, 8.0);
    await _requestControl('rate', <String, Object?>{
      'rateMilli': (clamped * 1000).round(),
    });
  }

  // --------------------------------------------------- cache occupancy (V1)

  /// V1 settings page: live P2P media cache occupancy, or `null` if no media
  /// service has been started yet (no local/remote P2P media has been set up).
  /// Reuses the media subsystem's existing bounded cache; no new cache layer
  /// is introduced here. UI must treat this as a snapshot, not a stream.
  MediaCacheTelemetrySnapshot? get cacheTelemetry {
    final media = _media;
    if (media == null) return null;
    return media.cacheTelemetry;
  }

  /// Bytes currently held by the P2P media chunk cache across all items.
  int get cacheUsedBytes => _media?.cacheTelemetry.cachedBytes ?? 0;

  /// Budget (ceiling) for the P2P media chunk cache in bytes.
  int get cacheMaxBytes => _media?.cacheTelemetry.maxBytes ?? kMediaMaxCacheBytes;

  /// Safe cache clear (V1 §9): evicts only unprotected chunks, keeping the
  /// chunks currently backing playback/serving of in-use items. Never deletes
  /// protected (in-use) chunks or playback files, and never interrupts an
  /// active session. Returns the number of bytes freed.
  ///
  /// This is a thin wrapper over the media subsystem's existing
  /// `clearUnprotectedCache()`; core introduces no separate management layer.
  Future<int> clearUnprotectedCache() async {
    final media = _media;
    if (media == null) return 0;
    try {
      final freed = await media.clearUnprotectedCache();
      // F5 recovery: a successful clear resets the media storage latch/code;
      // mirror that on the core side so a stale 'storage_full' does not linger.
      if (_lastErrorCode == 'storage_full') {
        _lastErrorCode = null;
        notifyListeners();
      }
      return freed;
    } catch (_) {
      _lastErrorCode = 'media_unavailable';
      notifyListeners();
      return 0;
    }
  }

  // --------------------------------------------------------- manual retry

  /// Manually re-establishes the signaling connection and re-registers the
  /// current room/identity, preserving room, identity and playback state (no
  /// reset). Safe to call while disconnected or reconnecting; concurrent or
  /// duplicate calls are ignored (`_retryInFlight` guard). Reuses the exact
  /// same re-registration and data-channel recovery path as auto-reconnect.
  ///
  /// Failures set [lastErrorCode] to `'signaling_unavailable'` and return the
  /// session to `disconnected` (the retry entry stays reachable). A successful
  /// retry after a signaling restart rotates the invite epoch and invalidates
  /// previously shared invites (see F3); recipients must be re-invited.
  Future<void> retry() async {
    if (_retryInFlight) return;
    if (_roomId == null || _signalingUrl == null || _keyPair == null) {
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
      return;
    }
    if (_connectionState == RoomConnectionState.connected) {
      if (_dc != null && _dcStateOpen() == true && _peerVerified) {
        return;
      }
      // Signaling is connected, but P2P channel/verification dropped or failed.
      // Reset ICE attempts and restart WebRTC recovery.
      _iceRestartAttempts = 0;
      _reconnectAttempt = 0;
      _reconnectExhausted = false;
      if (_lastErrorCode == 'connection_failed' ||
          _lastErrorCode == 'signaling_unavailable') {
        _lastErrorCode = null;
      }
      notifyListeners();
      if (role == RoomRole.owner) {
        await _teardownPeer();
        await _startWebRtc(isOwner: true);
      } else {
        await _requestResync(force: true);
      }
      return;
    }
    _retryInFlight = true;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _reconnectExhausted = false;
    _iceRestartAttempts = 0;
    _reconnecting = true;
    _connectionState = RoomConnectionState.reconnecting;
    notifyListeners();
    try {
      await _signaling.connect(_signalingUrl!);
      await _reconnectRegisterAndSettle();
    } catch (_) {
      // A failed manual attempt returns to the same terminal state instead of
      // leaving `reconnecting` stuck (which would hide the retry entry).
      _reconnectAttempt = 0;
      _reconnecting = false;
      _connectionState = RoomConnectionState.disconnected;
      _lastErrorCode = 'signaling_unavailable';
      notifyListeners();
    } finally {
      _retryInFlight = false;
    }
  }

  // ------------------------------------------------------- url probing

  static bool _isAllowedMediaUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      return host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '::1' ||
          host == '[::1]';
    }
    return false;
  }


  // ---------------------------------------------------------- dispose

  @override
  void dispose() {
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    AppSettings.instance.removeListener(updateLocalProfile);
    _closing = true;
    _reconnectTimer?.cancel();
    _handshakeTimer?.cancel();
    _parkedSweepTimer?.cancel();
    _stopRoomTimers();
    _mediaCompletedSub?.cancel();
    _mediaErrorSub?.cancel();
    final media = _media;
    _media = null;
    if (media != null) {
      unawaited(media.dispose());
    }
    unawaited(_teardownPeer());
    unawaited(_player?.dispose() ?? Future<void>.value());
    unawaited(_signaling.disconnect());
    super.dispose();
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this.session);
  final RoomSession session;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    session._handleAppLifecycleState(state);
  }
}

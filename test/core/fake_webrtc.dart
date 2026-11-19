import 'package:flutter_webrtc/flutter_webrtc.dart';

class FakeMediaTrack extends MediaStreamTrack {
  FakeMediaTrack(this.kindValue, {this.idValue = 'track-1'});

  final String kindValue;
  final String idValue;
  bool stopped = false;
  bool disposed = false;
  int stopCalls = 0;
  bool _enabled = true;

  @override
  String? get id => idValue;

  @override
  String? get label => 'fake';

  @override
  String? get kind => kindValue;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;

  @override
  bool? get muted => false;

  @override
  Future<void> stop() async {
    stopped = true;
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream extends MediaStream {
  FakeMediaStream({
    List<MediaStreamTrack>? tracks,
    String id = 'fake-stream',
  })  : _tracks = <MediaStreamTrack>[...?tracks],
        super(id, 'test');

  final List<MediaStreamTrack> _tracks;
  bool disposed = false;

  @override
  List<MediaStreamTrack> getTracks() => List<MediaStreamTrack>.from(_tracks);

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((t) => t.kind == 'audio').toList();

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((t) => t.kind == 'video').toList();

  @override
  Future<void> addTrack(MediaStreamTrack track, {bool addToNative = true}) async {
    _tracks.add(track);
  }

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    _tracks.remove(track);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRtpSender extends RTCRtpSender {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRtpTransceiver extends RTCRtpTransceiver {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePeerConnection extends RTCPeerConnection {
  bool closed = false;
  int closeCalls = 0;
  int createOfferCalls = 0;
  int createAnswerCalls = 0;
  int setRemoteDescriptionCalls = 0;
  final List<MediaStreamTrack> addedTracks = <MediaStreamTrack>[];
  final List<RTCIceCandidate> addedCandidates = <RTCIceCandidate>[];
  List<StatsReport> stats = <StatsReport>[];
  RTCSessionDescription? localDescription;
  RTCSessionDescription? remoteDescription;
  RTCSignalingState? _signalingState =
      RTCSignalingState.RTCSignalingStateStable;

  @override
  RTCSignalingState? get signalingState => _signalingState;

  set signalingState(RTCSignalingState? value) => _signalingState = value;

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic> constraints = const <String, dynamic>{},
  ]) async {
    createOfferCalls++;
    return RTCSessionDescription('v=0\r\n', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic> constraints = const <String, dynamic>{},
  ]) async {
    createAnswerCalls++;
    return RTCSessionDescription('v=0\r\n', 'answer');
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async =>
      localDescription;

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDescription = description;
    if (description.type == 'offer') {
      _signalingState = RTCSignalingState.RTCSignalingStateHaveLocalOffer;
    } else if (description.type == 'answer') {
      _signalingState = RTCSignalingState.RTCSignalingStateStable;
    }
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    setRemoteDescriptionCalls++;
    remoteDescription = description;
    if (description.type == 'offer') {
      _signalingState = RTCSignalingState.RTCSignalingStateHaveRemoteOffer;
    } else if (description.type == 'answer') {
      _signalingState = RTCSignalingState.RTCSignalingStateStable;
    }
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async => stats;

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    addedTracks.add(track);
    return FakeRtpSender();
  }

  @override
  Future<bool> removeTrack(RTCRtpSender sender) async => true;

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async =>
      FakeRtpTransceiver();

  @override
  Future<void> close() async {
    closed = true;
    closeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

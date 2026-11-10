import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:mime/mime.dart';

import 'media_cache.dart';
import 'media_cache_memory.dart' show MemoryChunkCache;
import 'media_format.dart';
import 'media_frames.dart';
import 'media_limits.dart';
import 'media_manifest.dart';
import 'media_server_interface.dart';

export 'media_limits.dart' show kMediaMaxCacheBytes, kMediaMaxFileBytes, kMediaChunkSize;
export 'media_cache.dart' show MediaCacheBudget;
export 'media_manifest.dart' show MediaManifest;

typedef CacheFactory = Future<MediaChunkCache?> Function(String mediaId, MediaManifest manifest);
typedef ServerHostFactory = MediaServerHost Function({required MediaWriteRange writeRange, required MediaReadRangeBytes readRangeBytes, required MediaManifestLookup manifestFor, required String token});
typedef MediaControlSender = void Function(Map<String, dynamic> message);
typedef MediaBinarySender = Future<void> Function(Uint8List frame);
typedef MediaBufferedAmount = FutureOr<int> Function();
typedef MediaMaxMessageBytes = FutureOr<int> Function();
typedef MediaManifestAuthorizer = Future<bool> Function(MediaManifest manifest);
typedef MediaRequestAuthorizer = Future<bool> Function(String mediaId);

class MediaTransferTelemetry {
  MediaTransferTelemetry({this.sentBytes = 0, this.receivedBytes = 0, this.sentFrames = 0, this.receivedFrames = 0, this.manifestBytesSent = 0, this.manifestBytesReceived = 0});
  int sentBytes;
  int receivedBytes;
  int sentFrames;
  int receivedFrames;
  int manifestBytesSent;
  int manifestBytesReceived;
}

class MediaCacheTelemetrySnapshot {
  MediaCacheTelemetrySnapshot({required this.cachedBytes, required this.cachedChunks, required this.hits, required this.misses, required this.evictedBytes, required this.maxBytes, this.lastStorageErrorCode});
  final int cachedBytes;
  final int cachedChunks;
  final int hits;
  final int misses;
  final int evictedBytes;
  final int maxBytes;

  /// `'storage_full'` after a native disk write failed for lack of space;
  /// `null` otherwise. Cleared by `clearUnprotectedCache()` after cleanup.
  final String? lastStorageErrorCode;
}

class _PendingFetch {
  _PendingFetch({required this.requestId, required this.mediaId, required this.start, required this.end, required this.urgent});

  final int requestId;
  final String mediaId;
  final int start;
  final int end;
  final bool urgent;
  final Completer<void> done = Completer<void>();
  final Map<int, Uint8List> parts = <int, Uint8List>{};
  int received = 0;
  bool cancelled = false;
  Uint8List? verifiedBytes;
}

class _ManifestReassembly {
  _ManifestReassembly({required this.transferId, required this.totalBytes, required this.chunks, required this.expectedSha});
  final String transferId;
  final int totalBytes;
  final int chunks;
  final String expectedSha;
  final Map<int, Uint8List> pieces = <int, Uint8List>{};
  int receivedBytes = 0;
  DateTime started = DateTime.now();
  bool cancelled = false;
}

class _SourceFile {
  _SourceFile({required this.manifest, required this.file});
  final MediaManifest manifest;
  final XFile file;
}

String localDeviceIdRequired(String? localDeviceId) {
  if (localDeviceId == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(localDeviceId)) {
    throw MediaException('invalid_manifest', 'localDeviceId required');
  }
  return localDeviceId;
}

abstract class BaseLocalMediaService {
  BaseLocalMediaService({
    required MediaControlSender sendControl,
    required MediaBinarySender sendBinary,
    required MediaBufferedAmount bufferedAmount,
    required String localDeviceId,
    MediaMaxMessageBytes? maxMessageBytes,
    MediaManifestAuthorizer? manifestAuthorizer,
    MediaRequestAuthorizer? requestAuthorizer,
    required ServerHostFactory serverHostFactory,
    CacheFactory? cacheFactory,
    int? maxCacheBytes,
    Duration fetchTimeout = kMediaFetchTimeout,
    String? sessionToken,
    void Function(String code)? onStorageError,
    void Function(String mediaId)? onSourceOffline,
    void Function(String mediaId)? onSourceAvailable,
  })  : _localDeviceId = localDeviceIdRequired(localDeviceId),
        _sendControl = sendControl,
        _sendBinary = sendBinary,
        _bufferedAmount = bufferedAmount,
        _maxMessageBytes = maxMessageBytes ?? (() => kMediaMaxMessageBytes),
        _manifestAuthorizer = manifestAuthorizer,
        _requestAuthorizer = requestAuthorizer,
        _serverHostFactory = serverHostFactory,
        _cacheFactory = cacheFactory,
        _fetchTimeout = fetchTimeout,
        _sessionToken = sessionToken ?? _randomHex64(),
        _onStorageError = onStorageError,
        _onSourceOffline = onSourceOffline,
        _onSourceAvailable = onSourceAvailable {
    if (maxCacheBytes != null) budget.maxBytes = maxCacheBytes;
  }

  final String _localDeviceId;
  final MediaControlSender _sendControl;
  final MediaBinarySender _sendBinary;
  final MediaBufferedAmount _bufferedAmount;
  final MediaMaxMessageBytes _maxMessageBytes;
  final MediaManifestAuthorizer? _manifestAuthorizer;
  final MediaRequestAuthorizer? _requestAuthorizer;
  final ServerHostFactory _serverHostFactory;
  final CacheFactory? _cacheFactory;
  final Duration _fetchTimeout;
  final String _sessionToken;
  final void Function(String code)? _onStorageError;
  final void Function(String mediaId)? _onSourceOffline;
  final void Function(String mediaId)? _onSourceAvailable;
  String? _lastStorageErrorCode;

  final Map<String, _SourceFile> _sources = <String, _SourceFile>{};
  final Map<String, MediaManifest> _remotes = <String, MediaManifest>{};
  final Map<String, MediaChunkCache> _caches = <String, MediaChunkCache>{};
  final Map<int, _PendingFetch> _pending = <int, _PendingFetch>{};
  final Map<String, int> _activeChunkReads = <String, int>{};
  final Map<String, Future<Uint8List>> _chunkFetches = <String, Future<Uint8List>>{};
  final List<_PendingFetch> _urgentQueue = <_PendingFetch>[];
  final Map<String, List<_PendingFetch>> _serveQueue = <String, List<_PendingFetch>>{};
  final Map<String, int> _cacheBytesByMedia = <String, int>{};
  final Map<String, int> _cacheChunksByMedia = <String, int>{};
  final _transfer = MediaTransferTelemetry();
  final _cacheTelemetry = MediaCacheTelemetry();
  final Map<String, _ManifestReassembly> _manifestTransfers = <String, _ManifestReassembly>{};

  MediaServerHost? _host;
  int _nextRequestId = 1;
  bool _started = false;
  bool _disposed = false;

  static int get kMaxManifestTransferBytes => kMediaMaxManifestBytes;

  String get loopbackBaseUrl => _host?.baseUrl ?? '';
  String get sessionToken => _sessionToken;
  MediaCacheTelemetrySnapshot get cacheTelemetry => MediaCacheTelemetrySnapshot(cachedBytes: _cacheTelemetry.cachedBytes, cachedChunks: _cacheTelemetry.cachedChunks, hits: _cacheTelemetry.hits, misses: _cacheTelemetry.misses, evictedBytes: _cacheTelemetry.evictedBytes, maxBytes: budget.maxBytes, lastStorageErrorCode: _lastStorageErrorCode);
  MediaTransferTelemetry get transferTelemetry => _transfer;

  /// `'storage_full'` after a native cache write failed for lack of disk
  /// space; `null` otherwise. Core maps this to its `lastErrorCode` and a
  /// localized "insufficient storage, please free space" message. Reset by
  /// [clearUnprotectedCache] once the user has freed space.
  String? get lastStorageErrorCode => _lastStorageErrorCode;

  void _recordStorageError(String code) {
    _lastStorageErrorCode = code;
    _onStorageError?.call(code);
  }

  MediaManifest? manifestFor(String mediaId) => _remotes[mediaId] ?? _sources[mediaId]?.manifest;

  Future<void> start() async {
    if (_started) return;
    _host = _serverHostFactory(writeRange: writeRange, readRangeBytes: readRangeBytes, manifestFor: manifestFor, token: _sessionToken);
    await _host!.start();
    _started = true;
  }

  String uriFor(String mediaId) {
    if (!_started || _host == null) throw MediaException('source_offline', 'service not started');
    if (manifestFor(mediaId) == null) throw MediaException('invalid_manifest', 'unknown media');
    return _host!.uriFor(mediaId);
  }

  Future<String> openMediaUri(String mediaId) async {
    if (!_started) await start();
    return uriFor(mediaId);
  }

  Future<Set<int>> _ensureCacheState(MediaManifest m) async {
    if (!_caches.containsKey(m.mediaId)) {
      final created = await _cacheFactory?.call(m.mediaId, m);
      _caches[m.mediaId] = created ?? MemoryChunkCache(mediaId: m.mediaId);
    }
    return _hashedIndicesOf(m);
  }

  Set<int> _hashedIndicesOf(MediaManifest m) => <int>{};

  Future<MediaChunkCache> _cacheFor(MediaManifest m) async {
    await _ensureCacheState(m);
    return _caches[m.mediaId]!;
  }

  Future<Set<int>> protectedChunkIndices(String mediaId, int centerChunk, {int radius = 4}) async {
    final manifest = manifestFor(mediaId);
    if (manifest == null) return <int>{};
    final out = <int>{};
    for (var i = centerChunk - radius; i <= centerChunk + radius; i++) {
      if (i >= 0 && i < manifest.chunkCount) out.add(i);
    }
    return out;
  }

  Future<Uint8List> _readExact(XFile file, int start, int end) async {
    final out = <int>[];
    await for (final part in file.openRead(start, end)) {
      out.addAll(part);
      if (out.length > kMediaChunkSize * 2) break;
    }
    return Uint8List.fromList(out);
  }

  Future<List<int>> _readMediaHeader(XFile file) async {
    final out = <int>[];
    await for (final part in file.openRead(0, defaultMagicNumbersMaxLength)) {
      out.addAll(part);
    }
    return out;
  }

  /// Registers a file with no container whitelist: the MIME is resolved by
  /// the `mime` package from the file header (magic numbers) plus name, the
  /// declared type wins when well-formed, and unclassifiable files fall back
  /// to `application/octet-stream` — the player decides playability. Known
  /// but unsafe types (e.g. `text/html`) throw `unsupported_media`.
  Future<MediaManifest> registerFile(XFile file, {String? title}) async {
    final size = await file.length();
    if (size <= 0 || size > kMediaMaxFileBytes) throw MediaException('unsupported_media', 'size');
    final mime = resolveMediaMime(
      magicMime: lookupMimeType(file.name, headerBytes: await _readMediaHeader(file)),
      declaredMime: file.mimeType,
      fileName: file.name,
    );
    final hashes = <String>[];
    final digestCollector = _DigestCollector();
    final fileHasher = crypto.sha256.startChunkedConversion(digestCollector);
    final chunkBuffer = <int>[];
    await for (final block in file.openRead()) {
      chunkBuffer.addAll(block);
      while (chunkBuffer.length >= kMediaChunkSize) {
        final chunk = Uint8List.fromList(chunkBuffer.sublist(0, kMediaChunkSize));
        chunkBuffer.removeRange(0, kMediaChunkSize);
        hashes.add(crypto.sha256.convert(chunk).toString());
        fileHasher.add(chunk);
      }
    }
    if (chunkBuffer.isNotEmpty) {
      final chunk = Uint8List.fromList(chunkBuffer);
      chunkBuffer.clear();
      hashes.add(crypto.sha256.convert(chunk).toString());
      fileHasher.add(chunk);
    }
    fileHasher.close();
    if (hashes.length > kMediaMaxManifestChunks) throw MediaException('unsupported_media', 'too many chunks');
    final fileSha = digestCollector.value!.toString();
    final mediaId = mediaIdFor(v: kMediaVersion, mime: mime, size: size, chunkSize: kMediaChunkSize, sourceDeviceId: _localDeviceId, fileSha256: fileSha, chunkHashes: hashes);
    final manifest = MediaManifest(mediaId: mediaId, sourceDeviceId: _localDeviceId, fileSha256: fileSha, mime: mime, size: size, chunkSize: kMediaChunkSize, chunkHashes: hashes, title: title);
    _sources[mediaId] = _SourceFile(manifest: manifest, file: file);
    await _cacheFor(manifest);
    return manifest;
  }

  Future<MediaManifest> registerRemoteManifest(Map<String, dynamic> json, {bool trustedByCore = false}) async {
    final manifest = MediaManifest.fromJson(json);
    var ok = trustedByCore;
    if (!ok && _manifestAuthorizer != null) ok = await _manifestAuthorizer(manifest);
    if (!ok) throw MediaException('untrusted_manifest');
    return _installRemote(manifest);
  }

  Future<MediaManifest> _installRemote(MediaManifest manifest) async {
    final existing = _remotes[manifest.mediaId];
    if (existing != null) {
      if (existing.toJson().toString() == manifest.toJson().toString()) return existing;
      throw MediaException('invalid_manifest', 'conflicting manifest');
    }
    _remotes[manifest.mediaId] = manifest;
    await _cacheFor(manifest);
    return manifest;
  }

  Future<void> writeManifestChunksFor(String mediaId, {int maxChunkBytes = kMediaManifestChunkBytes}) async {
    final manifest = manifestFor(mediaId);
    if (manifest == null) throw MediaException('invalid_manifest', 'unknown media');
    final bytes = utf8.encode(jsonEncode(manifest.toJson()));
    final sha = crypto.sha256.convert(bytes).toString();
    final total = (bytes.length + maxChunkBytes - 1) ~/ maxChunkBytes;
    final transferId = _randomHex64().substring(0, 32);
    for (var i = 0; i < total; i++) {
      final start = i * maxChunkBytes;
      final end = (start + maxChunkBytes).clamp(0, bytes.length);
      _sendControl(<String, dynamic>{'type': 'media_manifest_chunk', 'transferId': transferId, 'mediaId': mediaId, 'index': i, 'total': total, 'totalBytes': bytes.length, 'manifestSha256': sha, 'bytesB64': base64Encode(bytes.sublist(start, end))});
      _transfer.manifestBytesSent += end - start;
    }
  }

  void beginManifestTransfer(Map<String, dynamic> head) {
    final transferId = head['transferId'];
    final mediaId = head['mediaId'];
    final totalBytes = head['totalBytes'];
    final total = head['total'];
    final expectedSha = head['manifestSha256'];
    if (transferId is! String || mediaId is! String || totalBytes is! int || total is! int || expectedSha is! String) {
      throw MediaException('invalid_manifest', 'bad manifest head');
    }
    if (totalBytes <= 0 || totalBytes > kMaxManifestTransferBytes) throw MediaException('invalid_manifest', 'manifest too large');
    if (total <= 0 || total * kMediaManifestChunkBytes < totalBytes) throw MediaException('invalid_manifest', 'bad total');
    if (!isHex64(expectedSha)) throw MediaException('invalid_manifest', 'bad sha');
    _manifestTransfers[transferId] = _ManifestReassembly(transferId: transferId, totalBytes: totalBytes, chunks: total, expectedSha: expectedSha);
  }

  Future<MediaManifest?> handleManifestChunk(Map<String, dynamic> msg) async {
    final transferId = msg['transferId'];
    if (transferId is! String) throw MediaException('invalid_manifest', 'no transferId');
    var entry = _manifestTransfers[transferId];
    if (entry == null) {
      beginManifestTransfer(msg);
      entry = _manifestTransfers[transferId]!;
    }
    final index = msg['index'];
    final total = msg['total'];
    final bytesB64 = msg['bytesB64'];
    if (index is! int || total is! int || bytesB64 is! String) throw MediaException('invalid_manifest', 'bad chunk');
    if (total != entry.chunks || index < 0 || index >= entry.chunks) throw MediaException('invalid_manifest', 'chunk out of range');
    final bytes = base64Decode(bytesB64);
    if (bytes.isEmpty || bytes.length > kMediaManifestChunkBytes) throw MediaException('invalid_manifest', 'chunk too large');
    entry.pieces[index] = Uint8List.fromList(bytes);
    entry.receivedBytes = entry.pieces.values.fold(0, (a, b) => a + b.length);
    if (entry.pieces.length != entry.chunks) return null;
    final assembled = <int>[];
    for (var i = 0; i < entry.chunks; i++) {
      final piece = entry.pieces[i];
      if (piece == null) return null;
      assembled.addAll(piece);
    }
    final raw = Uint8List.fromList(assembled);
    if (crypto.sha256.convert(raw).toString() != entry.expectedSha) throw MediaException('invalid_manifest', 'manifest sha mismatch');
    try {
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final manifest = MediaManifest.fromJson(json);
      if (manifest.mediaId != msg['mediaId'] && msg['mediaId'] != null) throw MediaException('invalid_manifest', 'mediaId mismatch');
      final authorizer = _manifestAuthorizer;
      if (authorizer == null) throw MediaException('untrusted_manifest');
      final authOk = await authorizer(manifest);
      if (!authOk) throw MediaException('untrusted_manifest');
      _manifestTransfers.remove(transferId);
      return _installRemote(manifest);
    } catch (e) {
      _manifestTransfers.remove(transferId);
      rethrow;
    }
  }

  void onControl(Map<String, dynamic> message) {
    final type = message['type'];
    if (type == 'media_range_request') {
      _handleRemoteRequest(message);
    } else if (type == 'media_range_cancel') {
      final rid = message['requestId'];
      if (rid is int) _cancelPending(rid);
    } else if (type == 'media_manifest_chunk') {
      unawaited(handleManifestChunk(message).catchError((_) => null));
    } else if (type == 'media_error') {
      final rid = message['requestId'];
      final code = message['code'];
      if (rid is int) {
        final f = _pending.remove(rid);
        if (f != null && !f.done.isCompleted) f.done.completeError(MediaException(code is String ? code : 'source_offline'));
      }
    }
  }

  void onBinary(Uint8List frame) {
    MediaFrame decoded;
    try {
      decoded = MediaFrame.decode(frame);
    } catch (_) {
      return;
    }
    _transfer.receivedFrames++;
    _transfer.receivedBytes += frame.length;
    final fetch = _pending[decoded.requestId];
    if (fetch == null || fetch.cancelled) return;
    if (decoded.mediaId != fetch.mediaId) return;
    if (decoded.offset < fetch.start || decoded.offset + decoded.payload.length > fetch.end) return;
    if (fetch.parts.containsKey(decoded.offset)) return;
    fetch.parts[decoded.offset] = decoded.payload;
    fetch.received += decoded.payload.length;
    if (fetch.received >= fetch.end - fetch.start) _completeFetch(fetch);
  }

  void _completeFetch(_PendingFetch f) {
    if (f.done.isCompleted) return;
    _pending.remove(f.requestId);
    final bytes = BytesBuilder();
    var off = f.start;
    while (off < f.end) {
      final part = f.parts[off];
      if (part == null) break;
      bytes.add(part);
      off += part.length;
    }
    if (off < f.end) {
      if (!f.done.isCompleted) f.done.completeError(MediaException('source_offline', 'missing part'));
      return;
    }
    final all = bytes.toBytes();
    _verifyAndCache(f.mediaId, f.start, all).then((_) {
      f.verifiedBytes = all;
      if (!f.done.isCompleted) f.done.complete();
    }).catchError((Object e) {
      if (!f.done.isCompleted) f.done.completeError(e);
    });
  }

  Future<void> _verifyAndCache(String mediaId, int fileOffset, Uint8List bytes) async {
    final manifest = manifestFor(mediaId);
    if (manifest == null) throw MediaException('invalid_manifest', 'unknown media');
    final chunkIndex = fileOffset ~/ manifest.chunkSize;
    if (chunkIndex < 0 || chunkIndex >= manifest.chunkCount) throw MediaException('invalid_range');
    if (fileOffset != chunkIndex * manifest.chunkSize) throw MediaException('invalid_range', 'not chunk aligned');
    final expectedLen = manifest.chunkLength(chunkIndex);
    if (bytes.length != expectedLen) throw MediaException('invalid_range', 'bad chunk length');
    final expectedSha = manifest.chunkHashes[chunkIndex];
    final sum = crypto.sha256.convert(bytes).toString();
    if (sum != expectedSha) throw MediaException('chunk_hash_mismatch');
    final cache = await _cacheFor(manifest);
    try {
      await cache.putChunk(chunkIndex, bytes, expectedSha256: expectedSha);
    } on MediaException catch (e) {
      if (e.code == 'storage_full') {
        // Disk full: stop persisting, but keep the verified bytes available in
        // memory so this fetch (and playback) still completes.
        _recordStorageError('storage_full');
        return;
      }
      rethrow;
    }
    _accumulateCache(mediaId);
  }

  Future<void> _handleRemoteRequest(Map<String, dynamic> msg) async {
    final rid = msg['requestId'];
    final mediaId = msg['mediaId'];
    final start = msg['start'];
    final end = msg['end'];
    final urgent = msg['urgent'] == true;
    if (rid is! int || mediaId is! String || start is! int || end is! int) return;
    if (start < 0 || end <= start || end - start > kMediaMaxRangeBytes) {
      _sendControl(<String, dynamic>{'type': 'media_error', 'requestId': rid, 'code': 'invalid_range'});
      return;
    }
    if (_pending.length >= kMediaMaxPendingRequests) {
      _sendControl(<String, dynamic>{'type': 'media_error', 'requestId': rid, 'code': 'source_offline'});
      return;
    }
    final source = _sources[mediaId];
    if (source == null) {
      _sendControl(<String, dynamic>{'type': 'media_error', 'requestId': rid, 'code': 'source_offline'});
      return;
    }
    final manifest = source.manifest;
    if (start < 0 || end > manifest.size || end <= start) {
      _sendControl(<String, dynamic>{'type': 'media_error', 'requestId': rid, 'code': 'invalid_range'});
      return;
    }
    if (_requestAuthorizer != null && !await _requestAuthorizer(mediaId)) {
      _sendControl(<String, dynamic>{'type': 'media_error', 'requestId': rid, 'code': 'untrusted_manifest'});
      return;
    }
    final fetch = _PendingFetch(requestId: rid, mediaId: mediaId, start: start, end: end, urgent: urgent);
    (urgent ? _urgentQueue : (_serveQueue.putIfAbsent(mediaId, () => <_PendingFetch>[]))).add(fetch);
    _drainServeQueues();
  }

  Future<void> _drainServeQueues() async {
    while (_urgentQueue.isNotEmpty) {
      _serve(_urgentQueue.removeAt(0));
    }
    for (final list in _serveQueue.values) {
      while (list.isNotEmpty) {
        _serve(list.removeAt(0));
      }
    }
  }

  void _serve(_PendingFetch f) {
    if (f.cancelled || f.done.isCompleted) return;
    unawaited(_serveAsync(f));
  }

  Future<void> _serveAsync(_PendingFetch f) async {
    try {
      final source = _sources[f.mediaId]!;
      final manifest = source.manifest;
      var offset = f.start;
      while (offset < f.end) {
        if (f.cancelled) return;
        final chunkEnd = ((offset ~/ manifest.chunkSize) + 1) * manifest.chunkSize;
        final sliceEnd = chunkEnd.clamp(offset, f.end);
        final slice = await _readExact(source.file, offset, sliceEnd);
        var sent = 0;
        while (sent < slice.length) {
          if (f.cancelled) return;
          await _waitBackpressure();
          if (f.cancelled) return;
          final chunkLen = (slice.length - sent).clamp(0, _effectiveMessageBytes() - kFrameHeaderLen);
          final frame = MediaFrame(requestId: f.requestId, mediaId: f.mediaId, offset: offset + sent, payload: Uint8List.sublistView(slice, sent, sent + chunkLen));
          final encoded = frame.encode(maxMessageBytes: _effectiveMessageBytes());
          await _sendBinary(encoded);
          _transfer.sentFrames++;
          _transfer.sentBytes += encoded.length;
          sent += chunkLen;
        }
        offset = sliceEnd;
      }
      if (!f.done.isCompleted) f.done.complete();
    } catch (e) {
      _sendControl(<String, dynamic>{'type': 'media_error', 'requestId': f.requestId, 'code': 'source_offline'});
    }
  }

  Future<void> _waitBackpressure() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((await _bufferedAmount()) > kMediaHighWatermark) {
      if (DateTime.now().isAfter(deadline)) throw MediaException('source_offline', 'backpressure timeout');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  int _effectiveMessageBytes() {
    final v = _maxMessageBytes();
    final resolved = v is Future<int> ? kMediaMaxMessageBytes : v;
    if (resolved <= 0 || resolved > kMediaMaxMessageBytes) return kMediaMaxMessageBytes;
    return resolved;
  }

  Future<int> effectiveMessageBytes() async => _effectiveMessageBytes();

  Future<Uint8List> ensureChunk(String mediaId, int chunkIndex, {bool urgent = true}) async {
    final manifest = manifestFor(mediaId);
    if (manifest == null) throw MediaException('invalid_manifest', 'unknown media');
    if (chunkIndex < 0 || chunkIndex >= manifest.chunkCount) throw MediaException('invalid_range');
    final activeKey = _activeChunkKey(mediaId, chunkIndex);
    _activeChunkReads.update(activeKey, (v) => v + 1, ifAbsent: () => 1);
    try {
      final cache = await _cacheFor(manifest);
      final expected = manifest.chunkHashes[chunkIndex];
      final cached = await cache.getChunk(chunkIndex, expectedSha256: expected);
      if (cached != null) return cached;
      final source = _sources[mediaId];
      if (source != null) {
        final start = chunkIndex * manifest.chunkSize;
        final bytes = await _readExact(source.file, start, start + manifest.chunkLength(chunkIndex));
        final sum = crypto.sha256.convert(bytes).toString();
        if (sum != expected) throw MediaException('chunk_hash_mismatch');
        try {
          await cache.putChunk(chunkIndex, bytes, expectedSha256: expected);
        } on MediaException catch (e) {
          if (e.code == 'storage_full') {
            // Serve the verified bytes directly; do not fail on cache write.
            _recordStorageError('storage_full');
            return bytes;
          }
          rethrow;
        }
        _accumulateCache(mediaId);
        return bytes;
      }
      final start = chunkIndex * manifest.chunkSize;
      final end = start + manifest.chunkLength(chunkIndex);
      final existing = _chunkFetches[activeKey];
      if (existing != null) return await existing;
      // Player and probe Range requests can overlap on the same chunk.
      // Share its verified bytes instead of sending duplicate P2P requests.
      final fetch = _fetchRange(mediaId, start, end, urgent: urgent);
      _chunkFetches[activeKey] = fetch;
      try {
        return await fetch;
      } finally {
        if (identical(_chunkFetches[activeKey], fetch)) {
          _chunkFetches.remove(activeKey);
        }
      }
    } finally {
      final current = _activeChunkReads[activeKey];
      if (current == 1) {
        _activeChunkReads.remove(activeKey);
      } else if (current != null) {
        _activeChunkReads[activeKey] = current - 1;
      }
    }
  }

  Future<Uint8List> _fetchRange(String mediaId, int start, int end, {bool urgent = true}) async {
    if (end - start > kMediaMaxRangeBytes) throw MediaException('invalid_range', 'range too large');
    final manifest = manifestFor(mediaId)!;
    final firstChunk = start ~/ manifest.chunkSize;
    final lastChunk = (end - 1) ~/ manifest.chunkSize;
    final fetchedChunks = <int, Uint8List>{};
    for (var i = firstChunk; i <= lastChunk; i++) {
      final cache = await _cacheFor(manifest);
      if (await cache.getChunk(i, expectedSha256: manifest.chunkHashes[i]) != null) continue;
      final rid = _nextRequestId++;
      final fetch = _PendingFetch(requestId: rid, mediaId: mediaId, start: i * manifest.chunkSize, end: i * manifest.chunkSize + manifest.chunkLength(i), urgent: urgent);
      _pending[rid] = fetch;
      _sendControl(<String, dynamic>{'type': 'media_range_request', 'requestId': rid, 'mediaId': mediaId, 'start': fetch.start, 'end': fetch.end, 'urgent': urgent});
      try {
        await fetch.done.future.timeout(_fetchTimeout);
        final bytes = fetch.verifiedBytes;
        if (bytes != null) fetchedChunks[i] = bytes;
      } on TimeoutException {
        _pending.remove(rid);
        _sendControl(<String, dynamic>{'type': 'media_range_cancel', 'requestId': rid, 'mediaId': mediaId});
        throw MediaException('source_offline', 'fetch timeout');
      }
    }
    final out = BytesBuilder();
    var off = start;
    while (off < end) {
      final idx = off ~/ manifest.chunkSize;
      final chunk = await (await _cacheFor(manifest)).getChunk(idx, expectedSha256: manifest.chunkHashes[idx]);
      if (chunk != null) {
        final begin = off - idx * manifest.chunkSize;
        final take = (end - off).clamp(0, chunk.length - begin);
        out.add(Uint8List.sublistView(chunk, begin, begin + take));
        off += take;
        continue;
      }
      // The cache declined storage under the global budget; serve the
      // already-validated bytes without persisting them.
      final cached = fetchedChunks[idx];
      if (cached == null) throw MediaException('source_offline', 'chunk missing');
      final begin = off - idx * manifest.chunkSize;
      final take = (end - off).clamp(0, cached.length - begin);
      out.add(Uint8List.sublistView(cached, begin, begin + take));
      off += take;
    }
    return out.toBytes();
  }

  Future<Uint8List> readRangeBytes(String mediaId, int start, int end) async {
    final manifest = manifestFor(mediaId);
    if (manifest == null) throw MediaException('invalid_manifest', 'unknown media');
    if (start < 0 || end <= start || end > manifest.size || end - start > kMediaMaxRangeBytes) throw MediaException('invalid_range');
    final out = BytesBuilder();
    await writeRange(mediaId, start, end, (slice) async => out.add(slice));
    return out.toBytes();
  }

  Future<void> writeRange(String mediaId, int start, int end, Future<void> Function(Uint8List slice) write) async {
    final manifest = manifestFor(mediaId);
    if (manifest == null) throw MediaException('invalid_manifest', 'unknown media');
    if (start < 0 || end <= start || end > manifest.size) throw MediaException('invalid_range');
    var offset = start;
    while (offset < end) {
      final chunkIndex = offset ~/ manifest.chunkSize;
      final Uint8List chunk;
      try {
        chunk = await ensureChunk(mediaId, chunkIndex, urgent: true);
      } on MediaException catch (error) {
        if (error.code == 'source_offline') _onSourceOffline?.call(mediaId);
        rethrow;
      }
      (await _cacheFor(manifest)).protect(chunkIndex);
      final chunkStart = chunkIndex * manifest.chunkSize;
      final sliceStart = (offset - chunkStart).clamp(0, chunk.length);
      final sliceEnd = ((end - chunkStart) < chunk.length ? (end - chunkStart) : chunk.length).clamp(0, chunk.length);
      if (sliceEnd > sliceStart) {
        await write(Uint8List.sublistView(chunk, sliceStart, sliceEnd));
        _onSourceAvailable?.call(mediaId);
      }
      offset += (sliceEnd - sliceStart);
    }
  }

  Future<int> clearUnprotectedCache() async {
    final before = budget.cachedBytes;
    final mediaIds = _caches.keys.toList();
    for (;;) {
      var evicted = false;
      for (final mediaId in mediaIds) {
        final cache = _caches[mediaId];
        if (cache == null || cache.cachedBytes == 0) continue;
        if (await cache.evictOldest(protectedIndices: _activeChunksFor(mediaId))) {
          _accumulateCache(mediaId);
          evicted = true;
        }
      }
      if (!evicted) break;
    }
    // Freeing space clears the storage-full latch so new writes are retried;
    // if the disk is still full the next write re-latches and re-reports.
    MediaStorageState.reset();
    _lastStorageErrorCode = null;
    return before - budget.cachedBytes;
  }

  String _activeChunkKey(String mediaId, int chunkIndex) => '$mediaId:$chunkIndex';

  Set<int> _activeChunksFor(String mediaId) {
    final out = <int>{};
    for (final key in _activeChunkReads.keys) {
      final separator = key.lastIndexOf(':');
      if (separator <= 0) continue;
      if (key.substring(0, separator) != mediaId) continue;
      final index = int.tryParse(key.substring(separator + 1));
      if (index != null) out.add(index);
    }
    return out;
  }

  void cancelRequest(int requestId) => _cancelPending(requestId);

  void _cancelPending(int requestId) {
    final f = _pending.remove(requestId);
    if (f != null) {
      f.cancelled = true;
      if (!f.done.isCompleted) f.done.completeError(MediaException('source_offline', 'cancelled'));
    }
    _urgentQueue.removeWhere((q) => q.requestId == requestId);
    for (final list in _serveQueue.values) {
      list.removeWhere((q) => q.requestId == requestId);
    }
  }

  void _accumulateCache(String mediaId) {
    final cache = _caches[mediaId];
    if (cache == null) return;
    _cacheBytesByMedia[mediaId] = cache.telemetry.cachedBytes;
    _cacheChunksByMedia[mediaId] = cache.telemetry.cachedChunks;
    _cacheTelemetry.cachedBytes = _cacheBytesByMedia.values.fold(0, (a, b) => a + b);
    _cacheTelemetry.cachedChunks = _cacheChunksByMedia.values.fold(0, (a, b) => a + b);
    _cacheTelemetry.hits = cache.telemetry.hits;
    _cacheTelemetry.misses = cache.telemetry.misses;
    _cacheTelemetry.evictedBytes = cache.telemetry.evictedBytes;
  }

  Future<void> releaseMedia(String mediaId) async {
    _sources.remove(mediaId);
    _remotes.remove(mediaId);
    _cacheBytesByMedia.remove(mediaId);
    _cacheChunksByMedia.remove(mediaId);
    final cache = _caches.remove(mediaId);
    if (cache != null) await cache.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final f in _pending.values) {
      f.cancelled = true;
      if (!f.done.isCompleted) f.done.completeError(MediaException('source_offline', 'disposed'));
    }
    _pending.clear();
    for (final cache in _caches.values) {
      budget.unregister(cache);
    }
    _caches.clear();
    _cacheBytesByMedia.clear();
    _cacheChunksByMedia.clear();
    await _host?.stop();
    _host = null;
    _started = false;
  }
}

class _DigestCollector implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest d) => value = d;
  @override
  void close() {}
}

String _randomHex64() {
  final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}


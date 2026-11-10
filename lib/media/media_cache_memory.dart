import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'media_cache.dart';
import 'media_limits.dart';

bool chunkHashMatches(Uint8List bytes, String expectedSha256) =>
    crypto.sha256.convert(bytes).toString() == expectedSha256;

class MemoryChunkCache implements MediaChunkCache {
  MemoryChunkCache({required this.mediaId, this.registerBudget = true}) {
    if (registerBudget) budget.register(this);
  }

  @override
  final String mediaId;
  final bool registerBudget;
  final Map<int, Uint8List> _store = <int, Uint8List>{};
  final List<int> _lru = <int>[];
  final Set<int> _protected = <int>{};
  final _telemetry = MediaCacheTelemetry();

  @override
  int get cachedBytes => _telemetry.cachedBytes;

  @override
  MediaCacheTelemetry get telemetry => _telemetry;

  @override
  bool hasChunk(int index) => _store.containsKey(index);

  @override
  Future<Uint8List?> getChunk(int index, {required String expectedSha256}) async {
    final b = _store[index];
    if (b == null) {
      _telemetry.misses++;
      return null;
    }
    if (!chunkHashMatches(b, expectedSha256)) {
      _drop(index);
      _telemetry.misses++;
      return null;
    }
    _telemetry.hits++;
    _lru.remove(index);
    _lru.add(index);
    return Uint8List.fromList(b);
  }

  @override
  Future<void> putChunk(int index, Uint8List bytes, {required String expectedSha256}) async {
    if (!chunkHashMatches(bytes, expectedSha256)) throw MediaException('chunk_hash_mismatch');
    final prev = _store[index];
    if (!await budget.reserve(bytes.length)) return;
    if (prev != null) _drop(index);
    _store[index] = Uint8List.fromList(bytes);
    budget.update(bytes.length);
    _telemetry.cachedBytes += bytes.length;
    _lru.remove(index);
    _lru.add(index);
    _telemetry.cachedChunks = _store.length;
  }

  @override
  void protect(int index) {
    _protected.add(index);
    if (_protected.length > 16) {
      final s = _protected.toList()..sort();
      _protected.remove(s.first);
    }
  }

  int _drop(int index) {
    final prev = _store.remove(index);
    if (prev == null) return 0;
    budget.update(-prev.length);
    _telemetry.cachedBytes -= prev.length;
    _telemetry.cachedChunks = _store.length;
    _lru.remove(index);
    return prev.length;
  }

  @override
  Future<bool> evictOldest({Set<int> protectedIndices = const {}}) async {
    for (final i in List<int>.of(_lru)) {
      if (_protected.contains(i) || protectedIndices.contains(i)) continue;
      final len = _drop(i);
      if (len > 0) {
        _telemetry.evictedBytes += len;
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> clear() async {
    final total = _telemetry.cachedBytes;
    _store.clear();
    _lru.clear();
    _protected.clear();
    budget.update(-total);
    _telemetry.cachedBytes = 0;
    _telemetry.cachedChunks = 0;
    budget.unregister(this);
  }
}

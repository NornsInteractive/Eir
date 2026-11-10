import 'dart:typed_data';

import 'media_limits.dart';

class MediaCacheTelemetry {
  MediaCacheTelemetry({this.cachedBytes = 0, this.cachedChunks = 0, this.hits = 0, this.misses = 0, this.evictedBytes = 0});
  int cachedBytes;
  int cachedChunks;
  int hits;
  int misses;
  int evictedBytes;
}

abstract class MediaChunkCache {
  String get mediaId;
  MediaCacheTelemetry get telemetry;
  bool hasChunk(int index);
  Future<Uint8List?> getChunk(int index, {required String expectedSha256});
  Future<void> putChunk(int index, Uint8List bytes, {required String expectedSha256});
  void protect(int index);
  Future<void> clear();
  Future<bool> evictOldest({Set<int> protectedIndices = const {}});
  int get cachedBytes;
}

MediaCacheBudget budget = MediaCacheBudget();

/// Process-wide "storage full" latch for native disk caches.
///
/// A [MediaChunkCache] backed by disk sets this when a write fails with a
/// real disk-full / quota-exceeded file-system error (ENOSPC/EDQUOT or the
/// Windows equivalents). While set, disk caches stop attempting new writes
/// ("空间不足时停止新增缓存"); callers still serve already-verified bytes from
/// memory so playback does not silently stall. [reset] is called after the
/// user frees space (e.g. `clearUnprotectedCache`), allowing writes to retry.
///
/// This lives here (not in the disk cache file) so the shared, platform-neutral
/// service layer can read/reset it without importing `dart:io`. Web memory
/// caches never set it — their bound is the byte budget, not disk space.
class MediaStorageState {
  static bool blocked = false;
  static String? lastCode;

  static void reportFull() {
    blocked = true;
    lastCode = 'storage_full';
  }

  static void reset() {
    blocked = false;
    lastCode = null;
  }
}

class MediaCacheBudget {
  int maxBytes = kMediaMaxCacheBytes;
  final Set<MediaChunkCache> _members = <MediaChunkCache>{};
  int cachedBytes = 0;

  void register(MediaChunkCache c) {
    if (_members.add(c)) cachedBytes += c.cachedBytes;
  }

  void unregister(MediaChunkCache c) {
    if (_members.remove(c)) cachedBytes -= c.cachedBytes;
  }

  void update(int delta) => cachedBytes += delta;

  /// Evicts global chunks until [reserve] bytes fit under the budget.
  /// Returns true when [bytes] can be cached without exceeding [maxBytes].
  /// Unprotected bytes are evicted first across every registered cache.
  /// If only protected playback windows remain, the new bytes are not
  /// cached rather than breaking the global bound.
  Future<bool> reserve(int bytes) async {
    while (cachedBytes + bytes > maxBytes) {
      var evicted = false;
      for (final m in _members) {
        if (await m.evictOldest()) {
          evicted = true;
          break;
        }
      }
      if (!evicted) return false;
    }
    return true;
  }
}

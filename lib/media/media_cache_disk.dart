import 'dart:io';
import 'dart:typed_data';

import 'media_cache.dart';
import 'media_cache_memory.dart' show chunkHashMatches;
import 'media_limits.dart';

String _chunkName(int index) => '${index.toString().padLeft(8, '0')}.chunk';

/// True for a real "disk full" / "quota exceeded" file-system error on the
/// native platforms this app targets. Uses the platform errno/Win32 code and
/// falls back to the OS message, so one code path covers desktop + mobile
/// (`dart:io` is shared there). Not used on web (memory cache).
///
/// POSIX: ENOSPC=28, EDQUOT=122. Windows: ERROR_HANDLE_DISK_FULL=39,
/// ERROR_DISK_FULL=112.
bool isStorageFullError(Object error) {
  if (error is! FileSystemException) return false;
  final code = error.osError?.errorCode;
  if (code == 28 || code == 122 || code == 39 || code == 112) return true;
  final message = (error.osError?.message ?? error.message).toLowerCase();
  return message.contains('no space left') ||
      message.contains('disk quota') ||
      message.contains('not enough space') ||
      message.contains('disk full');
}

/// Optional chunk-write hook. Production uses `File.writeAsBytes`; tests
/// inject a failing writer to exercise ENOSPC deterministically. This is a
/// single-function seam, not a platform disk abstraction.
typedef ChunkFileWriter = Future<void> Function(File file, Uint8List bytes);

class DiskChunkCache implements MediaChunkCache {
  DiskChunkCache({required this.mediaId, required this.directory, required this.chunkSize, required this.maxCacheBytes, this.registerBudget = true, this.writeChunkFile});

  @override
  final String mediaId;
  final Directory directory;
  final int chunkSize;
  @Deprecated('Global budget now applies. Use MediaCacheBudget.instance.maxBytes.')
  final int maxCacheBytes;
  final bool registerBudget;
  final ChunkFileWriter? writeChunkFile;
  final Map<int, int> _len = <int, int>{};
  final List<int> _lru = <int>[];
  final Set<int> _protected = <int>{};
  final _telemetry = MediaCacheTelemetry();

  @override
  int get cachedBytes => _telemetry.cachedBytes;

  @override
  MediaCacheTelemetry get telemetry => _telemetry;

  Future<void> init() async {
    if (!await directory.exists()) await directory.create(recursive: true);
    await for (final e in directory.list(followLinks: false)) {
      if (e is! File) continue;
      final n = e.path.split(Platform.pathSeparator).last;
      if (n.startsWith('.tmp')) {
        // Leftover temp file from a crash or a failed write: clean it up.
        await _deleteQuietly(e);
        continue;
      }
      if (!n.endsWith('.chunk')) continue;
      final idx = int.tryParse(n.substring(0, n.length - 6));
      if (idx == null || idx < 0) continue;
      final len = await e.length();
      if (len <= 0 || len > chunkSize) continue;
      _len[idx] = len;
      _lru.add(idx);
    }
    _telemetry.cachedBytes = _len.values.fold(0, (a, b) => a + b);
    _telemetry.cachedChunks = _len.length;
    if (registerBudget) budget.register(this);
  }

  File _file(int index) => File('${directory.path}${Platform.pathSeparator}${_chunkName(index)}');

  @override
  bool hasChunk(int index) => _len.containsKey(index);

  @override
  Future<Uint8List?> getChunk(int index, {required String expectedSha256}) async {
    final f = _file(index);
    if (!_len.containsKey(index)) {
      _telemetry.misses++;
      return null;
    }
    try {
      final bytes = Uint8List.fromList(await f.readAsBytes());
      if (!chunkHashMatches(bytes, expectedSha256) || bytes.length != _len[index]) {
        await _drop(index);
        _telemetry.misses++;
        return null;
      }
      _telemetry.hits++;
      _lru.remove(index);
      _lru.add(index);
      return bytes;
    } catch (_) {
      _telemetry.misses++;
      return null;
    }
  }

  @override
  Future<void> putChunk(int index, Uint8List bytes, {required String expectedSha256}) async {
    if (!chunkHashMatches(bytes, expectedSha256)) throw MediaException('chunk_hash_mismatch');
    if (MediaStorageState.blocked) {
      // Storage already known full: stop adding new cache entries without
      // touching the disk. Callers keep serving verified bytes from memory.
      throw MediaException('storage_full');
    }
    final prevLen = _len[index] ?? 0;
    final net = bytes.length - prevLen;
    if (net > 0 && !await budget.reserve(net)) return;
    final tmp = File('${directory.path}${Platform.pathSeparator}.tmp$index');
    try {
      // Write to a temp file and atomically rename over the target. The old
      // chunk (if any) stays intact until the new one is fully in place, so a
      // failed write never deletes a valid cached block.
      await _writeChunk(tmp, bytes);
      await tmp.rename(_file(index).path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(tmp);
      if (isStorageFullError(e)) {
        MediaStorageState.reportFull();
        throw MediaException('storage_full');
      }
      rethrow;
    } catch (_) {
      await _deleteQuietly(tmp);
      rethrow;
    }
    if (prevLen > 0) _telemetry.cachedBytes -= prevLen;
    _len[index] = bytes.length;
    budget.update(net);
    _telemetry.cachedBytes += bytes.length;
    _telemetry.cachedChunks = _len.length;
    _lru.remove(index);
    _lru.add(index);
  }

  Future<void> _writeChunk(File file, Uint8List bytes) async {
    final hook = writeChunkFile;
    if (hook != null) {
      await hook(file, bytes);
    } else {
      await file.writeAsBytes(bytes, flush: true);
    }
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  @override
  void protect(int index) {
    _protected.add(index);
    if (_protected.length > 16) {
      final s = _protected.toList()..sort();
      _protected.remove(s.first);
    }
  }

  Future<int> _drop(int index) async {
    final len = _len.remove(index);
    if (len == null) return 0;
    budget.update(-len);
    _telemetry.cachedBytes -= len;
    _telemetry.cachedChunks = _len.length;
    _lru.remove(index);
    try {
      await _file(index).delete();
    } catch (_) {}
    return len;
  }

  @override
  Future<bool> evictOldest({Set<int> protectedIndices = const {}}) async {
    for (final i in List<int>.of(_lru)) {
      if (_protected.contains(i) || protectedIndices.contains(i)) continue;
      final len = await _drop(i);
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
    budget.update(-total);
    _len.clear();
    _lru.clear();
    _protected.clear();
    _telemetry.cachedBytes = 0;
    _telemetry.cachedChunks = 0;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
    budget.unregister(this);
  }
}

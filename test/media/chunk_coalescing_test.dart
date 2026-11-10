import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:eir/media/media_limits.dart';
import 'package:flutter_test/flutter_test.dart';

const _chunkSize = kMediaChunkSize;

Uint8List fileBytes(int length, {int seed = 31}) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * seed + 7) % 251));

Uint8List expectedChunk(List<int> full, int chunkIndex) {
  final start = chunkIndex * _chunkSize;
  final end = (start + _chunkSize).clamp(0, full.length);
  return Uint8List.fromList(full.sublist(start, end));
}

/// Pure unit harness: no HTTP server, no ADB/Web build, no device.
class Harness {
  Harness({required this.fetchTimeout}) : controlLog = <Map<String, dynamic>>[];

  final Duration fetchTimeout;
  final List<Map<String, dynamic>> controlLog;
  final List<Uint8List> heldFrames = <Uint8List>[];
  bool holdBinary = false;
  bool dropBinary = false;

  late final Directory root;
  late final LocalMediaService source;
  late final LocalMediaService recv;

  Future<void> setUp() async {
    root = await Directory.systemTemp.createTemp('eir-coalesce-');
    final sourceDir = Directory('${root.path}/src');
    final recvDir = Directory('${root.path}/recv');
    await sourceDir.create();
    await recvDir.create();
    source = LocalMediaService(
      sendControl: (m) {
        controlLog.add(m);
        recv.onControl(m);
      },
      sendBinary: (f) async {
        if (dropBinary) return;
        if (holdBinary) {
          heldFrames.add(Uint8List.fromList(f));
          return;
        }
        recv.onBinary(f);
      },
      bufferedAmount: () => 0,
      localDeviceId: 'a' * 64,
      cacheDir: sourceDir,
    );
    recv = LocalMediaService(
      sendControl: (m) {
        controlLog.add(m);
        source.onControl(m);
      },
      sendBinary: (f) async => source.onBinary(f),
      bufferedAmount: () => 0,
      localDeviceId: 'b' * 64,
      cacheDir: recvDir,
      fetchTimeout: fetchTimeout,
    );
  }

  Future<void> tearDown() async {
    await source.dispose();
    await recv.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<MediaManifest> addMedia(List<int> bytes, {String name = 'sample.mp4'}) async {
    final manifest = await source.registerFile(
      XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: 'video/mp4'),
      title: name,
    );
    await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
    return manifest;
  }

  List<Map<String, dynamic>> rangeRequests({String? mediaId, int? start}) =>
      controlLog.where((m) {
        if (m['type'] != 'media_range_request') return false;
        if (mediaId != null && m['mediaId'] != mediaId) return false;
        if (start != null && m['start'] != start) return false;
        return true;
      }).toList();

  int requestCount({String? mediaId, int? start}) => rangeRequests(mediaId: mediaId, start: start).length;

  Future<Map<String, dynamic>> waitForRequest({String? mediaId, int? start}) async {
    for (var i = 0; i < 500; i++) {
      final found = rangeRequests(mediaId: mediaId, start: start);
      if (found.isNotEmpty) return found.first;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('media_range_request not observed');
  }

  Future<void> waitForRequests(int n) async {
    for (var i = 0; i < 500; i++) {
      if (requestCount() >= n) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('expected $n range requests, got ${requestCount()}');
  }

  void releaseHeld() {
    holdBinary = false;
    final frames = heldFrames.toList();
    heldFrames.clear();
    for (final f in frames) {
      recv.onBinary(f);
    }
  }

  void clearHeld() {
    heldFrames.clear();
    holdBinary = false;
  }
}

Future<Object> settle(Future<Uint8List> f) async {
  try {
    return await f;
  } catch (e) {
    return e;
  }
}

MediaException asMediaException(Object e, String code) {
  expect(e, isA<MediaException>(), reason: 'expected MediaException($code), got $e');
  final me = e as MediaException;
  expect(me.code, code);
  return me;
}

void main() {
  group('ensureChunk _chunkFetches coalescing', () {
    test('concurrent same chunk: one request, equal bytes, then cache hit', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      h.holdBinary = true;
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s2 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      await h.waitForRequest(mediaId: manifest.mediaId, start: 0);
      // Give the second caller a window to attach to the shared future.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(h.requestCount(), 1, reason: 'same media/chunk must share one fetch');

      h.releaseHeld();
      final b1 = await s1;
      final b2 = await s2;
      expect(b1, isA<Uint8List>());
      expect(b2, isA<Uint8List>());
      expect(b1 as Uint8List, expectedChunk(full, 0));
      expect(b2 as Uint8List, expectedChunk(full, 0));
      expect(b2, b1);
      expect(h.requestCount(), 1);

      final b3 = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(b3, expectedChunk(full, 0));
      expect(h.requestCount(), 1, reason: 'cached chunk must not fetch again');
    });

    test('different media same chunkIndex are not merged', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final fullA = fileBytes(600_000, seed: 31);
      final fullB = fileBytes(600_000, seed: 47);
      final mA = await h.addMedia(fullA, name: 'a.mp4');
      final mB = await h.addMedia(fullB, name: 'b.mp4');
      expect(mA.mediaId, isNot(mB.mediaId));

      h.holdBinary = true;
      final sA = settle(h.recv.ensureChunk(mA.mediaId, 0));
      final sB = settle(h.recv.ensureChunk(mB.mediaId, 0));
      await h.waitForRequests(2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.requestCount(), 2);
      expect(h.requestCount(mediaId: mA.mediaId), 1);
      expect(h.requestCount(mediaId: mB.mediaId), 1);

      h.releaseHeld();
      final bA = await sA;
      final bB = await sB;
      expect(bA as Uint8List, expectedChunk(fullA, 0));
      expect(bB as Uint8List, expectedChunk(fullB, 0));
      expect(bA, isNot(bB));
    });

    test('different chunks of same media are not merged', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      h.holdBinary = true;
      final s0 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 1));
      await h.waitForRequests(2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.requestCount(), 2);
      expect(h.requestCount(start: 0), 1);
      expect(h.requestCount(start: _chunkSize), 1);

      h.releaseHeld();
      expect(await s0 as Uint8List, expectedChunk(full, 0));
      expect(await s1 as Uint8List, expectedChunk(full, 1));
    });

    test('timeout: all waiters fail, entry cleaned, retry sends new request', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 400));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      h.dropBinary = true;
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s2 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      await h.waitForRequest(mediaId: manifest.mediaId, start: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.requestCount(), 1);

      asMediaException(await s1, 'source_offline');
      asMediaException(await s2, 'source_offline');
      expect(h.recv.cacheTelemetry.cachedChunks, 0, reason: 'failed fetch must not cache');

      h.dropBinary = false;
      final retried = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(retried, expectedChunk(full, 0));
      expect(h.requestCount(), 2, reason: 'retry must issue a fresh request after cleanup');
      expect(h.recv.cacheTelemetry.cachedChunks, 1);
    });

    test('peer media_error: all waiters fail, retry succeeds', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      h.holdBinary = true;
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s2 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final request = await h.waitForRequest(mediaId: manifest.mediaId, start: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.requestCount(), 1);

      h.recv.onControl(<String, dynamic>{
        'type': 'media_error',
        'requestId': request['requestId'],
        'code': 'source_offline',
      });
      asMediaException(await s1, 'source_offline');
      asMediaException(await s2, 'source_offline');
      expect(h.recv.cacheTelemetry.cachedChunks, 0);
      h.clearHeld();

      final retried = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(retried, expectedChunk(full, 0));
      expect(h.requestCount(), 2);
    });

    test('cache + active cleanup: clear after completion frees; refetch proves entry removed', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      final first = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(first, expectedChunk(full, 0));
      expect(h.requestCount(), 1);
      expect(h.recv.cacheTelemetry.cachedChunks, 1);

      final second = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(second, expectedChunk(full, 0));
      expect(h.requestCount(), 1, reason: 'cache hit must not fetch');

      final freed = await h.recv.clearUnprotectedCache();
      expect(freed, greaterThan(0), reason: 'completed read must not stay protected');
      expect(h.recv.cacheTelemetry.cachedChunks, 0);
      expect(h.recv.cacheTelemetry.cachedBytes, 0);

      final third = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(third, expectedChunk(full, 0));
      expect(h.requestCount(), 2, reason: 'stale _chunkFetches entry would suppress refetch');
    });

    test('clear during in-flight coalesced fetch does not break waiters', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      final idle = await h.recv.ensureChunk(manifest.mediaId, 1);
      expect(idle, expectedChunk(full, 1));
      expect(h.recv.cacheTelemetry.cachedChunks, 1);

      h.holdBinary = true;
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s2 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      await h.waitForRequest(mediaId: manifest.mediaId, start: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.requestCount(), 2, reason: 'one cached chunk-1 fetch + one coalesced chunk-0 fetch');

      final freed = await h.recv.clearUnprotectedCache();
      expect(freed, greaterThan(0), reason: 'idle chunk 1 is evictable while chunk 0 is in flight');
      expect(h.recv.cacheTelemetry.cachedChunks, 0);

      h.releaseHeld();
      final b1 = await s1;
      final b2 = await s2;
      expect(b1 as Uint8List, expectedChunk(full, 0));
      expect(b2 as Uint8List, expectedChunk(full, 0));
      expect(h.recv.cacheTelemetry.cachedChunks, 1);

      final cached = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(cached, expectedChunk(full, 0));
      expect(h.requestCount(), 2, reason: 'completed in-flight chunk must be cached');
    });

    test('cancelRequest: shared waiters fail once, retry recovers', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5));
      await h.setUp();
      addTearDown(h.tearDown);
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      h.holdBinary = true;
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s2 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final request = await h.waitForRequest(mediaId: manifest.mediaId, start: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.requestCount(), 1);

      h.recv.cancelRequest(request['requestId'] as int);
      asMediaException(await s1, 'source_offline');
      asMediaException(await s2, 'source_offline');
      expect(h.recv.cacheTelemetry.cachedChunks, 0);
      h.clearHeld();

      final retried = await h.recv.ensureChunk(manifest.mediaId, 0);
      expect(retried, expectedChunk(full, 0));
      expect(h.requestCount(), 2);
    });

    test('dispose during coalesced fetch: waiters settle promptly, no hang/leak', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 10));
      await h.setUp();
      final full = fileBytes(600_000, seed: 31);
      final manifest = await h.addMedia(full);

      h.holdBinary = true;
      final s1 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      final s2 = settle(h.recv.ensureChunk(manifest.mediaId, 0));
      await h.waitForRequest(mediaId: manifest.mediaId, start: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(h.requestCount(), 1);

      await h.recv.dispose();

      // Must settle quickly, not hang until the 10s fetch timeout.
      final r1 = await s1.timeout(const Duration(seconds: 3));
      final r2 = await s2.timeout(const Duration(seconds: 3));
      asMediaException(r1, 'source_offline');
      asMediaException(r2, 'source_offline');

      // Dispose is idempotent; second call must be a no-op (no throw).
      await h.recv.dispose();
      h.clearHeld();
      await h.source.dispose();
      await h.root.delete(recursive: true);
    });
  });
}

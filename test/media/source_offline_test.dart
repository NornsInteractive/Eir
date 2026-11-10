import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:eir/media/media_frames.dart';
import 'package:eir/media/media_limits.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fileBytes(int length, {int seed = 31}) => Uint8List.fromList(List<int>.generate(length, (i) => (i * seed + 7) % 251));

/// Regression harness for the current-media `source_offline` feedback path:
/// `BaseLocalMediaService.writeRange` must invoke `onSourceOffline(mediaId)`
/// when a chunk fetch fails with `source_offline` (fetch timeout, peer
/// `media_error`, peer cancel, backpressure), and must NOT invoke it for
/// other error codes or on success. `RoomSession` filters by
/// `_itemById(_currentItemId)?.localMediaId != mediaId`, so these tests pin
/// the service-side contract: the callback carries the failing `mediaId`.
class Harness {
  Harness({
    required this.fetchTimeout,
    required this.bufferedAmount,
  })  : offlineEvents = <String>[],
        controlLog = <Map<String, dynamic>>[];

  final Duration fetchTimeout;
  final FutureOr<int> Function() bufferedAmount;
  final List<String> offlineEvents;
  final List<Map<String, dynamic>> controlLog;

  /// Binary frames for these requestIds are dropped (simulates a stalled
  /// DataChannel): the member times out, sends `media_range_cancel` and
  /// throws `source_offline`.
  final Set<int> dropRequestIds = <int>{};

  /// Binary frames for these mediaIds are dropped entirely.
  final Set<String> dropMediaIds = <String>{};

  /// When true, binary frames are dropped until [allowBinary] is set.
  bool dropAllBinary = false;

  late final Directory root;
  late final LocalMediaService source;
  late final LocalMediaService recv;

  Future<void> setUp() async {
    root = await Directory.systemTemp.createTemp('eir-offline-');
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
        if (dropAllBinary) return;
        final decoded = MediaFrame.decode(f);
        if (dropRequestIds.contains(decoded.requestId)) return;
        if (dropMediaIds.contains(decoded.mediaId)) return;
        recv.onBinary(f);
      },
      bufferedAmount: bufferedAmount,
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
      onSourceOffline: offlineEvents.add,
    );
  }

  Future<MediaManifest> addMedia(int length, {int seed = 31}) async {
    final manifest = await source.registerFile(
      XFile.fromData(fileBytes(length, seed: seed), name: 'sample.mp4', mimeType: 'video/mp4'),
      title: 'sample',
    );
    await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
    return manifest;
  }

  Future<void> tearDown() async {
    await source.dispose();
    await recv.dispose();
    await root.delete(recursive: true);
  }

  Future<void> startRecv() async {
    await recv.start();
  }

  /// Direct `writeRange` read (same path the loopback HTTP bridge uses).
  Future<Uint8List> readViaWriteRange(String mediaId, int start, int end) async {
    final out = BytesBuilder(copy: false);
    await recv.writeRange(mediaId, start, end, (slice) async => out.add(slice));
    return out.toBytes();
  }
}

void main() {
  group('source_offline feedback (current media vs stale media)', () {
    test('timeout on current media fires onSourceOffline with its mediaId', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 400), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.startRecv();
      h.dropAllBinary = true;
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      // fetch timeout must also emit a cancel for the peer.
      expect(
        h.controlLog.any((m) => m['type'] == 'media_range_request'),
        isTrue,
        reason: 'member must have requested the range',
      );
    });

    test('successful retry after timeout returns bytes and stays cached', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 400), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.startRecv();
      h.dropAllBinary = true;
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      h.dropAllBinary = false;
      final bytes = await h.readViaWriteRange(manifest.mediaId, 0, 100);
      expect(bytes, fileBytes(700_000).sublist(0, 100));
      // No second offline event on success: the error must not latch.
      expect(h.offlineEvents, [manifest.mediaId]);
      expect(h.recv.cacheTelemetry.cachedChunks, greaterThan(0));
      // Buffering recovery proof: with the network dropped again, the
      // cached chunk still serves without any fetch (bytes, not just
      // cleared error UI).
      h.dropAllBinary = true;
      final again = await h.readViaWriteRange(manifest.mediaId, 0, 100);
      expect(again, fileBytes(700_000).sublist(0, 100));
      expect(h.offlineEvents, [manifest.mediaId]);
    });

    test('stale (switched-away) media reports its own mediaId, not the current one', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 500), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final oldManifest = await h.addMedia(700_000, seed: 31);
      final currentManifest = await h.addMedia(700_000, seed: 47);
      expect(oldManifest.mediaId, isNot(currentManifest.mediaId));
      await h.startRecv();
      // Simulate the switch race: the old item's chunk is in flight and stalls
      // while the new (current) item is fetched concurrently. Only the old
      // fetch fails; the service must attribute the failure to the OLD id so
      // RoomSession can drop it (current item mismatch => ignored).
      h.dropMediaIds.add(oldManifest.mediaId);
      final oldFuture = h.readViaWriteRange(oldManifest.mediaId, 0, 100);
      final currentFuture = h.readViaWriteRange(currentManifest.mediaId, 0, 100);
      await expectLater(
        oldFuture,
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      final currentBytes = await currentFuture;
      expect(currentBytes, fileBytes(700_000, seed: 47).sublist(0, 100));
      expect(h.offlineEvents, [oldManifest.mediaId]);
    });

    test('normal Range over loopback HTTP still serves 206 without offline feedback', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.startRecv();
      final client = HttpClient();
      addTearDown(client.close);
      final req = await client.getUrl(Uri.parse(h.recv.uriFor(manifest.mediaId)));
      req.headers.set('Range', 'bytes=100-199');
      final res = await req.close();
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 100-199/700000');
      final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body, fileBytes(700_000).sublist(100, 200));
      expect(h.offlineEvents, isEmpty);
    });

    test('peer media_error maps to source_offline feedback', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.startRecv();
      h.dropAllBinary = true;
      final future = h.readViaWriteRange(manifest.mediaId, 0, 100);
      // Wait for the range request to be issued, then answer with media_error
      // (peer source missing / backpressure path).
      final request = await h.controlLog.firstWhereAsync((m) => m['type'] == 'media_range_request');
      h.recv.onControl(<String, dynamic>{'type': 'media_error', 'requestId': request['requestId'], 'code': 'source_offline'});
      await expectLater(
        future,
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
    });

    test('peer cancel completes the pending fetch as source_offline', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.startRecv();
      h.dropAllBinary = true;
      final future = h.readViaWriteRange(manifest.mediaId, 0, 100);
      final request = await h.controlLog.firstWhereAsync((m) => m['type'] == 'media_range_request');
      h.recv.cancelRequest(request['requestId'] as int);
      await expectLater(
        future,
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
    });

    test('invalid_range does NOT fire onSourceOffline', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.startRecv();
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 300_000, 300_100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'invalid_range')),
      );
      expect(h.offlineEvents, isEmpty);
    });

    test('hash-corrupted chunk does NOT fire onSourceOffline', () async {
      final root = await Directory.systemTemp.createTemp('eir-offline-corrupt-');
      addTearDown(() async => root.delete(recursive: true));
      final sourceDir = Directory('${root.path}/s');
      final recvDir = Directory('${root.path}/r');
      await sourceDir.create(recursive: true);
      await recvDir.create();
      final offlineEvents = <String>[];
      late LocalMediaService source;
      late LocalMediaService recv;
      source = LocalMediaService(
        sendControl: (m) => recv.onControl(m),
        sendBinary: (f) async {
          final corrupted = Uint8List.fromList(f);
          if (corrupted.length > 50) corrupted[49] ^= 0xff;
          recv.onBinary(corrupted);
        },
        bufferedAmount: () => 0,
        localDeviceId: 'a' * 64,
        cacheDir: sourceDir,
      );
      recv = LocalMediaService(
        sendControl: (m) => source.onControl(m),
        sendBinary: (f) async => source.onBinary(f),
        bufferedAmount: () => 0,
        localDeviceId: 'b' * 64,
        cacheDir: recvDir,
        onSourceOffline: offlineEvents.add,
      );
      addTearDown(() async {
        await source.dispose();
        await recv.dispose();
      });
      final manifest = await source.registerFile(XFile.fromData(fileBytes(600_000), name: 'c.mp4', mimeType: 'video/mp4'));
      await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
      await recv.start();
      final out = BytesBuilder(copy: false);
      Object? thrown;
      try {
        await recv.writeRange(manifest.mediaId, 0, 100, (slice) async => out.add(slice));
      } catch (e) {
        thrown = e;
      }
      // Hash mismatch surfaces as its own code and must neither be cached
      // nor reported as offline.
      expect(thrown, isA<MediaException>().having((e) => e.code, 'code', 'chunk_hash_mismatch'));
      expect(recv.cacheTelemetry.cachedChunks, 0);
      expect(offlineEvents, isEmpty);
    });

    test('host backpressure timeout surfaces as source_offline feedback', () async {
      final h = Harness(
        fetchTimeout: const Duration(seconds: 15),
        bufferedAmount: () => kMediaHighWatermark + 1,
      );
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.startRecv();
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
    });
  });
}

extension on List<Map<String, dynamic>> {
  /// Waits for a control message (the fetch is issued asynchronously).
  Future<Map<String, dynamic>> firstWhereAsync(bool Function(Map<String, dynamic>) test) async {
    for (var i = 0; i < 200; i++) {
      for (final m in this) {
        if (test(m)) return m;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('control message not observed');
  }
}

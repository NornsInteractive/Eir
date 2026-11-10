import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:eir/media/media_frames.dart';
import 'package:eir/media/media_limits.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fileBytes(int length, {int seed = 31}) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * seed + 7) % 251));

/// F1 regression harness: `onSourceAvailable(mediaId)` must fire ONLY after
/// `writeRange` successfully writes slice bytes, and never on offline,
/// cancel, or non-offline error paths. `RoomSession` clears `source_offline`
/// only when `_offlineMediaId == mediaId` AND the callback's `mediaId` is
/// still the current item's `localMediaId`, so these tests pin the
/// service-side contract those guards depend on.
class Harness {
  Harness({required this.fetchTimeout, required this.bufferedAmount})
      : offlineEvents = <String>[],
        availableEvents = <String>[],
        controlLog = <Map<String, dynamic>>[];

  final Duration fetchTimeout;
  final FutureOr<int> Function() bufferedAmount;
  final List<String> offlineEvents;
  final List<String> availableEvents;
  final List<Map<String, dynamic>> controlLog;
  final Set<int> dropRequestIds = <int>{};
  final Set<String> dropMediaIds = <String>{};
  bool dropAllBinary = false;

  late final Directory root;
  late final LocalMediaService source;
  late final LocalMediaService recv;

  Future<void> setUp() async {
    root = await Directory.systemTemp.createTemp('eir-available-');
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
      onSourceAvailable: availableEvents.add,
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

  Future<Uint8List> readViaWriteRange(String mediaId, int start, int end) async {
    final out = BytesBuilder(copy: false);
    await recv.writeRange(mediaId, start, end, (slice) async => out.add(slice));
    return out.toBytes();
  }
}

void main() {
  group('source_available (F1: bytes clear offline, nothing else may)', () {
    test('timeout failure fires offline and NEVER available', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 400), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.recv.start();
      h.dropAllBinary = true;
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      expect(h.availableEvents, isEmpty, reason: 'no bytes were written, must not signal available');
    });

    test('successful Range fires available with the same mediaId', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.recv.start();
      final bytes = await h.readViaWriteRange(manifest.mediaId, 0, 100);
      expect(bytes, fileBytes(700_000).sublist(0, 100));
      expect(h.offlineEvents, isEmpty);
      expect(h.availableEvents, [manifest.mediaId]);
      // Repeat load of the same media fires again (RoomSession treats
      // repeat as no-op clearing since _offlineMediaId is already null).
      final again = await h.readViaWriteRange(manifest.mediaId, 100, 200);
      expect(again, fileBytes(700_000).sublist(100, 200));
      expect(h.availableEvents, [manifest.mediaId, manifest.mediaId]);
    });

    test('offline then success: available arrives after offline (bytes clear offline)', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 400), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.recv.start();
      h.dropAllBinary = true;
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      expect(h.availableEvents, isEmpty);
      h.dropAllBinary = false;
      final bytes = await h.readViaWriteRange(manifest.mediaId, 0, 100);
      expect(bytes, fileBytes(700_000).sublist(0, 100));
      expect(h.availableEvents, [manifest.mediaId]);
      expect(h.offlineEvents, [manifest.mediaId], reason: 'success must not add a second offline event');
    });

    test('switched-away media success does not signal available for the current media', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final oldManifest = await h.addMedia(700_000, seed: 31);
      final currentManifest = await h.addMedia(700_000, seed: 47);
      expect(oldManifest.mediaId, isNot(currentManifest.mediaId));
      await h.recv.start();
      // Current media succeeds; old media never fetched. Available must
      // carry only the current id so RoomSession cannot clear an offline
      // stamp belonging to a different media.
      final currentBytes = await h.readViaWriteRange(currentManifest.mediaId, 0, 100);
      expect(currentBytes, fileBytes(700_000, seed: 47).sublist(0, 100));
      expect(h.availableEvents, [currentManifest.mediaId]);
      expect(h.availableEvents, isNot(contains(oldManifest.mediaId)));
      expect(h.offlineEvents, isEmpty);
    });

    test('old media offline + current media success stay attributed per-media', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 500), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final oldManifest = await h.addMedia(700_000, seed: 31);
      final currentManifest = await h.addMedia(700_000, seed: 47);
      await h.recv.start();
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
      expect(h.availableEvents, [currentManifest.mediaId],
          reason: 'old offline must not suppress current available, and vice versa');
    });

    test('peer cancel completes as offline and NEVER available', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.recv.start();
      h.dropAllBinary = true;
      final future = h.readViaWriteRange(manifest.mediaId, 0, 100);
      final request = await h.controlLog.firstWhereAsync((m) => m['type'] == 'media_range_request');
      h.recv.cancelRequest(request['requestId'] as int);
      await expectLater(
        future,
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      expect(h.availableEvents, isEmpty);
    });

    test('invalid_range fires NEITHER offline nor available', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.recv.start();
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 300_000, 300_100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'invalid_range')),
      );
      expect(h.offlineEvents, isEmpty);
      expect(h.availableEvents, isEmpty);
    });

    test('normal Range over loopback HTTP fires available (bridge path)', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.recv.start();
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
      expect(h.availableEvents, [manifest.mediaId]);
    });

    test('readRangeBytes (web hot path) fires available on success, offline on failure', () async {
      final h = Harness(fetchTimeout: const Duration(milliseconds: 400), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.recv.start();
      h.dropAllBinary = true;
      await expectLater(
        h.recv.readRangeBytes(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      expect(h.availableEvents, isEmpty);
      h.dropAllBinary = false;
      final bytes = await h.recv.readRangeBytes(manifest.mediaId, 0, 100);
      expect(bytes, fileBytes(700_000).sublist(0, 100));
      expect(h.availableEvents, [manifest.mediaId]);
    });

    test('host backpressure timeout fires offline and NEVER available', () async {
      final h = Harness(
        fetchTimeout: const Duration(seconds: 15),
        bufferedAmount: () => kMediaHighWatermark + 1,
      );
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(300_000);
      await h.recv.start();
      await expectLater(
        h.readViaWriteRange(manifest.mediaId, 0, 100),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'source_offline')),
      );
      expect(h.offlineEvents, [manifest.mediaId]);
      expect(h.availableEvents, isEmpty);
    });

    test('multi-chunk Range fires available per written slice (RoomSession clears on first bytes)', () async {
      final h = Harness(fetchTimeout: const Duration(seconds: 5), bufferedAmount: () => 0);
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia(700_000);
      await h.recv.start();
      // Two chunks: each successful writeRange slice signals available.
      final bytes = await h.readViaWriteRange(manifest.mediaId, 0, 200);
      expect(bytes.length, 200);
      expect(h.availableEvents, isNotEmpty);
      expect(h.availableEvents.every((id) => id == manifest.mediaId), isTrue);
      expect(h.offlineEvents, isEmpty);
    });
  });
}

extension on List<Map<String, dynamic>> {
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

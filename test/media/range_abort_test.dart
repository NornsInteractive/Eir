import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fileBytes(int length, {int seed = 17}) => Uint8List.fromList(List<int>.generate(length, (i) => (i * seed + 3) % 251));

const _fetchTimeout = Duration(milliseconds: 500);
const _httpTimeout = Duration(seconds: 6);
const _promptBound = Duration(seconds: 3);
const _fileLen = 700000;

/// HttpClient fetch outcome where body-phase errors are captured instead of
/// thrown, so abort-vs-success can be asserted deterministically. A silent
/// truncated success would be `error == null && bytes.length == expectedLen`.
class FetchOutcome {
  FetchOutcome({this.status, this.headers, required this.bytes, this.error});
  final int? status;
  final HttpHeaders? headers;
  final List<int> bytes;
  final Object? error;
  bool get isCompleteSuccess => error == null && status == 206;
}

Future<FetchOutcome> fetchLoopback(String url, {String method = 'GET', String? range}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(url);
    final req = method == 'HEAD' ? await client.openUrl('HEAD', uri) : await client.getUrl(uri);
    if (range != null) req.headers.set('Range', range);
    final res = await req.close().timeout(_httpTimeout);
    int? status = res.statusCode;
    final headers = res.headers;
    final bytes = <int>[];
    Object? error;
    try {
      await for (final chunk in res.timeout(_httpTimeout)) {
        bytes.addAll(chunk);
      }
    } catch (e) {
      error = e;
    }
    return FetchOutcome(status: status, headers: headers, bytes: bytes, error: error);
  } catch (e) {
    // Headers-or-even-connection level abort surfaces here.
    return FetchOutcome(bytes: <int>[], error: e);
  } finally {
    client.close(force: true);
  }
}

class Harness {
  Harness() : offlineEvents = <String>[], availableEvents = <String>[], controlLog = <Map<String, dynamic>>[];

  final List<String> offlineEvents;
  final List<String> availableEvents;
  final List<Map<String, dynamic>> controlLog;
  bool dropAllBinary = false;

  late final Directory root;
  late final LocalMediaService source;
  late final LocalMediaService recv;

  Future<void> setUp() async {
    root = await Directory.systemTemp.createTemp('eir-range-abort-');
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
      fetchTimeout: _fetchTimeout,
      onSourceOffline: offlineEvents.add,
      onSourceAvailable: availableEvents.add,
    );
  }

  Future<void> tearDown() async {
    await source.dispose();
    await recv.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<MediaManifest> addMedia({int length = _fileLen}) async {
    final manifest = await source.registerFile(
      XFile.fromData(fileBytes(length), name: 'abort.mp4', mimeType: 'video/mp4'),
      title: 'abort',
    );
    await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
    await recv.start();
    return manifest;
  }

  int rangeRequestCount() => controlLog.where((m) => m['type'] == 'media_range_request').length;
}

void main() {
  group('native range abort (HttpClient loopback)', () {
    test('HEAD/206/416 normal; server stays alive after abort', () async {
      final h = Harness();
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia();
      final url = h.recv.uriFor(manifest.mediaId);
      final expected = fileBytes(_fileLen);

      final headFull = await fetchLoopback(url, method: 'HEAD');
      expect(headFull.error, isNull, reason: 'HEAD must succeed');
      expect(headFull.status, 200);
      expect(headFull.headers?.value('content-length'), '$_fileLen');
      expect(headFull.bytes, isEmpty);

      final headRange = await fetchLoopback(url, method: 'HEAD', range: 'bytes=100-199');
      expect(headRange.error, isNull);
      expect(headRange.status, 206);
      expect(headRange.headers?.value('content-range'), 'bytes 100-199/$_fileLen');
      expect(headRange.headers?.value('content-length'), '100');
      expect(headRange.bytes, isEmpty);

      final range = await fetchLoopback(url, range: 'bytes=100-199');
      expect(range.error, isNull);
      expect(range.status, 206);
      expect(range.bytes, expected.sublist(100, 200));

      final tooFar = await fetchLoopback(url, range: 'bytes=$_fileLen-999999');
      expect(tooFar.error, isNull);
      expect(tooFar.status, 416);
      expect(tooFar.headers?.value('content-range'), 'bytes */$_fileLen');

      // Abort one GET, then HEAD/416 must still work (server not wedged).
      // Use an uncached chunk-1 offset: chunk 0 was cached by the 100-199 read above.
      h.dropAllBinary = true;
      final aborted = await fetchLoopback(url, range: 'bytes=500000-500099');
      expect(aborted.isCompleteSuccess, isFalse);
      h.dropAllBinary = false;
      final headAfter = await fetchLoopback(url, method: 'HEAD');
      expect(headAfter.error, isNull);
      expect(headAfter.status, 200);
      final badAfter = await fetchLoopback(url, range: 'bytes=$_fileLen-999999');
      expect(badAfter.status, 416);
    });

    test('fetch fails before first byte: client gets abort/truncation, bounded, then retry reads correct bytes', () async {
      final h = Harness();
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia();
      final url = h.recv.uriFor(manifest.mediaId);
      final expected = fileBytes(_fileLen).sublist(0, 1000);

      h.dropAllBinary = true;
      final sw = Stopwatch()..start();
      final aborted = await fetchLoopback(url, range: 'bytes=0-999');
      sw.stop();
      expect(sw.elapsed, lessThan(_promptBound), reason: 'abort must be prompt, not hang until client timeout');
      expect(aborted.isCompleteSuccess, isFalse, reason: 'aborted GET must not be silent success; status=${aborted.status} bytes=${aborted.bytes.length} err=${aborted.error}');
      expect(aborted.error != null || aborted.bytes.length != 1000, isTrue, reason: 'must observe truncation or error');
      expect(h.offlineEvents, contains(manifest.mediaId));
      expect(h.availableEvents, isEmpty, reason: 'no slice written => no available signal');
      final requestsAfterFail = h.rangeRequestCount();
      expect(requestsAfterFail, greaterThan(0));

      // Recovery: same Range must serve exact bytes and issue a fresh fetch (cleanup).
      h.dropAllBinary = false;
      final ok = await fetchLoopback(url, range: 'bytes=0-999');
      expect(ok.error, isNull, reason: 'retry after abort must succeed');
      expect(ok.status, 206);
      expect(ok.bytes, expected);
      expect(h.rangeRequestCount(), greaterThan(requestsAfterFail), reason: 'retry must send new range request after cleanup');
      expect(h.availableEvents, contains(manifest.mediaId));
    });

    test('fails after partial slice: client never sees complete Content-Length success, then recovery is exact', () async {
      final h = Harness();
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia();
      final url = h.recv.uriFor(manifest.mediaId);
      final expectedFull = fileBytes(_fileLen);

      // Warm chunk 0 so the next wide Range writes slice 1 from cache, then fails on chunk 1.
      final warm = await fetchLoopback(url, range: 'bytes=0-99');
      expect(warm.error, isNull);
      expect(warm.status, 206);
      expect(warm.bytes, expectedFull.sublist(0, 100));
      h.offlineEvents.clear();
      h.availableEvents.clear();

      h.dropAllBinary = true;
      // Spans cached chunk 0 (262144) + uncached chunk 1: writeRange emits chunk 0 then throws on chunk 1.
      final sw = Stopwatch()..start();
      final aborted = await fetchLoopback(url, range: 'bytes=0-399999');
      sw.stop();
      final elapsed = sw.elapsed;
      expect(aborted.isCompleteSuccess, isFalse, reason: 'partial-then-abort must not be silent success');
      expect(aborted.error != null || aborted.bytes.length != 400000, isTrue);
      expect(aborted.bytes.length, lessThan(400000), reason: 'client must not receive full 400k as success');
      expect(h.offlineEvents, contains(manifest.mediaId), reason: 'second-chunk failure must still report offline');

      h.dropAllBinary = false;
      final ok = await fetchLoopback(url, range: 'bytes=0-399999');
      expect(ok.error, isNull);
      expect(ok.status, 206);
      expect(ok.bytes, expectedFull.sublist(0, 400000));
      expect(elapsed, lessThan(_promptBound), reason: 'partial abort must be prompt, not hang until client timeout (elapsed $elapsed)');
    });

    test('concurrent same Range shares failure then cleans up: retry serves correct bytes', () async {
      final h = Harness();
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia();
      final url = h.recv.uriFor(manifest.mediaId);
      final expected = fileBytes(_fileLen).sublist(0, 1000);

      h.dropAllBinary = true;
      final sw = Stopwatch()..start();
      final both = await Future.wait([
        fetchLoopback(url, range: 'bytes=0-999'),
        fetchLoopback(url, range: 'bytes=0-999'),
      ]);
      sw.stop();
      expect(sw.elapsed, lessThan(_promptBound));
      for (final o in both) {
        expect(o.isCompleteSuccess, isFalse, reason: 'each concurrent waiter must observe abort/truncation');
        expect(o.error != null || o.bytes.length != 1000, isTrue);
      }

      h.dropAllBinary = false;
      final ok = await fetchLoopback(url, range: 'bytes=0-999');
      expect(ok.error, isNull);
      expect(ok.status, 206);
      expect(ok.bytes, expected);
      expect(h.recv.cacheTelemetry.cachedChunks, greaterThan(0), reason: 'successful retry must populate cache');
    });

    test('normal Range still serves 206 after failures (no latch, no poisoned Content-Length)', () async {
      final h = Harness();
      await h.setUp();
      addTearDown(h.tearDown);
      final manifest = await h.addMedia();
      final url = h.recv.uriFor(manifest.mediaId);
      final expected = fileBytes(_fileLen);
      h.dropAllBinary = true;
      final a = await fetchLoopback(url, range: 'bytes=0-999');
      expect(a.isCompleteSuccess, isFalse);
      h.dropAllBinary = false;
      final b = await fetchLoopback(url, range: 'bytes=500-599');
      expect(b.error, isNull);
      expect(b.status, 206);
      expect(b.headers?.value('content-range'), 'bytes 500-599/$_fileLen');
      expect(b.headers?.value('content-length'), '100');
      expect(b.bytes, expected.sublist(500, 600));
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:eir/media/media_limits.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fileBytes(int length) => Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + 7) % 251));

Future<({LocalMediaService source, LocalMediaService recv, Directory root, MediaManifest manifest})> pair(int length, {int? maxCacheBytes}) async {
  final root = await Directory.systemTemp.createTemp('eir-xfer-');
  final sourceDir = Directory('${root.path}/src');
  final recvDir = Directory('${root.path}/recv');
  await sourceDir.create();
  await recvDir.create();
  late LocalMediaService source;
  late LocalMediaService recv;
  source = LocalMediaService(
    sendControl: (m) => recv.onControl(m),
    sendBinary: (f) async => recv.onBinary(f),
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
    maxCacheBytes: maxCacheBytes ?? kMediaMaxCacheBytes,
  );
  final manifest = await source.registerFile(XFile.fromData(fileBytes(length), name: 'sample.mp4', mimeType: 'video/mp4'), title: 'sample');
  await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
  return (source: source, recv: recv, root: root, manifest: manifest);
}

Future<List<int>> getRange(HttpClient client, String url, String range) async {
  final req = await client.getUrl(Uri.parse(url));
  req.headers.set('Range', range);
  final res = await req.close();
  if (res.statusCode != 206) throw StateError('status ${res.statusCode}');
  return res.fold<List<int>>([], (a, b) => a..addAll(b));
}

void main() {
  group('transfer', () {
    test('only needed chunks transferred + seek tail', () async {
      final p = await pair(700_000);
      addTearDown(() async {
        await p.source.dispose();
        await p.recv.dispose();
        await p.root.delete(recursive: true);
      });
      await p.recv.start();
      final client = HttpClient();
      final body = await getRange(client, p.recv.uriFor(p.manifest.mediaId), 'bytes=100-199');
      expect(body.length, 100);
      expect(p.source.transferTelemetry.sentBytes, lessThan(700_000));
      final tail = await getRange(client, p.recv.uriFor(p.manifest.mediaId), 'bytes=699900-699999');
      expect(tail.length, 100);
      expect(tail, fileBytes(700_000).sublist(699900));
      client.close();
    });

    test('corrupt chunk rejected, never cached', () async {
      final root = await Directory.systemTemp.createTemp('eir-corrupt-');
      addTearDown(() => root.delete(recursive: true));
      final sourceDir = Directory('${root.path}/s');
      final recvDir = Directory('${root.path}/r');
      await sourceDir.create(recursive: true);
      await recvDir.create();
      final data = fileBytes(600_000);
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
    localDeviceId: 'c' * 64,
        cacheDir: sourceDir,
      );
      recv = LocalMediaService(sendControl: source.onControl, sendBinary: (f) async => source.onBinary(f), bufferedAmount: () => 0,
    localDeviceId: 'd' * 64, cacheDir: recvDir);
      final manifest = await source.registerFile(XFile.fromData(data, name: 'c.mp4', mimeType: 'video/mp4'));
      await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
      await recv.start();
      final client = HttpClient();
      var failed = false;
      try {
        final req = await client.getUrl(Uri.parse(recv.uriFor(manifest.mediaId)));
        req.headers.set('Range', 'bytes=0-99');
        final res = await req.close();
        // Corrupt frame bytes fail the chunk sha256; the bridge errors and
        // the chunk is never cached. Mid-stream failures surface as a
        // closed connection or an HTTP 500, both acceptable.
        if (res.statusCode != 206) failed = true;
        await res.fold<List<int>>([], (a, b) => a..addAll(b));
      } catch (_) {
        failed = true;
      }
      client.close();
      await source.dispose();
      await recv.dispose();
      expect(failed, isTrue);
      expect(recv.cacheTelemetry.cachedChunks, 0);
    });

    test('untrusted manifest denied without authorizer', () async {
      final root = await Directory.systemTemp.createTemp('eir-trust-');
      addTearDown(() => root.delete(recursive: true));
      final svc = LocalMediaService(sendControl: (_) {}, sendBinary: (_) async {}, bufferedAmount: () => 0,
    localDeviceId: 'e' * 64, cacheDir: root);
      final src = LocalMediaService(sendControl: (_) {}, sendBinary: (_) async {}, bufferedAmount: () => 0,
    localDeviceId: 'f' * 64, cacheDir: root);
      final manifest = await src.registerFile(XFile.fromData(fileBytes(1000), name: 't.mp4', mimeType: 'video/mp4'));
      expect(() => svc.registerRemoteManifest(manifest.toJson()), throwsA(isA<MediaException>()));
      await src.dispose();
      await svc.dispose();
    });

    test('out-of-range returns 416', () async {
      final p = await pair(300_000);
      addTearDown(() async {
        await p.source.dispose();
        await p.recv.dispose();
        await p.root.delete(recursive: true);
      });
      await p.recv.start();
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(p.recv.uriFor(p.manifest.mediaId)));
      req.headers.set('Range', 'bytes=999999-1000000');
      final res = await req.close();
      expect(res.statusCode, 416);
      client.close();
    });

    test('cancel pending request', () async {
      final p = await pair(700_000);
      addTearDown(() async {
        await p.source.dispose();
        await p.recv.dispose();
        await p.root.delete(recursive: true);
      });
      await p.recv.start();
      p.recv.cancelRequest(99999);
      final client = HttpClient();
      final body = await getRange(client, p.recv.uriFor(p.manifest.mediaId), 'bytes=0-99');
      expect(body.length, 100);
      client.close();
    });

    test('cache bound evicts unprotected', () async {
      final p = await pair(900_000, maxCacheBytes: 300_000);
      addTearDown(() async {
        await p.source.dispose();
        await p.recv.dispose();
        await p.root.delete(recursive: true);
      });
      await p.recv.start();
      final client = HttpClient();
      for (var c = 0; c < 4; c++) {
        final body = await getRange(client, p.recv.uriFor(p.manifest.mediaId), 'bytes=${c * 262144}-${c * 262144 + 99}');
        expect(body.length, 100);
      }
      client.close();
      expect(p.recv.cacheTelemetry.cachedBytes, lessThanOrEqualTo(300_000 + 262144));
    });
  });
}

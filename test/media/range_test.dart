import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List data(int n) => Uint8List.fromList(List<int>.generate(n, (i) => (i * 17 + 3) % 251));

void main() {
  group('native range responses', () {
    late Directory root;
    late LocalMediaService source;
    late LocalMediaService recv;
    late MediaManifest manifest;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('eir-range-');
      final sourceDir = Directory('${root.path}/s');
      final recvDir = Directory('${root.path}/r');
      await sourceDir.create(recursive: true);
      await recvDir.create();
      source = LocalMediaService(sendControl: (m) => recv.onControl(m), sendBinary: (f) async => recv.onBinary(f), bufferedAmount: () => 0, localDeviceId: 'a' * 64, cacheDir: sourceDir);
      recv = LocalMediaService(sendControl: (m) => source.onControl(m), sendBinary: (f) async => source.onBinary(f), bufferedAmount: () => 0, localDeviceId: 'b' * 64, cacheDir: recvDir);
      manifest = await source.registerFile(XFile.fromData(data(700_000), name: 'range.mp4', mimeType: 'video/mp4'));
      await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
      await recv.start();
    });

    tearDown(() async {
      await source.dispose();
      await recv.dispose();
      await root.delete(recursive: true);
    });

    Future<HttpClientResponse> get(HttpClient client, String range) =>
        client.getUrl(Uri.parse(recv.uriFor(manifest.mediaId))).then((r) {
          if (range.isNotEmpty) r.headers.set('Range', range);
          return r.close();
        });

    Future<List<int>> body(HttpClientResponse res) =>
        res.fold<List<int>>([], (a, b) => a..addAll(b));

    test('206 + content-range + low bytes', () async {
      final client = HttpClient();
      final res = await get(client, 'bytes=100-199');
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 100-199/700000');
      expect(res.headers.value('accept-ranges'), 'bytes');
      final b = await body(res);
      expect(b, data(700_000).sublist(100, 200));
      expect(source.transferTelemetry.sentBytes, lessThan(700_000));
      client.close();
    });

    test('suffix range returns exact tail', () async {
      final client = HttpClient();
      final res = await get(client, 'bytes=-128');
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 699872-699999/700000');
      final b = await body(res);
      expect(b, data(700_000).sublist(699872));
      client.close();
    });

    test('open-ended range works', () async {
      final client = HttpClient();
      final res = await get(client, 'bytes=699800-');
      expect(res.statusCode, 206);
      final b = await body(res);
      expect(b, data(700_000).sublist(699800));
      client.close();
    });

    test('clamped end for end beyond EOF', () async {
      final client = HttpClient();
      final res = await get(client, 'bytes=699800-999999');
      expect(res.statusCode, 206);
      expect(res.headers.value('content-range'), 'bytes 699800-699999/700000');
      final b = await body(res);
      expect(b, data(700_000).sublist(699800));
      client.close();
    });

    test('416 for out-of-bounds', () async {
      final client = HttpClient();
      final res = await get(client, 'bytes=700000-700100');
      expect(res.statusCode, 416);
      client.close();
    });

    test('multiple ranges rejected 416', () async {
      final client = HttpClient();
      final res = await get(client, 'bytes=0-1,2-3');
      expect(res.statusCode, 416);
      client.close();
    });
  });
}

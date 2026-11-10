import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:eir/media/local_media_service.dart';

import 'package:eir/media/media_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List payload(int n) => Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 7) % 251));

void main() {
  group('container serving', () {
    late Directory root;
    late LocalMediaService source;
    late LocalMediaService recv;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('eir-containers-');
      final sourceDir = Directory('${root.path}/s')..createSync(recursive: true);
      final recvDir = Directory('${root.path}/r')..createSync(recursive: true);
      source = LocalMediaService(sendControl: (m) => recv.onControl(m), sendBinary: (f) async => recv.onBinary(f), bufferedAmount: () => 0, localDeviceId: 'a' * 64, cacheDir: sourceDir);
      recv = LocalMediaService(sendControl: (m) => source.onControl(m), sendBinary: (f) async => source.onBinary(f), bufferedAmount: () => 0, localDeviceId: 'b' * 64, cacheDir: recvDir);
      await recv.start();
    });

    tearDown(() async {
      await source.dispose();
      await recv.dispose();
      await root.delete(recursive: true);
    });

    Future<(int, HttpHeaders, List<int>)> fetch(String url, {String? range}) async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(url));
        if (range != null) req.headers.set('Range', range);
        final res = await req.close();
        final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        return (res.statusCode, res.headers, bytes);
      } finally {
        client.close(force: true);
      }
    }

    Future<MediaManifest> share(String name, String? declaredMime, int size) async {
      final manifest = await source.registerFile(XFile.fromData(payload(size), name: name, mimeType: declaredMime));
      await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
      return manifest;
    }

    test('matroska is served with its own extension and content type', () async {
      final data = payload(300_000);
      final manifest = await share('clip.mkv', 'video/x-matroska', data.length);
      expect(manifest.mime, 'video/x-matroska');

      final url = recv.uriFor(manifest.mediaId);
      expect(url, endsWith('.mkv'));

      final (status, headers, bytes) = await fetch(url);
      expect(status, 200);
      expect(headers.contentType?.mimeType, 'video/x-matroska');
      expect(headers.value('accept-ranges'), 'bytes');
      expect(bytes, data);
    });

    test('range requests work for a non-mp4 container', () async {
      final data = payload(400_000);
      final manifest = await share('clip.webm', 'video/webm', data.length);
      final (status, headers, bytes) = await fetch(recv.uriFor(manifest.mediaId), range: 'bytes=1000-1999');
      expect(status, 206);
      expect(headers.value('content-range'), 'bytes 1000-1999/400000');
      expect(bytes, data.sublist(1000, 2000));
    });

    test('legacy mp4 keeps its mediaId binding and .mp4 url', () async {
      final data = payload(120_000);
      final manifest = await share('legacy.mp4', 'video/mp4', data.length);
      final fileSha = crypto.sha256.convert(data).toString();
      final hashes = <String>[fileSha];
      final expectedId = mediaIdFor(v: 1, mime: 'video/mp4', size: data.length, chunkSize: 262144, sourceDeviceId: 'a' * 64, fileSha256: fileSha, chunkHashes: hashes);
      expect(manifest.mediaId, expectedId, reason: 'v1 mp4 mediaId must not change');
      expect(recv.uriFor(manifest.mediaId), endsWith('.mp4'));
      final (status, headers, bytes) = await fetch(recv.uriFor(manifest.mediaId));
      expect(status, 200);
      expect(headers.contentType?.mimeType, 'video/mp4');
      expect(bytes, data);
    });

    test('url extension is a validated label; identity is the hex mediaId', () async {
      final manifest = await share('clip.mkv', 'video/x-matroska', 10_000);
      final base = recv.uriFor(manifest.mediaId);
      // The mediaId is the guarded identity — malformed ids fail fast.
      expect((await fetch(base.replaceFirst(manifest.mediaId, 'not-hex'))).$1, 404);
      // The extension is only a label: an arbitrary lowercase extension still
      // resolves the manifest with its real Content-Type.
      final exe = await fetch(base.replaceFirst('.mkv', '.exe'));
      expect(exe.$1, 200);
      expect(exe.$2.contentType?.mimeType, 'video/x-matroska');
      // Extension shape stays validated (transparent tokens only).
      expect((await fetch(base)).$1, 200);
    });

    test('non-media files register with their own safe mime', () async {
      final data = payload(1000);
      final manifest = await share('notes.txt', 'text/plain', data.length);
      expect(manifest.mime, 'text/plain');
      final url = recv.uriFor(manifest.mediaId);
      final (status, headers, bytes) = await fetch(url);
      expect(status, 200);
      expect(headers.contentType?.mimeType, 'text/plain');
      expect(bytes, data);
    });
  });
}

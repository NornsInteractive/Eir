import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:eir/media/media_cache_disk.dart';
import 'package:eir/media/media_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int n, int seed) => Uint8List.fromList(List<int>.generate(n, (i) => (seed * 31 + i) % 251));

void main() {
  setUp(() {
    budget.maxBytes = 512 * 1024 * 1024;
  });

  group('disk cache', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('eir-cache-test-');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('put/get/evict bounded and hash verified', () async {
      final cache = DiskChunkCache(mediaId: 'a' * 64, directory: Directory('${tmp.path}/mid'), chunkSize: 50, maxCacheBytes: 100);
      await cache.init();
      final b0 = bytes(50, 1);
      final b1 = bytes(50, 2);
      final b2 = bytes(50, 3);
      await cache.putChunk(0, b0, expectedSha256: crypto.sha256.convert(b0).toString());
      await cache.putChunk(1, b1, expectedSha256: crypto.sha256.convert(b1).toString());
      budget.maxBytes = 100;
      await cache.putChunk(2, b2, expectedSha256: crypto.sha256.convert(b2).toString());
      expect(budget.cachedBytes, lessThanOrEqualTo(100));
      expect(await cache.getChunk(0, expectedSha256: crypto.sha256.convert(b0).toString()), isNull);
      expect(await cache.getChunk(1, expectedSha256: crypto.sha256.convert(b1).toString()), isNotNull);
    });

    test('tampered disk chunk rejected', () async {
      final cache = DiskChunkCache(mediaId: 'd' * 64, directory: Directory('${tmp.path}/mid3'), chunkSize: 50, maxCacheBytes: 4096);
      await cache.init();
      final b0 = bytes(50, 4);
      await cache.putChunk(0, b0, expectedSha256: crypto.sha256.convert(b0).toString());
      final file = File('${tmp.path}/mid3/00000000.chunk');
      await file.writeAsBytes(Uint8List.fromList(b0)..[0] = b0[0] ^ 0xff);
      expect(await cache.getChunk(0, expectedSha256: crypto.sha256.convert(b0).toString()), isNull);
      expect(cache.telemetry.cachedBytes, 0);
    });

    test('protected playback window survives pressure', () async {
      final cache = DiskChunkCache(mediaId: 'b' * 64, directory: Directory('${tmp.path}/mid2'), chunkSize: 50, maxCacheBytes: 100);
      await cache.init();
      final b0 = bytes(50, 5);
      final b1 = bytes(50, 6);
      final b2 = bytes(50, 7);
      budget.maxBytes = 100;
      await cache.putChunk(0, b0, expectedSha256: crypto.sha256.convert(b0).toString());
      await cache.putChunk(1, b1, expectedSha256: crypto.sha256.convert(b1).toString());
      cache.protect(0);
      await cache.putChunk(2, b2, expectedSha256: crypto.sha256.convert(b2).toString());
      expect(await cache.getChunk(0, expectedSha256: crypto.sha256.convert(b0).toString()), isNotNull);
      expect(await cache.getChunk(1, expectedSha256: crypto.sha256.convert(b1).toString()), isNull);
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:eir/media/local_media_common.dart';
import 'package:eir/media/media_cache.dart';
import 'package:eir/media/media_cache_disk.dart';
import 'package:eir/media/media_limits.dart';
import 'package:eir/media/media_server_interface.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List chunkBytes(int n, int seed) => Uint8List.fromList(List<int>.generate(n, (i) => (seed * 31 + i) % 251));

/// Minimal host: these tests exercise the cache/serve path directly and never
/// bind a real HTTP server.
class _FakeHost implements MediaServerHost {
  @override
  String get baseUrl => '';
  @override
  String uriFor(String mediaId) => 'http://127.0.0.1:0/m/t/$mediaId.mp4';
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

/// Concrete test double over the shared service base so we can inject a
/// failing disk cache factory without a real platform service.
class _TestMediaService extends BaseLocalMediaService {
  _TestMediaService({
    required super.sendControl,
    required super.sendBinary,
    required super.localDeviceId,
    super.manifestAuthorizer,
    super.cacheFactory,
    super.onStorageError,
  }) : super(
          bufferedAmount: () => 0,
          serverHostFactory: ({required MediaWriteRange writeRange, required MediaReadRangeBytes readRangeBytes, required MediaManifestLookup manifestFor, required String token}) => _FakeHost(),
        );
}

void main() {
  setUp(() {
    budget.maxBytes = 512 * 1024 * 1024;
    MediaStorageState.reset();
  });

  group('disk storage full', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('eir-storage-');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('ENOSPC stops new writes, keeps valid chunks, cleans temp, is recognizable', () async {
      var fail = false;
      var writes = 0;
      final cache = DiskChunkCache(
        mediaId: 'a' * 64,
        directory: Directory('${tmp.path}/mid'),
        chunkSize: 50,
        maxCacheBytes: 1 << 20,
        writeChunkFile: (file, bytes) async {
          writes++;
          if (fail) {
            throw FileSystemException('No space left on device', file.path, const OSError('No space left on device', 28));
          }
          await file.writeAsBytes(bytes, flush: true);
        },
      );
      await cache.init();
      addTearDown(cache.clear);

      final b0 = chunkBytes(50, 1);
      final b1 = chunkBytes(50, 2);
      final b2 = chunkBytes(50, 3);
      final h0 = crypto.sha256.convert(b0).toString();
      final h1 = crypto.sha256.convert(b1).toString();
      final h2 = crypto.sha256.convert(b2).toString();

      await cache.putChunk(0, b0, expectedSha256: h0);
      expect(cache.cachedBytes, 50);
      expect(await cache.getChunk(0, expectedSha256: h0), isNotNull);

      // Disk fills up: the next write fails with a real ENOSPC.
      fail = true;
      await expectLater(
        cache.putChunk(1, b1, expectedSha256: h1),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'storage_full')),
      );
      // Valid chunk 0 untouched, temp file cleaned, bytes not counted.
      expect(await cache.getChunk(0, expectedSha256: h0), isNotNull);
      expect(cache.cachedBytes, 50);
      expect(File('${tmp.path}/mid/.tmp1').existsSync(), isFalse);
      expect(MediaStorageState.blocked, isTrue);
      expect(MediaStorageState.lastCode, 'storage_full');

      // While blocked, further puts must not touch the disk at all.
      final writesBeforeBlocked = writes;
      await expectLater(
        cache.putChunk(2, b2, expectedSha256: h2),
        throwsA(isA<MediaException>().having((e) => e.code, 'code', 'storage_full')),
      );
      expect(writes, writesBeforeBlocked);
      expect(File('${tmp.path}/mid/.tmp2').existsSync(), isFalse);

      // Recovery: after the user frees space, writes resume.
      MediaStorageState.reset();
      fail = false;
      await cache.putChunk(2, b2, expectedSha256: h2);
      expect(cache.cachedBytes, 100);
      expect(await cache.getChunk(2, expectedSha256: h2), isNotNull);
      expect(MediaStorageState.blocked, isFalse);
    });

    test('init cleans stale temp files', () async {
      final dir = Directory('${tmp.path}/stale');
      await dir.create(recursive: true);
      final stale = File('${dir.path}/.tmp7');
      await stale.writeAsBytes([1, 2, 3]);
      final cache = DiskChunkCache(mediaId: 'b' * 64, directory: dir, chunkSize: 50, maxCacheBytes: 1 << 20);
      await cache.init();
      addTearDown(cache.clear);
      expect(stale.existsSync(), isFalse);
      expect(cache.cachedBytes, 0);
    });

    test('isStorageFullError recognizes POSIX/Windows codes and messages', () {
      expect(isStorageFullError(FileSystemException('x', '', const OSError('No space left on device', 28))), isTrue);
      expect(isStorageFullError(FileSystemException('x', '', const OSError('Disk quota exceeded', 122))), isTrue);
      expect(isStorageFullError(FileSystemException('x', '', const OSError('There is not enough space on the disk', 112))), isTrue);
      expect(isStorageFullError(FileSystemException('There is not enough space on the disk', '')), isTrue);
      expect(isStorageFullError(FileSystemException('Permission denied', '', const OSError('Permission denied', 13))), isFalse);
      expect(isStorageFullError(StateError('nope')), isFalse);
    });

    test('service serves verified bytes from memory on storage_full, reports code, recovers', () async {
      final srcDir = Directory('${tmp.path}/src');
      final recvDir = Directory('${tmp.path}/recv');
      await srcDir.create();
      await recvDir.create();

      var fail = false;
      late DiskChunkCache recvCache;
      String? reported;

      late _TestMediaService source;
      late _TestMediaService recv;
      source = _TestMediaService(
        sendControl: (m) => recv.onControl(m),
        sendBinary: (f) async => recv.onBinary(f),
        localDeviceId: 'a' * 64,
      );
      recv = _TestMediaService(
        sendControl: (m) => source.onControl(m),
        sendBinary: (f) async => source.onBinary(f),
        localDeviceId: 'b' * 64,
        manifestAuthorizer: (_) async => true,
        onStorageError: (code) => reported = code,
        cacheFactory: (id, manifest) async {
          recvCache = DiskChunkCache(
            mediaId: id,
            directory: Directory('${recvDir.path}/$id'),
            chunkSize: manifest.chunkSize,
            maxCacheBytes: 1 << 20,
            writeChunkFile: (file, bytes) async {
              if (fail) {
                throw FileSystemException('No space left on device', file.path, const OSError('No space left on device', 28));
              }
              await file.writeAsBytes(bytes, flush: true);
            },
          );
          await recvCache.init();
          return recvCache;
        },
      );

      final data = Uint8List.fromList(List<int>.generate(600 * 1024, (i) => (i * 17 + 3) % 251));
      final manifest = await source.registerFile(XFile.fromData(data, name: 's.mp4', mimeType: 'video/mp4'));
      await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);

      // Chunk 0 caches normally.
      final c0 = await recv.ensureChunk(manifest.mediaId, 0);
      expect(c0.length, manifest.chunkLength(0));
      expect(recvCache.cachedBytes, greaterThan(0));

      // Disk full: chunk 1 must still be served (from memory), not thrown.
      fail = true;
      final c1 = await recv.ensureChunk(manifest.mediaId, 1);
      expect(c1, data.sublist(manifest.chunkSize, manifest.chunkSize + manifest.chunkLength(1)));
      expect(reported, 'storage_full');
      expect(recv.lastStorageErrorCode, 'storage_full');
      expect(recv.cacheTelemetry.lastStorageErrorCode, 'storage_full');
      // Valid chunk 0 kept; chunk 1 was not persisted.
      expect(await recvCache.getChunk(0, expectedSha256: manifest.chunkHashes[0]), isNotNull);
      expect(recvCache.hasChunk(1), isFalse);

      // Cleanup frees space and clears the latch + reported code.
      await recv.clearUnprotectedCache();
      expect(recv.lastStorageErrorCode, isNull);
      expect(MediaStorageState.blocked, isFalse);

      fail = false;
      final c1b = await recv.ensureChunk(manifest.mediaId, 1);
      expect(c1b.length, manifest.chunkLength(1));
      expect(recvCache.hasChunk(1), isTrue);

      await source.dispose();
      await recv.dispose();
    });
  });
}

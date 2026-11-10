import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List fileBytes(int length) => Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + 7) % 251));

Future<({LocalMediaService source, LocalMediaService recv, Directory root, MediaManifest manifest})> pair(int length) async {
  final root = await Directory.systemTemp.createTemp('eir-clear-');
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
    manifestAuthorizer: (_) async => true,
  );
  final manifest = await source.registerFile(XFile.fromData(fileBytes(length), name: 'clear.mp4', mimeType: 'video/mp4'));
  await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
  return (source: source, recv: recv, root: root, manifest: manifest);
}

void main() {
  group('clearUnprotectedCache', () {
    test('removes all idle cached chunks', () async {
      final p = await pair(700_000);
      addTearDown(() async {
        await p.source.dispose();
        await p.recv.dispose();
        await p.root.delete(recursive: true);
      });
      await p.recv.ensureChunk(p.manifest.mediaId, 0);
      await p.recv.ensureChunk(p.manifest.mediaId, 1);
      expect(p.recv.cacheTelemetry.cachedChunks, 2);
      final freed = await p.recv.clearUnprotectedCache();
      expect(freed, greaterThan(0));
      expect(p.recv.cacheTelemetry.cachedBytes, 0);
      expect(p.recv.cacheTelemetry.cachedChunks, 0);
      expect(p.recv.manifestFor(p.manifest.mediaId), isNotNull);
      final before = p.source.transferTelemetry.sentBytes;
      await p.recv.ensureChunk(p.manifest.mediaId, 0);
      expect(p.source.transferTelemetry.sentBytes, greaterThan(before));
    });

    test('keeps active playback window and evicts idle chunks', () async {
      final p = await pair(700_000);
      addTearDown(() async {
        await p.source.dispose();
        await p.recv.dispose();
        await p.root.delete(recursive: true);
      });
      // writeRange/protect marks chunk 0 for playback; chunk 1 is idle.
      await p.recv.readRangeBytes(p.manifest.mediaId, 0, 100);
      await p.recv.ensureChunk(p.manifest.mediaId, 1);
      expect(p.recv.cacheTelemetry.cachedChunks, 2);
      final freed = await p.recv.clearUnprotectedCache();
      expect(freed, greaterThan(0));
      expect(p.recv.cacheTelemetry.cachedChunks, 1);
      final before = p.source.transferTelemetry.sentBytes;
      await p.recv.readRangeBytes(p.manifest.mediaId, 0, 100);
      expect(p.source.transferTelemetry.sentBytes, before);
      await p.recv.ensureChunk(p.manifest.mediaId, 1);
      expect(p.source.transferTelemetry.sentBytes, greaterThan(before));
    });
  });
}

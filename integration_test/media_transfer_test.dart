import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:eir/media/local_media_service.dart';
import 'package:eir/media_validation.dart';

class TestPair {
  TestPair({required this.source, required this.recv, required this.root, required this.manifest, required this.bytes});
  final LocalMediaService source;
  final LocalMediaService recv;
  final Directory root;
  final MediaManifest manifest;
  final int bytes;

  Future<void> dispose() async {
    await source.dispose();
    await recv.dispose();
    await root.delete(recursive: true);
  }
}

Future<File> ensureFixture() async {
  const fixturePath = '/tmp/eir-media-fixture.mp4';
  final fixture = File(fixturePath);
  if (!await fixture.exists()) {
    final result = await Process.run('/home/dev/.local/bin/ffmpeg', [
      '-y',
      '-f', 'lavfi',
      '-i', 'testsrc2=size=320x240:rate=30',
      '-f', 'lavfi',
      '-i', 'sine=frequency=440',
      '-t', '20',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-crf', '18',
      '-pix_fmt', 'yuv420p',
      '-g', '15',
      '-c:a', 'aac',
      fixturePath,
    ]);
    if (result.exitCode != 0 || !await fixture.exists()) {
      throw StateError('unable to generate multi-chunk MP4 fixture with ffmpeg: ${result.stderr}');
    }
  }
  return fixture;
}

Future<TestPair> makePair() async {
  final fixture = await ensureFixture();
  final bytes = await fixture.readAsBytes();
  final dir = await Directory.systemTemp.createTemp('eir-media-it-');
  final srcDir = Directory('${dir.path}/src');
  final recvDir = Directory('${dir.path}/recv');
  await srcDir.create();
  await recvDir.create();

  late LocalMediaService source;
  late LocalMediaService recv;
  source = LocalMediaService(
    sendControl: (m) => recv.onControl(m),
    sendBinary: (f) async => recv.onBinary(f),
    bufferedAmount: () => 0,
    localDeviceId: 'a' * 64,
    cacheDir: srcDir,
  );
  recv = LocalMediaService(
    sendControl: (m) => source.onControl(m),
    sendBinary: (f) async => source.onBinary(f),
    bufferedAmount: () => 0,
    localDeviceId: 'b' * 64,
    cacheDir: recvDir,
    manifestAuthorizer: (_) async => true,
  );
  final manifest = await source.registerFile(XFile(fixture.path), title: 'multi-chunk');
  await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
  await recv.start();
  expect(bytes.length, greaterThan(3_000_000));
  expect(manifest.chunkCount, greaterThan(1));
  return TestPair(source: source, recv: recv, root: dir, manifest: manifest, bytes: bytes.length);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P2P streamed original multi-chunk MP4 before full download', (tester) async {
    final p = await makePair();
    try {
      final probe = await probeMediaPlayback(uri: p.recv.uriFor(p.manifest.mediaId), play: true, timeout: const Duration(seconds: 30));
      debugPrint(probe.toString());
      debugPrint('media-sent=${p.source.transferTelemetry.sentBytes} full=${p.bytes} cachedBytes=${p.recv.cacheTelemetry.cachedBytes}');
      expect(probe.success, isTrue);
      expect(probe.duration, isNotNull);
      expect(p.source.transferTelemetry.sentBytes, lessThan(p.bytes));
      expect(p.recv.cacheTelemetry.cachedChunks, greaterThan(0));
    } finally {
      await p.dispose();
    }
  });

  testWidgets('P2P receiver seeks into MP4 tail (moov-at-end fixture)', (tester) async {
    final p = await makePair();
    try {
      MediaKit.ensureInitialized();
      final player = Player();
      try {
        final errors = <String>[];
        player.stream.error.listen((e) => errors.add(e));
        await player.open(Media(p.recv.uriFor(p.manifest.mediaId)));
        final openStart = DateTime.now();
        while (player.state.duration == Duration.zero && DateTime.now().difference(openStart) < const Duration(seconds: 20)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(player.state.duration.inSeconds, greaterThan(10));
        await player.seek(const Duration(seconds: 18));
        final seekStart = DateTime.now();
        while (player.state.position < const Duration(seconds: 17) && DateTime.now().difference(seekStart) < const Duration(seconds: 20)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        debugPrint('tail-position=${player.state.position} media-sent=${p.source.transferTelemetry.sentBytes} errors=$errors');
        expect(errors, isEmpty);
        expect(player.state.position, greaterThan(const Duration(seconds: 17)));
        expect(p.source.transferTelemetry.sentBytes, lessThan(p.bytes));
      } finally {
        try {
          await player.dispose();
        } catch (_) {}
      }
    } finally {
      await p.dispose();
    }
  });
}

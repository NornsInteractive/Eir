import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Real LocalMediaService chunked-manifest tests only.
//
// The four earlier cases in this file were invalid regressions and are
// deleted: three copied `if` / CommitChain logic without calling
// RoomSession, and one asserted on room_session.dart source text. Their
// behaviours (snapshot vs commit, leave/rejoin old-await isolation, large
// manifest late autoplay) are covered instead by real two-client
// RoomSession tests in
// integration_test/room_session_session_manifest_timing_test.dart
// (Linux harness, real Player/WebRTC/signaling). Stale-snapshot replay
// and queued-task races that cannot be injected through the public API
// are honestly marked unproven in the regression report, not faked here.

void main() {
  group('LocalMediaService chunked manifest (real service)', () {
    test('large manifest travels chunked; only final chunk installs', () async {
      final outgoing = <Map<String, dynamic>>[];
      final source = LocalMediaService(
        sendControl: outgoing.add,
        sendBinary: (_) async {},
        bufferedAmount: () => 0,
        localDeviceId: 'a' * 64,
      );
      final receiver = LocalMediaService(
        sendControl: (_) {},
        sendBinary: (_) async {},
        bufferedAmount: () => 0,
        localDeviceId: 'b' * 64,
        manifestAuthorizer: (_) async => true,
      );
      final dir = await Directory.systemTemp.createTemp('eir-reg-');
      addTearDown(() async {
        await source.dispose();
        await receiver.dispose();
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final f = await _largeFile(dir, 65 * 1024 * 1024);
      final manifest = await source.registerFile(f);
      final bytes = utf8.encode(jsonEncode(manifest.toJson()));
      // Snapshot inline threshold is 16000 (add_local inline threshold is
      // 8192). A 40 MiB file's manifest can still fit under 16000 and ride
      // inline in a snapshot, so the fixture must exceed 16000 to prove
      // the chunked path for both thresholds.
      expect(
        bytes.length,
        greaterThan(16000),
        reason: 'fixture manifestJSON ${bytes.length} must exceed the '
            '16000 snapshot inline threshold (not just 8192)',
      );
      expect(bytes.length, greaterThan(_Thresholds.addLocal),
          reason: 'chunked fixture must also exceed the add_local threshold');

      await source.writeManifestChunksFor(manifest.mediaId, maxChunkBytes: 700);
      expect(outgoing.length, greaterThan(1));

      MediaManifest? installed;
      for (var i = 0; i < outgoing.length; i++) {
        final got = await receiver.handleManifestChunk(outgoing[i]);
        if (i < outgoing.length - 1) {
          expect(got, isNull, reason: 'only last chunk installs');
        } else {
          installed = got;
        }
      }
      expect(installed, isNotNull);
      expect(installed!.mediaId, manifest.mediaId);
      expect(receiver.manifestFor(manifest.mediaId)?.mediaId, manifest.mediaId);
    });

    test('unauthorized chunked manifest is rejected and not installed',
        () async {
      final outgoing = <Map<String, dynamic>>[];
      final source = LocalMediaService(
        sendControl: outgoing.add,
        sendBinary: (_) async {},
        bufferedAmount: () => 0,
        localDeviceId: 'a' * 64,
      );
      final receiver = LocalMediaService(
        sendControl: (_) {},
        sendBinary: (_) async {},
        bufferedAmount: () => 0,
        localDeviceId: 'b' * 64,
        manifestAuthorizer: (_) async => false,
      );
      final dir = await Directory.systemTemp.createTemp('eir-reg-');
      addTearDown(() async {
        await source.dispose();
        await receiver.dispose();
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      final f = await _largeFile(dir, 65 * 1024 * 1024);
      final manifest = await source.registerFile(f);
      final bytes = utf8.encode(jsonEncode(manifest.toJson()));
      expect(
        bytes.length,
        greaterThan(16000),
        reason: 'fixture manifestJSON ${bytes.length} must exceed the '
            '16000 snapshot inline threshold (not just 8192)',
      );
      await source.writeManifestChunksFor(manifest.mediaId, maxChunkBytes: 700);
      expect(outgoing.length, greaterThan(1));

      Object? thrown;
      for (final c in outgoing) {
        try {
          await receiver.handleManifestChunk(c);
        } catch (e) {
          thrown = e;
        }
      }
      expect(thrown, isNotNull);
      expect(thrown.toString(), contains('untrusted_manifest'));
      expect(receiver.manifestFor(manifest.mediaId), isNull);
    });
  });
}

class _Thresholds {
  static const int addLocal = 8 * 1024;
}

Future<XFile> _largeFile(Directory dir, int sizeBytes) async {
  final f = File('${dir.path}/a.mp4');
  final sink = f.openWrite();
  final chunk = Uint8List(1024 * 1024);
  var remaining = sizeBytes;
  while (remaining > 0) {
    final n = remaining > chunk.length ? chunk.length : remaining;
    sink.add(n == chunk.length ? chunk : chunk.sublist(0, n));
    remaining -= n;
  }
  await sink.close();
  return XFile(f.path);
}

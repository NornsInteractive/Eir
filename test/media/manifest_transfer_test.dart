import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'package:eir/media/local_media_service.dart';
import 'package:eir/media/media_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('small manifest fits one chunk', () async {
    final chunks = <Map<String, dynamic>>[];
    final source = LocalMediaService(sendControl: chunks.add, sendBinary: (_) async {}, bufferedAmount: () => 0, localDeviceId: 'a' * 64);
    final file = await source.registerFile(await _TempMp4.file10KB());
    await source.writeManifestChunksFor(file.mediaId);
    expect(chunks.length, greaterThanOrEqualTo(1));
    expect(chunks.every((c) => c['type'] == 'media_manifest_chunk'), isTrue);
    expect(chunks.every((c) => (c['bytesB64'] as String).length < base64Encode(List<int>.filled(kMediaManifestChunkBytes, 0)).length + 8), isTrue);
    await source.dispose();
  });

  test('manifest chunk roundtrip bounded and verified', () async {
    final outgoing = <Map<String, dynamic>>[];
    late LocalMediaService source;
    // use minimal source created before tmp exists to get id
    source = LocalMediaService(sendControl: outgoing.add, sendBinary: (_) async {}, bufferedAmount: () => 0, localDeviceId: 'a' * 64);
    final f = await source.registerFile(await _TempMp4.file3MB());
    await source.writeManifestChunksFor(f.mediaId, maxChunkBytes: 700);
    expect(outgoing.length, greaterThan(1));
    final incoming = <Map<String, dynamic>>[];
    final receiver = LocalMediaService(sendControl: incoming.add, sendBinary: (_) async {}, bufferedAmount: () => 0, localDeviceId: 'b' * 64, manifestAuthorizer: (_) async => true);
    MediaManifest? parsed;
    for (final c in outgoing) {
      parsed = await receiver.handleManifestChunk(c);
    }
    expect(parsed, isNotNull);
    expect(parsed!.mediaId, f.mediaId);
    await source.dispose();
    await receiver.dispose();
  });

  test('chunked manifest rejects oversize head', () async {
    final receiver = LocalMediaService(sendControl: (_) {}, sendBinary: (_) async {}, bufferedAmount: () => 0, localDeviceId: 'b' * 64, manifestAuthorizer: (_) async => true);
    expect(() => receiver.beginManifestTransfer({'transferId': 't', 'mediaId': 'x', 'totalBytes': kMediaMaxManifestBytes + 1, 'total': 1, 'manifestSha256': 'a' * 64}), throwsA(isA<MediaException>()));
    await receiver.dispose();
  });
}

class _TempMp4 {
  static Future<dynamic> file10KB() async {
    // Minimal dummy file will be rejected by manifest size/chunks? Manifest hashes okay even for arbitrary bytes; just test transfer.
    final dir = await Directory.systemTemp.createTemp('eir-mf10k-');
    final f = File('${dir.path}/a.mp4');
    await f.writeAsBytes(Uint8List(10 * 1024));
    return XFile(f.path);
  }

  static Future<dynamic> file3MB() async {
    final dir = await Directory.systemTemp.createTemp('eir-mf3mb-');
    final f = File('${dir.path}/a.mp4');
    await f.writeAsBytes(Uint8List(3 * 1024 * 1024));
    return XFile(f.path);
  }
}

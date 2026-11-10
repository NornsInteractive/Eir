import 'dart:typed_data';

import 'package:eir/media/media_manifest.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int n) => Uint8List.fromList(List<int>.generate(n, (i) => i % 251));

void main() {
  group('manifest', () {
    test('round-trip + mediaId binding', () async {
      final data = bytes(300_000);
      final hashes = <String>[];
      for (var off = 0; off < data.length; off += 262144) {
        final end = (off + 262144).clamp(0, data.length);
        hashes.add(crypto.sha256.convert(Uint8List.sublistView(data, off, end)).toString());
      }
      final fileSha = crypto.sha256.convert(data).toString();
      final mediaId = mediaIdFor(v: 1, mime: 'video/mp4', size: data.length, chunkSize: 262144, sourceDeviceId: 'a' * 64, fileSha256: fileSha, chunkHashes: hashes);
      final m = MediaManifest(mediaId: mediaId, sourceDeviceId: 'a' * 64, fileSha256: fileSha, mime: 'video/mp4', size: data.length, chunkSize: 262144, chunkHashes: hashes, title: 't');
      final parsed = MediaManifest.fromJson(m.toJson());
      expect(parsed.mediaId, mediaId);
      expect(parsed.chunkCount, 2);
      expect(parsed.chunkLength(1), data.length - 262144);
      expect(parsed.chunkOffset(1), 262144);
    });

    test('tampered hash rejected', () {
      try {
        MediaManifest.fromJson(<String, dynamic>{'v': 1, 'mediaId': '0' * 64, 'sourceDeviceId': 'a' * 64, 'fileSha256': 'b' * 64, 'mime': 'video/mp4', 'size': 100, 'chunkSize': 262144, 'chunkCount': 1, 'chunkHashes': ['c' * 64]});
        fail('should throw');
      } catch (e) {
        expect(e.toString(), contains('invalid_manifest'));
      }
    });

    test('safe non-video mimes accepted; unsafe and non-canonical mime rejected', () {
      final mkId = mediaIdFor(v: 1, mime: 'video/x-matroska', size: 100, chunkSize: 262144, sourceDeviceId: 'a' * 64, fileSha256: 'b' * 64, chunkHashes: ['c' * 64]);
      final mk = MediaManifest.fromJson(<String, dynamic>{'v': 1, 'mediaId': mkId, 'sourceDeviceId': 'a' * 64, 'fileSha256': 'b' * 64, 'mime': 'video/x-matroska', 'size': 100, 'chunkSize': 262144, 'chunkCount': 1, 'chunkHashes': ['c' * 64]});
      expect(mk.mime, 'video/x-matroska');

      // Safe types are accepted — the octet-stream fallback is a legal manifest
      // value and the player decides playability.
      for (final mime in <String>['text/plain', 'application/octet-stream']) {
        final mId = mediaIdFor(v: 1, mime: mime, size: 100, chunkSize: 262144, sourceDeviceId: 'a' * 64, fileSha256: 'b' * 64, chunkHashes: ['c' * 64]);
        final m = MediaManifest.fromJson(<String, dynamic>{'v': 1, 'mediaId': mId, 'sourceDeviceId': 'a' * 64, 'fileSha256': 'b' * 64, 'mime': mime, 'size': 100, 'chunkSize': 262144, 'chunkCount': 1, 'chunkHashes': ['c' * 64]});
        expect(m.mime, mime);
      }

      // MIME security validation: active-document types are never servable.
      for (final mime in <String>['text/html', 'image/svg+xml', 'application/xhtml+xml', 'application/javascript', 'text/html ', 'video/mp4; codecs=avc1', 'VIDEO/WEBM', 'garbage mime']) {
        try {
          MediaManifest.fromJson(<String, dynamic>{'v': 1, 'mediaId': mkId, 'sourceDeviceId': 'a' * 64, 'fileSha256': 'b' * 64, 'mime': mime, 'size': 100, 'chunkSize': 262144, 'chunkCount': 1, 'chunkHashes': ['c' * 64]});
          fail('should throw for $mime');
        } catch (e) {
          expect(e.toString(), contains('unsupported_media'), reason: mime);
        }
      }
    });

    test('legacy v1 mp4 manifest still validates', () {
      final m = MediaManifest.fromJson(<String, dynamic>{
        'v': 1,
        'mediaId': mediaIdFor(v: 1, mime: 'video/mp4', size: 100, chunkSize: 262144, sourceDeviceId: 'a' * 64, fileSha256: 'b' * 64, chunkHashes: ['c' * 64]),
        'sourceDeviceId': 'a' * 64,
        'fileSha256': 'b' * 64,
        'mime': 'video/mp4',
        'size': 100,
        'chunkSize': 262144,
        'chunkCount': 1,
        'chunkHashes': ['c' * 64],
      });
      expect(m.mime, 'video/mp4');
    });

    test('wrong chunkSize rejected', () {
      try {
        MediaManifest.fromJson(<String, dynamic>{'v': 1, 'mediaId': 'd' * 64, 'sourceDeviceId': 'a' * 64, 'fileSha256': 'b' * 64, 'mime': 'video/mp4', 'size': 999999, 'chunkSize': 1024, 'chunkCount': 1, 'chunkHashes': ['c' * 64]});
        fail('should throw');
      } catch (e) {
        expect(e.toString(), contains('unsupported_media'));
      }
    });
  });
}

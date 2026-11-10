import 'dart:typed_data';

import 'package:eir/media/media_format.dart';
import 'package:eir/media/media_limits.dart' show MediaException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mime/mime.dart';

/// `01 00 00 20 66 74 79 70` + brand 'isom' — MP4 ftyp box.
final Uint8List mp4Header = Uint8List.fromList(
  [0x00, 0x00, 0x00, 0x20] + ['f', 't', 'y', 'p', 'i', 's', 'o', 'm'].map((c) => c.codeUnitAt(0)).toList(),
);

/// EBML magic an MKV file starts with.
final Uint8List ebmlHeader = Uint8List.fromList(
  [0x1a, 0x45, 0xdf, 0xa3, 0, 1, 2, 3, 4, 5, 6, 7],
);

void main() {
  group('media format detection', () {
    test('extension lookup resolves known names', () {
      const expected = <String, String>{
        'clip.mp4': 'video/mp4',
        'clip.MP4': 'video/mp4',
        'clip.m4v': 'video/x-m4v',
        'clip.mov': 'video/quicktime',
        'clip.mkv': 'video/x-matroska',
        'clip.webm': 'video/webm',
        'clip.avi': 'video/x-msvideo',
        'clip.ts': 'video/mp2t',
        'clip.3gp': 'video/3gpp',
        'clip.ogv': 'video/ogg',
        'clip.flv': 'video/x-flv',
        'notes.txt': 'text/plain',
        'clip.pdf': 'application/pdf',
      };
      expected.forEach((name, mime) {
        expect(
          resolveMediaMime(magicMime: null, declaredMime: null, fileName: name),
          mime,
          reason: name,
        );
      });
    });

    test('magic numbers win over the file name', () {
      expect(
        resolveMediaMime(magicMime: lookupMimeType('clip.bin', headerBytes: mp4Header), declaredMime: null, fileName: 'notes.txt'),
        'video/mp4',
      );
      expect(
        resolveMediaMime(magicMime: lookupMimeType('clip.bin', headerBytes: ebmlHeader), declaredMime: null, fileName: 'notes.bin'),
        'audio/weba',
      );
    });

    test('EBML magic is corrected to matroska/webm when the name says so', () {
      expect(
        resolveMediaMime(magicMime: lookupMimeType('clip.mkv', headerBytes: ebmlHeader), declaredMime: null, fileName: 'clip.mkv'),
        'video/x-matroska',
      );
      expect(
        resolveMediaMime(magicMime: lookupMimeType('clip.mkv', headerBytes: ebmlHeader), declaredMime: null, fileName: 'clip.webm'),
        'video/webm',
      );
      expect(
        resolveMediaMime(magicMime: lookupMimeType('clip.mkv', headerBytes: ebmlHeader), declaredMime: 'video/x-matroska', fileName: 'clip.bin'),
        'video/x-matroska',
      );
    });

    test('declared mime wins over extension and is normalized', () {
      expect(
        resolveMediaMime(magicMime: null, declaredMime: 'video/x-matroska', fileName: 'clip.bin'),
        'video/x-matroska',
      );
      expect(
        resolveMediaMime(magicMime: null, declaredMime: 'VIDEO/WEBM', fileName: 'clip.bin'),
        'video/webm',
      );
      expect(
        resolveMediaMime(magicMime: null, declaredMime: 'video/mp4; codecs=avc1', fileName: 'clip.bin'),
        'video/mp4',
      );
    });

    test('a redundant declared octet-stream falls back to name lookup', () {
      expect(
        resolveMediaMime(magicMime: null, declaredMime: 'application/octet-stream', fileName: 'clip.mkv'),
        'video/x-matroska',
      );
    });

    test('unclassifiable files register as octet-stream', () {
      expect(
        resolveMediaMime(magicMime: null, declaredMime: null, fileName: 'archive.zip'),
        'application/zip',
      );
      expect(
        resolveMediaMime(magicMime: null, declaredMime: 'application/zip', fileName: 'no_extension'),
        'application/zip',
      );
      expect(resolveMediaMime(magicMime: null, declaredMime: null, fileName: 'no_extension'), 'application/octet-stream');
      expect(
        resolveMediaMime(magicMime: null, declaredMime: 'garbage mime', fileName: 'no_extension'),
        'application/octet-stream',
      );
    });

    test('unsafe types are rejected at registration', () {
      for (final (declared, name) in [('text/html', 'clip.bin'), (null, 'page.html'), ('image/svg+xml', 'a.svg')]) {
        expect(
          () => resolveMediaMime(magicMime: null, declaredMime: declared, fileName: name),
          throwsA(predicate((e) => e is MediaException && e.code == 'unsupported_media')),
          reason: '$declared/$name',
        );
      }
    });

    test('every resolved mime is servable by Content-Type security rules', () {
      expect(isValidManifestMediaMime('video/mp4'), isTrue);
      expect(isValidManifestMediaMime('application/octet-stream'), isTrue);
      expect(isValidManifestMediaMime('text/plain'), isTrue);
      expect(isValidManifestMediaMime('audio/weba'), isTrue);
      expect(isValidManifestMediaMime('text/html'), isFalse);
      expect(isValidManifestMediaMime('image/svg+xml'), isFalse);
      expect(isValidManifestMediaMime('application/javascript'), isFalse);
      expect(isValidManifestMediaMime('video/mp4; codecs=avc1'), isFalse);
      expect(isValidManifestMediaMime('VIDEO/WEBM'), isFalse);
      expect(isValidManifestMediaMime('not a mime'), isFalse);
      expect(isValidManifestMediaMime(null), isFalse);
    });

    test('url extension compatibility: legacy mp4 default preserved', () {
      expect(mediaExtensionForMime('video/mp4'), 'mp4');
      expect(mediaExtensionForMime('video/x-matroska'), 'mkv');
      expect(mediaExtensionForMime('video/ogg'), 'ogv');
      expect(mediaExtensionForMime('application/octet-stream'), 'mp4');
      expect(mediaExtensionForMime('video/mpeg'), 'mpg');
      expect(mediaExtensionForMime('application/x-unknown'), 'mp4');
    });
  });
}

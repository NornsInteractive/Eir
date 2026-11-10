import 'package:eir/core/url_probe_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HLS playlist classification (F2)', () {
    test('non-m3u body is rejected', () {
      final v = classifyHlsPlaylist('<html>not a playlist</html>');
      expect(v.isAllowed, isFalse);
      expect(v.code, 'unsupported_media');
    });

    test('VOD media playlist (EXT-X-ENDLIST, no key) is allowed', () {
      const body = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg0.ts
#EXTINF:10.0,
seg1.ts
#EXT-X-ENDLIST
''';
      final v = classifyHlsPlaylist(body);
      expect(v.isAllowed, isTrue);
    });

    test('live media playlist (no ENDLIST) is rejected', () {
      const body = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg0.ts
''';
      final v = classifyHlsPlaylist(body);
      expect(v.isAllowed, isFalse);
      expect(v.code, 'unsupported_media');
    });

    test('encrypted (AES-128) playlist is rejected (DRM)', () {
      const body = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:10.0,
seg0.ts
#EXT-X-ENDLIST
''';
      final v = classifyHlsPlaylist(body);
      expect(v.isAllowed, isFalse);
      expect(v.code, 'unsupported_media');
    });

    test('SAMPLE-AES playlist is rejected (DRM)', () {
      const body = '''
#EXTM3U
#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI="skd://abc"
#EXT-X-STREAM-INF:BANDWIDTH=1
v.m3u8
''';
      final v = classifyHlsPlaylist(body);
      expect(v.isAllowed, isFalse);
    });

    test('METHOD=NONE key is not treated as encryption', () {
      const body = '''
#EXTM3U
#EXT-X-KEY:METHOD=NONE
#EXTINF:10.0,
seg0.ts
#EXT-X-ENDLIST
''';
      final v = classifyHlsPlaylist(body);
      expect(v.isAllowed, isTrue);
    });

    test('master playlist follows first variant (depth 0 -> follow)', () {
      const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000
high/index.m3u8
''';
      final v = classifyHlsPlaylist(body, baseUri: Uri.parse('https://h.example.com/a/'));
      expect(v.followUri, isNotNull);
      expect(
        v.followUri.toString(),
        'https://h.example.com/a/low/index.m3u8',
      );
    });

    test('master playlist with non-http variant is rejected (SSRF guard)', () {
      const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000
file:///etc/passwd
''';
      final v = classifyHlsPlaylist(body, baseUri: Uri.parse('https://h.example.com/'));
      expect(v.isAllowed, isFalse);
      expect(v.code, 'unsupported_media');
    });

    test('master at depth 1 is rejected (no unbounded recursion)', () {
      const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000
nested.m3u8
''';
      final v = classifyHlsPlaylist(body, depth: 1);
      expect(v.isAllowed, isFalse);
      expect(v.code, 'unsupported_media');
    });
  });

  group('probeMediaUrl scheme policy (F2)', () {
    test('rejects non-http(s) scheme without network', () async {
      final r = await probeMediaUrl('file:///tmp/x.mp4');
      expect(r, 'unsupported_media');
    });
    test('rejects garbage url without network', () async {
      final r = await probeMediaUrl('not a url');
      expect(r, 'unsupported_media');
    });
  });
}

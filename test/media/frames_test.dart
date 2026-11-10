import 'dart:typed_data';

import 'package:eir/media/media_frames.dart';
import 'package:eir/media/media_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frames', () {
    test('round-trip with offset > 4 GiB and requestId high bit', () {
      final mediaId = 'ef' * 32;
      const offset = 4294967449;
      final frame = MediaFrame(requestId: 4294967295, mediaId: mediaId, offset: offset, payload: Uint8List.fromList([9, 8, 7]));
      final encoded = frame.encode(maxMessageBytes: kMediaMaxMessageBytes);
      final decoded = MediaFrame.decode(encoded, expectedMediaId: mediaId, rangeStart: offset, rangeEnd: offset + 3);
      expect(decoded.offset, offset);
      expect(decoded.requestId, 4294967295);

      // Big-endian high/low Uint32 words: no dart2js setUint64.
      final bd = ByteData.view(encoded.buffer);
      expect(bd.getUint32(39, Endian.big), greaterThan(0));
      expect((bd.getUint32(39, Endian.big) * 4294967296 + bd.getUint32(43, Endian.big)), offset);
    });

    test('round-trip', () {
      final mediaId = 'ab' * 32;
      final frame = MediaFrame(requestId: 42, mediaId: mediaId, offset: 262144, payload: Uint8List.fromList([1, 2, 3, 4]));
      final encoded = frame.encode(maxMessageBytes: kMediaMaxMessageBytes);
      expect(encoded.length, lessThanOrEqualTo(kMediaMaxMessageBytes));
      final decoded = MediaFrame.decode(encoded, expectedMediaId: mediaId, rangeStart: 262144, rangeEnd: 262148);
      expect(decoded.requestId, 42);
      expect(decoded.mediaId, mediaId);
      expect(decoded.offset, 262144);
      expect(decoded.payload, [1, 2, 3, 4]);
    });

    test('short + bad magic rejected', () {
      expect(() => MediaFrame.decode(Uint8List(10)), throwsA(isA<MediaException>()));
      final bad = Uint8List(50)..[0] = 0;
      expect(() => MediaFrame.decode(bad), throwsA(isA<MediaException>()));
    });

    test('out-of-range offset rejected', () {
      final mediaId = 'cd' * 32;
      final encoded = MediaFrame(requestId: 1, mediaId: mediaId, offset: 9999, payload: Uint8List.fromList([7])).encode(maxMessageBytes: kMediaMaxMessageBytes);
      expect(() => MediaFrame.decode(encoded, expectedMediaId: mediaId, rangeStart: 0, rangeEnd: 100), throwsA(isA<MediaException>()));
    });

    test('wrong media rejected', () {
      final encoded = MediaFrame(requestId: 1, mediaId: 'aa' * 32, offset: 0, payload: Uint8List.fromList([7])).encode(maxMessageBytes: kMediaMaxMessageBytes);
      expect(() => MediaFrame.decode(encoded, expectedMediaId: 'bb' * 32), throwsA(isA<MediaException>()));
    });

    test('oversize rejected', () {
      final big = Uint8List(kMediaMaxMessageBytes + 1);
      expect(() => MediaFrame.decode(big), throwsA(isA<MediaException>()));
    });
  });
}

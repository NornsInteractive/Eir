import 'dart:typed_data';

import 'media_limits.dart';
import 'media_manifest.dart';

const int kFrameHeaderLen = 47;
const int kFrameTypeMedia = 0;

class MediaFrame {
  MediaFrame({required this.requestId, required this.mediaId, required this.offset, required this.payload});

  final int requestId;
  final String mediaId;
  final int offset;
  final Uint8List payload;

  Uint8List encode({required int maxMessageBytes}) {
    if (maxMessageBytes <= kFrameHeaderLen) throw MediaException('invalid_range', 'message too small');
    if (payload.length > maxMessageBytes - kFrameHeaderLen) {
      throw MediaException('invalid_range', 'payload too large');
    }
    final out = Uint8List(kFrameHeaderLen + payload.length);
    final bd = ByteData.view(out.buffer);
    out[0] = 0x45;
    out[1] = 0x4D;
    out[2] = kFrameTypeMedia;
    bd.setUint32(3, requestId % 4294967296, Endian.big);
    out.setRange(7, 39, hexToBytes(mediaId));
    setUint64BigEndian(bd, 39, offset);
    out.setRange(kFrameHeaderLen, out.length, payload);
    return out;
  }

  static MediaFrame decode(Uint8List msg, {String? expectedMediaId, int? rangeStart, int? rangeEnd}) {
    if (msg.length < kFrameHeaderLen) throw MediaException('invalid_range', 'short frame');
    if (msg.length > kMediaMaxMessageBytes) throw MediaException('invalid_range', 'frame too large');
    if (msg[0] != 0x45 || msg[1] != 0x4D || msg[2] != kFrameTypeMedia) {
      throw MediaException('invalid_range', 'bad magic');
    }
    final bd = ByteData.view(msg.buffer, msg.offsetInBytes);
    final requestId = bd.getUint32(3, Endian.big);
    final mediaIdBytes = msg.sublist(7, 39);
    final mediaId = mediaIdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final offset = getUint64BigEndian(bd, 39);
    final payload = Uint8List.fromList(msg.sublist(kFrameHeaderLen));
    if (expectedMediaId != null && mediaId != expectedMediaId) {
      throw MediaException('invalid_range', 'mediaId mismatch');
    }
    if (rangeStart != null && rangeEnd != null) {
      if (offset < rangeStart || offset + payload.length > rangeEnd) {
        throw MediaException('invalid_range', 'offset out of range');
      }
    }
    return MediaFrame(requestId: requestId, mediaId: mediaId, offset: offset, payload: payload);
  }
}

const int _uint32Range = 4294967296;

void setUint64BigEndian(ByteData bd, int byteOffset, int value) {
  if (value < 0 || value > kMediaMaxFileBytes) throw MediaException('invalid_range', 'file offset out of range');
  final high = value ~/ _uint32Range;
  final low = value % _uint32Range;
  bd.setUint32(byteOffset, high, Endian.big);
  bd.setUint32(byteOffset + 4, low, Endian.big);
}

int getUint64BigEndian(ByteData bd, int byteOffset) {
  final high = bd.getUint32(byteOffset, Endian.big);
  if (high > kMediaMaxFileBytes ~/ _uint32Range + 1) throw MediaException('invalid_range', 'file offset out of range');
  final low = bd.getUint32(byteOffset + 4, Endian.big);
  return high * _uint32Range + low;
}

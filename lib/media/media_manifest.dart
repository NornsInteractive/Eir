import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'media_format.dart';
import 'media_limits.dart';

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _hexChars = RegExp(r'^[0-9a-f]*$');

bool isHex64(String? s) => s != null && _hex64.hasMatch(s);

String mediaIdFor({
  required int v,
  required String mime,
  required int size,
  required int chunkSize,
  required String sourceDeviceId,
  required String fileSha256,
  required List<String> chunkHashes,
}) {
  final binding = 'eir-media-manifest/v1|'
      '${[v, mime, size, chunkSize, sourceDeviceId, fileSha256, chunkHashes.join(',')].join('|')}';
  return crypto.sha256.convert(utf8.encode(binding)).toString();
}

class MediaManifest {
  MediaManifest({
    required this.mediaId,
    required this.sourceDeviceId,
    required this.fileSha256,
    required this.mime,
    required this.size,
    required this.chunkSize,
    required this.chunkHashes,
    this.title,
  });

  final String mediaId;
  final String sourceDeviceId;
  final String fileSha256;
  final String mime;
  final int size;
  final int chunkSize;
  final List<String> chunkHashes;
  final String? title;

  int get chunkCount => chunkHashes.length;
  int chunkOffset(int index) => index * chunkSize;
  int chunkLength(int index) {
    final start = chunkOffset(index);
    if (start >= size) throw ArgumentError('chunk index out of range');
    final remain = size - start;
    return remain < chunkSize ? remain : chunkSize;
  }

  int get totalChunks => (size + chunkSize - 1) ~/ chunkSize;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': kMediaVersion,
        'mediaId': mediaId,
        'sourceDeviceId': sourceDeviceId,
        'fileSha256': fileSha256,
        'mime': mime,
        'size': size,
        'chunkSize': chunkSize,
        'chunkCount': chunkHashes.length,
        'chunkHashes': chunkHashes,
        if (title != null) 'title': title,
      };

  static MediaManifest fromJson(Map<String, dynamic> j) {
    final v = j['v'];
    if (v != kMediaVersion) throw MediaException('invalid_manifest', 'bad v');
    final mediaId = j['mediaId'];
    final sourceDeviceId = j['sourceDeviceId'];
    final fileSha256 = j['fileSha256'];
    final mime = j['mime'];
    final size = j['size'];
    final chunkSize = j['chunkSize'];
    final chunkCount = j['chunkCount'];
    final hashesRaw = j['chunkHashes'];
    if (!isHex64(mediaId is String ? mediaId : null) ||
        !isHex64(sourceDeviceId is String ? sourceDeviceId : null) ||
        !isHex64(fileSha256 is String ? fileSha256 : null)) {
      throw MediaException('invalid_manifest', 'bad hash field');
    }
    if (mime is! String ||
        normalizeMediaMime(mime) != mime ||
        !isValidManifestMediaMime(mime)) {
      throw MediaException('unsupported_media', 'mime');
    }
    if (size is! int || size <= 0 || size > kMediaMaxFileBytes) {
      throw MediaException('unsupported_media', 'size');
    }
    if (chunkSize != kMediaChunkSize) {
      throw MediaException('unsupported_media', 'chunkSize');
    }
    if (hashesRaw is! List) throw MediaException('invalid_manifest', 'hashes');
    final hashes = <String>[];
    for (final h in hashesRaw) {
      if (h is! String || !_hex64.hasMatch(h)) {
        throw MediaException('invalid_manifest', 'chunk hash');
      }
      hashes.add(h);
    }
    if (chunkCount is! int) throw MediaException('invalid_manifest', 'chunkCount');
    final expected = (size + chunkSize - 1) ~/ chunkSize;
    if (hashes.length != expected || chunkCount != expected) {
      throw MediaException('invalid_manifest', 'chunk count mismatch');
    }
    if (expected > kMediaMaxManifestChunks) {
      throw MediaException('unsupported_media', 'too many chunks');
    }
    final title = j['title'];
    if (title != null && (title is! String || title.length > 512)) {
      throw MediaException('invalid_manifest', 'title');
    }
    final computed = mediaIdFor(
      v: v,
      mime: mime,
      size: size,
      chunkSize: chunkSize,
      sourceDeviceId: sourceDeviceId,
      fileSha256: fileSha256,
      chunkHashes: hashes,
    );
    if (computed != mediaId) throw MediaException('invalid_manifest', 'mediaId');
    return MediaManifest(
      mediaId: mediaId,
      sourceDeviceId: sourceDeviceId,
      fileSha256: fileSha256,
      mime: mime,
      size: size,
      chunkSize: chunkSize,
      chunkHashes: hashes,
      title: title as String?,
    );
  }
}

List<int> hexToBytes(String hex) {
  if (hex.length % 2 != 0 || !_hexChars.hasMatch(hex)) {
    throw MediaException('invalid_manifest', 'bad hex');
  }
  final out = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

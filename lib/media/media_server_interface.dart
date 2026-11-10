import 'media_manifest.dart';

abstract class MediaServerHost {
  String get baseUrl;
  String uriFor(String mediaId);
  Future<void> start();
  Future<void> stop();
}

typedef MediaWriteRange = Future<void> Function(String mediaId, int start, int end, Future<void> Function(List<int> slice) write);
typedef MediaManifestLookup = MediaManifest? Function(String mediaId);
typedef MediaReadRangeBytes = Future<List<int>> Function(String mediaId, int start, int end);

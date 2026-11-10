import 'media_server_interface.dart';

MediaServerHost createMediaServerHost({
  required MediaWriteRange writeRange,
  required MediaReadRangeBytes readRangeBytes,
  required MediaManifestLookup manifestFor,
  required String token,
}) {
  throw UnsupportedError('media server not available on this platform');
}

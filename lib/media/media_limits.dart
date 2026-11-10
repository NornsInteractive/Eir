const int kMediaChunkSize = 262144;
const int kMediaMaxMessageBytes = 16384;
const int kMediaMaxFileBytes = 8 * 1024 * 1024 * 1024;
const int kMediaMaxManifestChunks = 32768;
const int kMediaMaxCacheBytes = 512 * 1024 * 1024;
const int kMediaHighWatermark = 256 * 1024;
const int kMediaMaxRangeBytes = 8 * 1024 * 1024;
const Duration kMediaFetchTimeout = Duration(seconds: 30);
const int kMediaMaxPendingRequests = 16;
const String kMediaMime = 'video/mp4';
const int kMediaVersion = 1;

class MediaException implements Exception {
  MediaException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'MediaException($code${message != null ? ': $message' : ''})';
}

const int kMediaManifestChunkBytes = 12000;
const int kMediaMaxManifestBytes = 4 * 1024 * 1024;

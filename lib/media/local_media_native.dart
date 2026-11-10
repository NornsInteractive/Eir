import 'dart:io';

import 'media_cache_disk.dart';
import 'media_cache.dart';
import 'media_server_host.dart';
import 'media_server_interface.dart';
import 'local_media_common.dart';

export 'local_media_common.dart'
    show MediaControlSender, MediaBinarySender, MediaBufferedAmount, MediaMaxMessageBytes, MediaManifestAuthorizer, MediaRequestAuthorizer, MediaTransferTelemetry, MediaCacheTelemetrySnapshot;
export 'media_manifest.dart' show MediaManifest;
export 'media_limits.dart' show kMediaMaxCacheBytes;
export 'media_cache.dart' show MediaCacheBudget;

class LocalMediaService extends BaseLocalMediaService {
  LocalMediaService({
    required super.sendControl,
    required super.sendBinary,
    required super.bufferedAmount,
    required super.localDeviceId,
    super.maxMessageBytes,
    super.manifestAuthorizer,
    super.requestAuthorizer,
    Directory? cacheDir,
    super.maxCacheBytes,
    super.fetchTimeout,
    super.sessionToken,
    super.onStorageError,
    super.onSourceOffline,
    super.onSourceAvailable,
  }) : super(
          serverHostFactory: ({required MediaWriteRange writeRange, required MediaReadRangeBytes readRangeBytes, required MediaManifestLookup manifestFor, required String token}) => createMediaServerHost(writeRange: writeRange, readRangeBytes: readRangeBytes, manifestFor: manifestFor, token: token),
          cacheFactory: cacheDir == null ? null : (mediaId, manifest) async => _diskCache(mediaId, manifest, cacheDir),
        );

  static Future<DiskChunkCache> _diskCache(String mediaId, MediaManifest manifest, Directory root) async {
    final dir = Directory('${root.path}${Platform.pathSeparator}$mediaId');
    if (!await dir.exists()) await dir.create(recursive: true);
    final cache = DiskChunkCache(mediaId: mediaId, directory: dir, chunkSize: manifest.chunkSize, maxCacheBytes: budget.maxBytes);
    await cache.init();
    return cache;
  }
}

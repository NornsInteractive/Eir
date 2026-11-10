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
    super.maxCacheBytes,
    super.fetchTimeout,
    super.sessionToken,
    super.onStorageError,
    super.onSourceOffline,
    super.onSourceAvailable,
  }) : super(
          serverHostFactory: ({required MediaWriteRange writeRange, required MediaReadRangeBytes readRangeBytes, required MediaManifestLookup manifestFor, required String token}) => createMediaServerHost(writeRange: writeRange, readRangeBytes: readRangeBytes, manifestFor: manifestFor, token: token),
        );
}

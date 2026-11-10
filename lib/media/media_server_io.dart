import 'dart:io';

import 'media_format.dart';
import 'media_limits.dart';
import 'media_manifest.dart' show isHex64;
import 'media_server_interface.dart';

MediaServerHost createMediaServerHost({
  required MediaWriteRange writeRange,
  required MediaReadRangeBytes readRangeBytes,
  required MediaManifestLookup manifestFor,
  required String token,
}) {
  return _NativeHost(writeRange: writeRange, manifestFor: manifestFor, token: token);
}

final RegExp _uExtension = RegExp(r'^[a-z0-9]{1,16}$');

class _NativeHost implements MediaServerHost {
  _NativeHost({required this.writeRange, required this.manifestFor, required this.token});

  final MediaWriteRange writeRange;
  final MediaManifestLookup manifestFor;
  final String token;
  HttpServer? _server;

  @override
  String get baseUrl => _server == null ? '' : 'http://127.0.0.1:${_server!.port}/';

  @override
  String uriFor(String mediaId) {
    final mime = manifestFor(mediaId)?.mime ?? kMediaMime;
    return 'http://127.0.0.1:${_server!.port}/m/$token/$mediaId.${mediaExtensionForMime(mime)}';
  }

  @override
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = 405;
        await res.close();
        return;
      }
      final parts = req.uri.pathSegments;
      if (parts.length != 3 || parts[0] != 'm' || parts[1] != token) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      final segment = parts[2];
      final dot = segment.lastIndexOf('.');
      if (dot <= 0) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      final mediaId = segment.substring(0, dot);
      final extension = segment.substring(dot + 1).toLowerCase();
      // The extension is a URL label (address compatibility keeps the legacy
      // `.mp4` default); identity is the hex mediaId above. Only the shape is
      // validated so no mime-derived extension can ever be rejected.
      if (!isHex64(mediaId) || !_uExtension.hasMatch(extension)) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      final manifest = manifestFor(mediaId);
      if (manifest == null) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      final size = manifest.size;
      final rangeHeader = req.headers.value('range');
      final ranged = parseSingleRange(rangeHeader, size);
      if (ranged == null) {
        res.statusCode = 416;
        res.headers.set('Content-Range', 'bytes */$size');
        res.headers.set('Content-Length', '0');
        await res.close();
        return;
      }
      final (start, endExclusive, isPartial) = ranged;
      res.statusCode = isPartial ? 206 : 200;
      res.headers.set('Accept-Ranges', 'bytes');
      res.headers.set('Content-Type', manifest.mime);
      res.headers.set('Cache-Control', 'no-store');
      res.headers.set('Content-Length', '${endExclusive - start}');
      if (isPartial) res.headers.set('Content-Range', 'bytes $start-${endExclusive - 1}/$size');
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await writeRange(mediaId, start, endExclusive, (slice) async {
        res.add(slice);
        await res.flush();
      });
      await res.flush();
      await res.close();
    } catch (e) {
      try {
        // Range headers may already advertise the full body. Abort a
        // failed transfer rather than presenting a truncated success.
        res.done.ignore();
        res.deadline = Duration.zero;
      } catch (_) {}
      return;
    }
  }
}

(int, int, bool)? parseSingleRange(String? header, int size) {
  if (header == null || header.isEmpty) return (0, size, false);
  if (!header.startsWith('bytes=')) return null;
  final spec = header.substring(6);
  if (spec.contains(',')) return null;
  final dash = spec.indexOf('-');
  if (dash < 0) return null;
  final a = spec.substring(0, dash);
  final b = spec.substring(dash + 1);
  if (a.isEmpty && b.isEmpty) return null;
  if (a.isEmpty) {
    final suffix = int.tryParse(b);
    if (suffix == null || suffix <= 0) return null;
    final start = (size - suffix).clamp(0, size);
    return (start, size, true);
  }
  final start = int.tryParse(a);
  if (start == null || start < 0 || start >= size) return null;
  final endExclusive = b.isEmpty ? size : ((int.tryParse(b) ?? -1) + 1).clamp(0, size);
  if (endExclusive <= start || endExclusive > size) return null;
  return (start, endExclusive, true);
}

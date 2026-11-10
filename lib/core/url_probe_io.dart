import 'dart:convert';
import 'dart:io';

/// Result of classifying an HLS playlist body.
class HlsVerdict {
  const HlsVerdict._(this.code, this.followUri);
  /// Allowed: VOD (on-demand) playlist, no encryption.
  static const HlsVerdict allowed = HlsVerdict._(null, null);
  /// Rejected with [code] (live, DRM, malformed, unresolvable master…).
  factory HlsVerdict.rejected(String code) => HlsVerdict._(code, null);
  /// Follow [followUri] (master playlist variant), bounded by the caller.
  factory HlsVerdict.follow(Uri uri) => HlsVerdict._(null, uri);

  final String? code;
  final Uri? followUri;
  bool get isAllowed => code == null && followUri == null;
}

const int _kMaxPlaylistBytes = 64 * 1024;

/// Probes [url] with a bounded ranged GET and validates it as a VOD media
/// source. Returns null on success, or a stable error code on rejection.
///
/// Enforces the HTTPS / loopback-HTTP policy (callers also enforce this).
/// HTML pages, live HLS, encrypted/DRM HLS and unreachable hosts are
/// rejected. HLS detection is by content-type or `.m3u8` extension; the
/// playlist is then classified (VOD vs master vs live vs DRM) with bounded
/// recursion into master variants.
Future<String?> probeMediaUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'media_probe_failed';
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'unsupported_media';
  }
  final client = HttpClient();
  client.userAgent = 'Eir/1.0';
  client.connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
    final response =
        await request.close().timeout(const Duration(seconds: 8));
    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      await response.drain<void>();
      return 'media_probe_failed';
    }
    final contentType = response.headers.contentType?.mimeType.toLowerCase();
    if (contentType == 'text/html' || contentType == 'application/xhtml+xml') {
      await response.drain<void>();
      // A web page served where a media file was expected.
      return 'unsupported_media';
    }
    await response.drain<void>();
    final isHlsType = contentType == 'application/vnd.apple.mpegurl' ||
        contentType == 'application/x-mpegurl' ||
        contentType == 'application/mpegurl' ||
        contentType == 'audio/mpegurl';
    final isHlsExt = uri.path.toLowerCase().endsWith('.m3u8');
    if (isHlsType || isHlsExt) {
      return _probeHls(uri, depth: 0);
    }
    // Non-HLS media (e.g. MP4) is accepted; playability is surfaced later by
    // the player's async error stream (see F1).
    return null;
  } catch (_) {
    return 'media_probe_failed';
  } finally {
    client.close(force: true);
  }
}

/// Fetches the playlist (bounded) and classifies it, following master
/// variants at most one level deep to avoid infinite recursion / SSRF via
/// alias chains.
Future<String?> _probeHls(Uri uri, {required int depth}) async {
  var current = uri;
  var currentDepth = depth;
  // Bounded loop: depth grows only on master->variant follow, capped at 1.
  while (currentDepth <= 1) {
    final body = await _fetchBounded(current, _kMaxPlaylistBytes);
    if (body == null) return 'media_probe_failed';
    final verdict = classifyHlsPlaylist(body, baseUri: current, depth: currentDepth);
    if (verdict.isAllowed) return null;
    if (verdict.followUri != null) {
      current = verdict.followUri!;
      currentDepth += 1;
      continue;
    }
    return verdict.code;
  }
  return 'unsupported_media';
}

/// Pure classifier for an HLS playlist body. Exposed for unit testing.
///
/// - Missing `#EXTM3U` → rejected (`unsupported_media`).
/// - Any `#EXT-X-KEY`/`#EXT-X-SESSION-KEY` with a non-NONE METHOD → rejected
///   (DRM / encryption unsupported).
/// - Master playlist (`#EXT-X-STREAM-INF`): follows the first resolvable
///   http(s) variant (returns a `follow` verdict); if none resolves → rejected.
/// - Media playlist without `#EXT-X-ENDLIST` → rejected (live, not VOD).
/// - Media playlist with `#EXT-X-ENDLIST` and no encryption → allowed.
HlsVerdict classifyHlsPlaylist(String body, {Uri? baseUri, int depth = 0}) {
  if (!body.contains('#EXTM3U')) return HlsVerdict.rejected('unsupported_media');
  if (_hasEncryptedKey(body)) return HlsVerdict.rejected('unsupported_media');
  final isMaster = body.contains('#EXT-X-STREAM-INF');
  if (isMaster) {
    if (depth >= 1) return HlsVerdict.rejected('unsupported_media');
    final variant = _firstVariantUri(body, baseUri);
    if (variant == null) return HlsVerdict.rejected('unsupported_media');
    return HlsVerdict.follow(variant);
  }
  final isVod = body.contains('#EXT-X-ENDLIST');
  if (!isVod) return HlsVerdict.rejected('unsupported_media'); // live
  return HlsVerdict.allowed;
}

bool _hasEncryptedKey(String body) {
  final keyRe = RegExp(r'#EXT-X-(?:SESSION-)?KEY:([^\r\n]*)');
  for (final m in keyRe.allMatches(body)) {
    final method = _attr(m.group(1) ?? '', 'METHOD');
    if (method != null && method.toUpperCase() != 'NONE') return true;
  }
  return false;
}

Uri? _firstVariantUri(String body, Uri? baseUri) {
  final lines = body.split(RegExp(r'[\r\n]+'));
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    for (var j = i + 1; j < lines.length; j++) {
      final cand = lines[j].trim();
      if (cand.isEmpty || cand.startsWith('#')) continue;
      return _resolveUri(baseUri, cand);
    }
  }
  return null;
}

Uri? _resolveUri(Uri? base, String raw) {
  // Only http/https are followed, preventing SSRF via file:// or other schemes.
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme == 'http' || uri.scheme == 'https') return uri;
    if (uri.scheme.isEmpty && base != null) return base.resolve(raw);
  } catch (_) {}
  return null;
}

String? _attr(String attrs, String key) {
  final m = RegExp('$key=([^,]+)').firstMatch(attrs);
  if (m == null) return null;
  var v = m.group(1)!.trim();
  if (v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1);
  return v;
}

Future<String?> _fetchBounded(Uri uri, int maxBytes) async {
  final client = HttpClient();
  client.userAgent = 'Eir/1.0';
  client.connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${maxBytes - 1}');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length >= maxBytes) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Web build probe. Browsers do not permit reading cross-origin media
/// responses (no CORS headers on video CDNs), so a hard network probe
/// would false-fail legitimate URLs on web. We therefore validate the
/// scheme/shape here and return null; actual playability is surfaced by
/// the media element's error events and the room's probe-on-open path.
/// This is a documented Web platform limitation, not a bypass of the
/// HTTPS/loopback policy enforced in the shared layer.
Future<String?> probeMediaUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return 'media_probe_failed';
  if (uri.scheme != 'https' && !_isLoopbackHttp(uri)) {
    return 'unsupported_media';
  }
  return null;
}

bool _isLoopbackHttp(Uri uri) {
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';
}

import 'package:mime/mime.dart';

import 'media_limits.dart';

/// Container/extension/magic identification for shared media files.
///
/// No fixed acceptance whitelist: the `mime` package resolves a type from the
/// file header (magic numbers first) and the file name, the declared picker
/// type is honored when it is well-formed, and anything that cannot be
/// classified is registered as [kOctetStreamMime] — the player decides
/// playability. Registered/imported MIME values are still security-validated
/// because they are spoken as `Content-Type` by the loopback HTTP daemon and
/// the same-origin web ServiceWorker bridge: types a browser may execute as an
/// active document are rejected outright (`unsupported_media`).

/// Fallback MIME for files neither magic numbers nor name/signals classify.
const String kOctetStreamMime = 'application/octet-stream';

/// Never served or accepted as media Content-Type.
const Set<String> kUnsafeMediaMimes = <String>{
  'text/html',
  'application/xhtml+xml',
  'image/svg+xml',
  'text/javascript',
  'application/javascript',
  'application/ecmascript',
  'text/ecmascript',
  'application/x-javascript',
  'application/xml',
  'text/xml',
};

final RegExp _mimeToken = RegExp(
  r'^[!#$%&*+\-.^_`|~0-9A-Za-z]{1,127}/[!#$%&*+\-.^_`|~0-9A-Za-z]{1,127}$',
);

/// Lower-cases a MIME value and drops parameters (`video/mp4; codecs=...`).
String? normalizeMediaMime(String? raw) {
  if (raw == null) return null;
  final base = raw.split(';').first.trim().toLowerCase();
  return base.isEmpty ? null : base;
}

bool isUnsafeMediaMime(String? mime) =>
    mime != null && kUnsafeMediaMimes.contains(mime);

/// A well-formed, parameterless `type/subtype` token that is safe to use as a
/// `Content-Type` for media responses. Order-sensitive: manifests re-check
/// that the stored value is already canonical.
bool isValidManifestMediaMime(String? mime) =>
    mime != null &&
    normalizeMediaMime(mime) == mime &&
    _mimeToken.hasMatch(mime) &&
    !isUnsafeMediaMime(mime);

/// Resolve the registered MIME for a picked file from the checked signals.
///
/// Precedence: magic-number sniff, then the picker-declared [declaredMime],
/// then the name/extension lookup. Known-but-unsafe types abort with
/// `unsupported_media`; unclassifiable files fall back to [kOctetStreamMime].
/// Package quirk handled here: the magic table has a single EBML pattern
/// mapped to `audio/weba`, so Matroska/WebM files are read back from the
/// name/extension table when it identifies them.
String resolveMediaMime({
  required String? magicMime,
  required String? declaredMime,
  required String fileName,
}) {
  final candidates = <String?>[
    _fixEbmlMagic(magicMime, declaredMime, fileName),
    _declaredCandidate(declaredMime),
    normalizeMediaMime(lookupMimeType(fileName)),
  ];
  for (final mime in candidates) {
    if (mime == null) continue;
    if (isUnsafeMediaMime(mime)) throw MediaException('unsupported_media', 'mime');
    if (_mimeToken.hasMatch(mime) && mime != kOctetStreamMime) return mime;
  }
  return kOctetStreamMime;
}

String? _fixEbmlMagic(String? magicMime, String? declaredMime, String fileName) {
  if (normalizeMediaMime(magicMime) != 'audio/weba') return magicMime;
  final declared = _declaredCandidate(declaredMime);
  if (declared == 'video/x-matroska' || declared == 'video/webm') return declared;
  final named = normalizeMediaMime(lookupMimeType(fileName));
  if (named == 'video/x-matroska' || named == 'video/webm') return named;
  return 'audio/weba';
}

String? _declaredCandidate(String? declaredMime) {
  final declared = normalizeMediaMime(declaredMime);
  if (declared == null || !_mimeToken.hasMatch(declared)) return null;
  return declared;
}

/// URL extension for a registered MIME; `mp4` when the value has none so the
/// `/m/<token>/<mediaId>.mp4` legacy URL shape and existing manifests stay
/// stable.
String mediaExtensionForMime(String mime) {
  if (mime == kOctetStreamMime) return 'mp4';
  return extensionFromMime(mime) ?? 'mp4';
}

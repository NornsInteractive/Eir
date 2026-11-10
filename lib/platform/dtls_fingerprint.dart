import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Extracts the actual DTLS certificate fingerprints from a live
/// PeerConnection via getStats(). Never trusts SDP-declared fingerprints.
///
/// Returns null when the platform does not expose a certificate fingerprint
/// reachable from a transport report. Callers must treat null as a hard
/// blocker (close the connection) rather than skip verification.
Future<String?> remoteDtlsFingerprint(RTCPeerConnection pc) async {
  final stats = await pc.getStats();
  final certificateFingerprints = <String, String>{};
  for (final report in stats) {
    final type = report.type.toLowerCase();
    if (!type.contains('certificate')) continue;
    final fp = report.values['fingerprint']?.toString();
    if (fp != null && fp.isNotEmpty) {
      certificateFingerprints[report.id] = fp;
    }
  }
  for (final report in stats) {
    final type = report.type.toLowerCase();
    if (!type.contains('transport')) continue;
    final remoteId = report.values['remoteCertificateId']?.toString();
    if (remoteId != null && certificateFingerprints.containsKey(remoteId)) {
      return certificateFingerprints[remoteId];
    }
  }
  // Some stacks report the certificate inline on the transport itself.
  for (final report in stats) {
    final type = report.type.toLowerCase();
    if (!type.contains('transport')) continue;
    final fp = report.values['remoteCertificateFingerprint']?.toString() ??
        report.values['remote-fingerprint']?.toString();
    if (fp != null && fp.isNotEmpty) return fp;
  }
  return null;
}

/// Local certificate fingerprint as reported by getStats().
/// Used by both sides to bind the handshake to the actual DTLS transport.
Future<String?> localDtlsFingerprint(RTCPeerConnection pc) async {
  final stats = await pc.getStats();
  final certificateFingerprints = <String, String>{};
  for (final report in stats) {
    final type = report.type.toLowerCase();
    if (!type.contains('certificate')) continue;
    final fp = report.values['fingerprint']?.toString();
    if (fp != null && fp.isNotEmpty) {
      certificateFingerprints[report.id] = fp;
    }
  }
  for (final report in stats) {
    final type = report.type.toLowerCase();
    if (!type.contains('transport')) continue;
    final localId = report.values['localCertificateId']?.toString();
    if (localId != null && certificateFingerprints.containsKey(localId)) {
      return certificateFingerprints[localId];
    }
  }
  return null;
}

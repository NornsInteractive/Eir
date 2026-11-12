import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../app_settings.dart';
import '../platform/http_fetch.dart';

class RemoteConfigResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;

  const RemoteConfigResult({required this.success, this.message, this.data});
}

class RemoteConfigService {
  static const String defaultConfigSecret = 'eir_secure_config_key_2026';

  /// Decrypts an encrypted config response payload using AES-256-GCM
  static Future<Map<String, dynamic>?> decryptPayload(
    Map<String, dynamic> payload, {
    String secret = defaultConfigSecret,
  }) async {
    try {
      final ivStr = payload['iv'] as String?;
      final tagStr = payload['tag'] as String?;
      final cipherStr = payload['ciphertext'] as String?;
      if (ivStr == null || tagStr == null || cipherStr == null) return null;

      final iv = base64Decode(ivStr);
      final tag = base64Decode(tagStr);
      final cipher = base64Decode(cipherStr);

      final keyBytes = crypto.sha256.convert(utf8.encode(secret)).bytes;
      final algorithm = AesGcm.with256bits();
      final secretKey = SecretKey(keyBytes);

      final box = SecretBox(cipher, nonce: iv, mac: Mac(tag));
      final decryptedBytes = await algorithm.decrypt(box, secretKey: secretKey);
      final decryptedText = utf8.decode(decryptedBytes);
      final decoded = jsonDecode(decryptedText);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      debugPrint('[RemoteConfigService] Decrypt error: $e');
      return null;
    }
  }

  /// Resolves the full URL to query /api/config based on server domain
  static String resolveConfigUrl(String domainOrUrl) {
    var raw = domainOrUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'https://$raw';
    }
    if (raw.endsWith('/api/config') || raw.endsWith('/api/v1/config')) {
      return raw;
    }
    return '$raw/api/config';
  }

  /// Fetches encrypted remote config from server, decrypts it, and applies it to AppSettings.
  static Future<RemoteConfigResult> fetchAndApply({
    String? serverDomain,
    String secret = defaultConfigSecret,
  }) async {
    final settings = AppSettings.instance;
    final domain = (serverDomain != null && serverDomain.trim().isNotEmpty)
        ? serverDomain.trim()
        : settings.serverDomain;
    final url = resolveConfigUrl(domain);

    try {
      final responseText = await httpGetText(url);
      if (responseText == null || responseText.isEmpty) {
        return const RemoteConfigResult(
          success: false,
          message: 'Network request failed or returned empty response',
        );
      }

      final payloadMap = jsonDecode(responseText);
      if (payloadMap is! Map) {
        return const RemoteConfigResult(
          success: false,
          message: 'Invalid payload structure',
        );
      }

      final config = await decryptPayload(
        Map<String, dynamic>.from(payloadMap),
        secret: secret,
      );
      if (config == null) {
        return const RemoteConfigResult(
          success: false,
          message: 'Failed to decrypt configuration',
        );
      }

      // 1. If server_domain is present in response, update server domain
      final remoteDomain =
          config['server_domain'] as String? ?? config['domain'] as String?;
      if (remoteDomain != null && remoteDomain.trim().isNotEmpty) {
        await settings.setServerDomain(remoteDomain.trim());
      }

      // 2. Update signaling server (ws_server)
      final signaling =
          config['signaling_server'] as String? ?? config['ws_server'] as String?;
      if (signaling != null && signaling.trim().isNotEmpty) {
        await settings.setSignalingUrl(signaling.trim());
      }

      // 3. Update TURN server
      final turnServer = config['turn_server'] as String?;
      final turnUser = config['turn_username'] as String?;
      final turnCred =
          config['turn_credential'] as String? ?? config['turn_password'] as String?;
      if (turnServer != null && turnServer.trim().isNotEmpty) {
        await settings.setTurnConfig(
          server: turnServer.trim(),
          username: turnUser?.trim() ?? '',
          credential: turnCred?.trim() ?? '',
        );
      }

      // 4. Record sync timestamp
      await settings.setLastConfigSyncTime(DateTime.now().millisecondsSinceEpoch);

      return RemoteConfigResult(success: true, data: config);
    } catch (e) {
      debugPrint('[RemoteConfigService] fetchAndApply failed: $e');
      return RemoteConfigResult(success: false, message: e.toString());
    }
  }

  /// Non-blocking background sync on app launch
  static Future<void> syncOnStartup() async {
    try {
      await fetchAndApply();
    } catch (_) {}
  }
}

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

  static String? _trimmedString(Object? value) {
    return value is String ? value.trim() : null;
  }

  /// Validates and normalizes an HTTP(S) server domain. Scheme-less domains
  /// such as `eir.norns.cc.cd` are accepted, matching resolveConfigUrl().
  static String? _validatedDomain(String value) {
    if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return value;
  }

  static String? _validatedSignaling(String value) {
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      return null;
    }
    return value;
  }

  static String? _validatedTurnServer(String value) {
    if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;
    final cleaned = value.replaceFirst(
      RegExp(r'^turns?:', caseSensitive: false),
      '',
    );
    if (cleaned.isEmpty) return null;
    try {
      final uri = Uri.parse('turn://$cleaned');
      if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
      if (uri.path.isNotEmpty && uri.path != '/') return null;
      final port = uri.hasPort ? uri.port : 3478;
      if (port < 1 || port > 65535) return null;
    } catch (_) {
      return null;
    }
    return value;
  }

  /// Fetches encrypted remote config from server, decrypts and validates the
  /// whole payload, then applies it as one coherent AppSettings batch.
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

      final remoteDomainRaw =
          _trimmedString(config['server_domain']) ??
          _trimmedString(config['domain']);
      final signalingRaw =
          _trimmedString(config['signaling_server']) ??
          _trimmedString(config['ws_server']);
      final turnServerRaw = _trimmedString(config['turn_server']);
      final turnUser = _trimmedString(config['turn_username']) ?? '';
      final turnCred =
          _trimmedString(config['turn_credential']) ??
          _trimmedString(config['turn_password']) ??
          '';

      String? remoteDomain;
      if (remoteDomainRaw != null && remoteDomainRaw.isNotEmpty) {
        remoteDomain = _validatedDomain(remoteDomainRaw);
        if (remoteDomain == null) {
          return const RemoteConfigResult(
            success: false,
            message: 'Invalid server domain in remote configuration',
          );
        }
      }

      String? signaling;
      if (signalingRaw != null && signalingRaw.isNotEmpty) {
        signaling = _validatedSignaling(signalingRaw);
        if (signaling == null) {
          return const RemoteConfigResult(
            success: false,
            message: 'Invalid signaling server in remote configuration',
          );
        }
      }

      String? turnServer;
      if (turnServerRaw != null && turnServerRaw.isNotEmpty) {
        turnServer = _validatedTurnServer(turnServerRaw);
        if (turnServer == null) {
          return const RemoteConfigResult(
            success: false,
            message: 'Invalid TURN server in remote configuration',
          );
        }
      }

      await settings.applyRemoteConfig(
        serverDomain: remoteDomain,
        signalingUrl: signaling,
        turnServer: turnServer,
        turnUsername: turnServer != null ? turnUser : null,
        turnCredential: turnServer != null ? turnCred : null,
        lastConfigSyncTime: DateTime.now().millisecondsSinceEpoch,
      );

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

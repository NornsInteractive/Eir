import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpClient;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_localization.dart';
import '../apple_glass.dart';
import '../models.dart' show formatBytes;

/// Model representing update response from Yggdrasil platform
class UpdateInfo {
  final bool hasUpdate;
  final bool isForce;
  final String appId;
  final String appName;
  final int currentVersionCode;
  final int latestVersionCode;
  final String latestVersionName;
  final String changelog;
  final String downloadUrl;
  final String shortDownloadUrl;
  final String fileName;
  final int fileSize;
  final String? fileSha256;
  final String releaseTime;

  UpdateInfo({
    required this.hasUpdate,
    required this.isForce,
    required this.appId,
    required this.appName,
    required this.currentVersionCode,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.changelog,
    required this.downloadUrl,
    required this.shortDownloadUrl,
    required this.fileName,
    required this.fileSize,
    this.fileSha256,
    required this.releaseTime,
  });

  factory UpdateInfo.fromJson(
    Map<String, dynamic> json, {
    int? activeVersionCode,
  }) {
    final latestCode = (json['latest_version_code'] as num?)?.toInt() ?? 0;
    final currentCode = activeVersionCode ??
        (json['current_version_code'] as num?)?.toInt() ??
        UpdateService.currentVersionCode;
    final serverHasUpdate = json['has_update'] == true;
    final hasUpdate = serverHasUpdate && (latestCode > currentCode);

    return UpdateInfo(
      hasUpdate: hasUpdate,
      isForce: hasUpdate && (json['is_force'] == true),
      appId: json['app_id'] as String? ?? '',
      appName: json['app_name'] as String? ?? 'Eir',
      currentVersionCode: currentCode,
      latestVersionCode: latestCode,
      latestVersionName: json['latest_version_name'] as String? ?? '',
      changelog: json['changelog'] as String? ?? '',
      downloadUrl: json['download_url'] as String? ?? '',
      shortDownloadUrl: json['short_download_url'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      fileSha256: json['file_sha256'] as String?,
      releaseTime: json['release_time'] as String? ?? '',
    );
  }
}

/// Service connecting to Yggdrasil Distribution Gateway (https://ygg.norns.cc.cd)
class UpdateService {
  static const String appId = 'com.norns.eir';
  static int _runtimeVersionCode = 2;
  static String _runtimeVersionName = '1.0.1';

  static int get currentVersionCode => _runtimeVersionCode;
  static String get currentVersionName => _runtimeVersionName;

  static const String defaultEndpoint =
      'https://ygg.norns.cc.cd/api/v1/app/latest';

  /// Asynchronously loads platform package info to dynamically reflect version from pubspec.
  static Future<void> ensureInitialized() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber);
      if (code != null && code > 0) {
        _runtimeVersionCode = code;
      }
      if (info.version.isNotEmpty) {
        _runtimeVersionName = info.version;
      }
    } catch (_) {}
  }

  static String get currentPlatform {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'universal';
  }

  /// Queries Yggdrasil distribution platform for the latest release.
  /// Never throws unhandled exceptions; returns null on network or parsing failure.
  static Future<UpdateInfo?> checkUpdate({
    String? customEndpoint,
    String? channel,
  }) async {
    try {
      final endpoint = customEndpoint ?? defaultEndpoint;
      final uri = Uri.parse(endpoint).replace(queryParameters: {
        'app_id': appId,
        'version_code': currentVersionCode.toString(),
        'platform': currentPlatform,
        'channel': channel ?? 'default',
      });

      final jsonMap = await _fetchJson(uri);
      if (jsonMap == null) return null;

      // Yggdrasil returns { code: 0, message: "success", data: { has_update: true, ... } }
      if (jsonMap['code'] == 0 && jsonMap['data'] is Map<String, dynamic>) {
        return UpdateInfo.fromJson(
          jsonMap['data'] as Map<String, dynamic>,
          activeVersionCode: currentVersionCode,
        );
      }

      // Or direct object
      if (jsonMap.containsKey('has_update')) {
        return UpdateInfo.fromJson(
          jsonMap,
          activeVersionCode: currentVersionCode,
        );
      }

      return null;
    } catch (e) {
      debugPrint('[UpdateService] checkUpdate error: $e');
      return null;
    }
  }

  /// Opens the download link in external browser or system application
  static Future<bool> openDownloadUrl(String url) async {
    if (url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e) {
        debugPrint('[UpdateService] launchUrl failed: $e');
        return false;
      }
    }
  }

  static Future<Map<String, dynamic>?> _fetchJson(Uri uri) async {
    if (kIsWeb) {
      // In web builds, CORS or browser fetch
      return null;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set('User-Agent', 'Eir-Client/$currentVersionName ($currentPlatform)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } finally {
      client.close();
    }
  }
}

/// Liquid Glass modal dialog showing update details
class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, UpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: !updateInfo.isForce,
      builder: (ctx) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final isShort = MediaQuery.of(context).size.height < 600;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassContainer.card(
          surfaceStyle: GlassSurfaceStyle.solid,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Icon & Version Badge
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tc.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: tc.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i18n.updateAvailable,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: tc.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tc.primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'v${updateInfo.latestVersionName}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (updateInfo.fileSize > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                formatBytes(updateInfo.fileSize),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: tc.textTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Changelog Section
              if (updateInfo.changelog.isNotEmpty) ...[
                Text(
                  i18n.updateChangelog,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tc.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: BoxConstraints(maxHeight: isShort ? 120 : 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tc.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tc.glassBorderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      updateInfo.changelog,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: tc.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Action Buttons
              Row(
                children: [
                  if (!updateInfo.isForce) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: tc.inputBackground,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            i18n.updateLater,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: tc.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: LiquidGlassActionButton(
                      height: 42,
                      onTap: () async {
                        final effectiveUrl = updateInfo.shortDownloadUrl.isNotEmpty
                            ? updateInfo.shortDownloadUrl
                            : updateInfo.downloadUrl;
                        await UpdateService.openDownloadUrl(effectiveUrl);
                        if (context.mounted && !updateInfo.isForce) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            i18n.updateDownloadNow,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

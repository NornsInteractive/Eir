import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        Platform,
        HttpClient,
        HttpClientResponse,
        HttpHeaders,
        File,
        Directory,
        IOSink,
        Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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

  static const MethodChannel _mediaPickerChannel =
      MethodChannel('com.norns.eir/media_picker');

  /// Downloads the update file with real-time streaming progress and speed.
  static Future<File?> downloadUpdateFile(
    String url, {
    String? preferredFileName,
    required void Function(int received, int total, double bytesPerSec)
        onProgress,
  }) async {
    if (kIsWeb) return null;

    HttpClient? client;
    IOSink? sink;
    try {
      Directory dir;
      try {
        dir = await getTemporaryDirectory();
      } catch (_) {
        dir = Directory.systemTemp;
      }

      final ext = currentPlatform == 'android' ? '.apk' : '';
      final rawName = preferredFileName?.trim();
      final safeName = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : 'eir_update_${DateTime.now().millisecondsSinceEpoch}$ext';
      final file = File('${dir.path}/$safeName');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      var currentUri = Uri.parse(url);
      HttpClientResponse? response;
      for (int i = 0; i < 5; i++) {
        final request = await client.getUrl(currentUri);
        request.headers.set(
            'User-Agent', 'Eir-Client/$currentVersionName ($currentPlatform)');
        request.followRedirects = false;
        response = await request.close();
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null) {
            currentUri = currentUri.resolve(location);
            await response.drain<void>();
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != 200) {
        await response?.drain<void>();
        return null;
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      var lastSampleTime = DateTime.now().millisecondsSinceEpoch;
      var lastSampleBytes = 0;
      var speedBps = 0.0;

      sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - lastSampleTime;
        if (elapsed >= 300) {
          final bytesDiff = receivedBytes - lastSampleBytes;
          speedBps = (bytesDiff * 1000.0) / elapsed;
          lastSampleTime = now;
          lastSampleBytes = receivedBytes;
          onProgress(receivedBytes, totalBytes, speedBps);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      onProgress(receivedBytes, totalBytes, 0);
      return file;
    } catch (e) {
      debugPrint('[UpdateService] download error: $e');
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      return null;
    } finally {
      client?.close();
    }
  }

  /// Installs the downloaded update package natively on the current platform.
  static Future<bool> installDownloadedFile(String filePath) async {
    if (kIsWeb) return false;
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[UpdateService] install file not found: $filePath');
      return false;
    }

    if (Platform.isAndroid) {
      try {
        final res = await _mediaPickerChannel.invokeMethod<bool>(
          'installApk',
          {'path': filePath},
        );
        return res ?? true;
      } catch (e) {
        debugPrint('[UpdateService] installApk MethodChannel failed: $e');
        return false;
      }
    } else if (Platform.isWindows) {
      try {
        await Process.start(filePath, <String>[], runInShell: true);
        return true;
      } catch (e) {
        debugPrint('[UpdateService] run windows installer failed: $e');
        return false;
      }
    } else if (Platform.isMacOS) {
      try {
        await Process.run('open', <String>[filePath]);
        return true;
      } catch (e) {
        debugPrint('[UpdateService] run macos installer failed: $e');
        return false;
      }
    } else if (Platform.isLinux) {
      try {
        await Process.run('xdg-open', <String>[filePath]);
        return true;
      } catch (e) {
        debugPrint('[UpdateService] run linux installer failed: $e');
        return false;
      }
    }
    return false;
  }

  static Future<Map<String, dynamic>?> _fetchJson(Uri uri) async {
    if (kIsWeb) {
      // In web builds, CORS or browser fetch
      return null;
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(
          'User-Agent', 'Eir-Client/$currentVersionName ($currentPlatform)');
      request.headers.set('Accept', 'application/json');

      final response =
          await request.close().timeout(const Duration(seconds: 10));
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

/// Liquid Glass modal dialog showing update details with in-app download and installation.
class UpdateDialog extends StatefulWidget {
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
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _speedText = '';
  String _downloadedSizeText = '';
  bool _downloadComplete = false;
  String? _downloadedFilePath;
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _speedText = '';
    });

    final effectiveUrl = widget.updateInfo.shortDownloadUrl.isNotEmpty
        ? widget.updateInfo.shortDownloadUrl
        : widget.updateInfo.downloadUrl;

    final file = await UpdateService.downloadUpdateFile(
      effectiveUrl,
      preferredFileName: widget.updateInfo.fileName.isNotEmpty
          ? widget.updateInfo.fileName
          : null,
      onProgress: (received, total, speedBps) {
        if (!mounted) return;
        setState(() {
          if (total > 0) {
            _progress = (received / total).clamp(0.0, 1.0);
            _downloadedSizeText =
                '${formatBytes(received)} / ${formatBytes(total)}';
          } else {
            _downloadedSizeText = formatBytes(received);
          }
          if (speedBps > 0) {
            _speedText = '${formatBytes(speedBps.toInt())}/s';
          }
        });
      },
    );

    if (!mounted) return;

    if (file != null) {
      setState(() {
        _isDownloading = false;
        _downloadComplete = true;
        _downloadedFilePath = file.path;
      });
      // Automatically trigger native installation immediately
      await UpdateService.installDownloadedFile(file.path);
    } else {
      setState(() {
        _isDownloading = false;
        _errorMessage = AppI18n.of(context).updateDownloadFailed;
      });
    }
  }

  Future<void> _install() async {
    final path = _downloadedFilePath;
    if (path != null) {
      await UpdateService.installDownloadedFile(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final isShort = MediaQuery.of(context).size.height < 600;
    final updateInfo = widget.updateInfo;

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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
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
              if (updateInfo.changelog.isNotEmpty && !_isDownloading && !_downloadComplete) ...[
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

              // Downloading Progress Section
              if (_isDownloading) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tc.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tc.glassBorderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            i18n.updateDownloading,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: tc.textPrimary,
                            ),
                          ),
                          Text(
                            '${(_progress * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tc.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress > 0 ? _progress : null,
                          backgroundColor: tc.glassBorderSubtle,
                          valueColor: AlwaysStoppedAnimation<Color>(tc.primary),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _downloadedSizeText,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: tc.textTertiary,
                            ),
                          ),
                          if (_speedText.isNotEmpty)
                            Text(
                              _speedText,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: tc.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Download Complete Section
              if (_downloadComplete) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.green, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          i18n.updateDownloadComplete,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Error Message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Action Buttons
              Row(
                children: [
                  if (!updateInfo.isForce && !_isDownloading) ...[
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
                    child: _isDownloading
                        ? Container(
                            height: 42,
                            decoration: BoxDecoration(
                              color: tc.primary.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          )
                        : _downloadComplete
                            ? LiquidGlassActionButton(
                                height: 42,
                                onTap: _install,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.install_mobile_rounded,
                                        size: 16, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      i18n.updateInstallNow,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : LiquidGlassActionButton(
                                height: 42,
                                onTap: _startDownload,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.download_rounded,
                                        size: 16, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      _errorMessage != null
                                          ? i18n.updateRetry
                                          : i18n.updateDownloadNow,
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
              // Fallback to external browser if download fails
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () {
                      final effectiveUrl =
                          updateInfo.shortDownloadUrl.isNotEmpty
                              ? updateInfo.shortDownloadUrl
                              : updateInfo.downloadUrl;
                      UpdateService.openDownloadUrl(effectiveUrl);
                    },
                    child: Text(
                      i18n.updateOpenInBrowser,
                      style: TextStyle(
                        fontSize: 12,
                        color: tc.textTertiary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

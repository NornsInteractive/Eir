import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../app_settings.dart';
import '../platform/web_favicon.dart';

enum AppIconStyle {
  classic('classic', '经典黑晶', 'Classic Dark', 'assets/images/icons/icon_default.png'),
  neon('neon', '极光霓虹', 'Aurora Neon', 'assets/images/icons/icon_neon.png'),
  stealth('stealth', '沉浸暗夜', 'Midnight Stealth', 'assets/images/icons/icon_stealth.png'),
  silver('silver', '冰川银白', 'Glacier Silver', 'assets/images/icons/icon_silver.png'),
  custom('custom', '自定义图片', 'Custom Image', null);

  final String id;
  final String nameZh;
  final String nameEn;
  final String? assetPath;

  const AppIconStyle(this.id, this.nameZh, this.nameEn, this.assetPath);

  static AppIconStyle fromId(String? id) {
    return AppIconStyle.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AppIconStyle.classic,
    );
  }
}

class AppIconManager {
  static const MethodChannel _channel = MethodChannel('com.norns.eir/app_icon');

  /// Initializes web favicon and icon synchronization on app start
  static Future<void> init() async {
    final style = AppIconStyle.fromId(AppSettings.instance.appIconStyle);
    final customPath = AppSettings.instance.customAppIconPath;
    if (kIsWeb) {
      if (style == AppIconStyle.custom && customPath != null && customPath.isNotEmpty) {
        _setWebFavicon(customPath);
      } else {
        _setWebFavicon(style.id);
      }
    }
  }

  /// Switches app launcher icon or active icon style
  static Future<bool> setAppIcon(AppIconStyle style) async {
    await AppSettings.instance.setAppIconStyle(style.id);

    if (kIsWeb) {
      _setWebFavicon(style.id);
      return true;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final res = await _channel.invokeMethod<bool>('setAppIcon', {'icon': style.id});
        return res ?? true;
      } catch (e) {
        debugPrint('[AppIconManager] setAppIcon failed: $e');
        return false;
      }
    }

    return true;
  }

  /// Sets up a custom image file as the launcher icon / home screen shortcut
  static Future<bool> applyCustomIcon(String sourceFilePath, {String label = 'Eir'}) async {
    try {
      String persistentPath = sourceFilePath;
      if (!kIsWeb) {
        final docDir = await getApplicationDocumentsDirectory();
        final iconsDir = Directory('${docDir.path}/custom_icons');
        if (!iconsDir.existsSync()) {
          iconsDir.createSync(recursive: true);
        }
        final ext = sourceFilePath.contains('.') ? sourceFilePath.split('.').last : 'png';
        persistentPath = '${iconsDir.path}/app_icon_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(sourceFilePath).copy(persistentPath);
      }

      await AppSettings.instance.setCustomAppIconPath(persistentPath);
      await AppSettings.instance.setAppIconStyle(AppIconStyle.custom.id);

      if (kIsWeb) {
        _setWebFavicon(persistentPath);
        return true;
      }

      if (Platform.isAndroid) {
        final res = await _channel.invokeMethod<bool>('createPinShortcut', {
          'iconPath': persistentPath,
          'label': label,
        });
        return res ?? true;
      }

      return true;
    } catch (e) {
      debugPrint('[AppIconManager] applyCustomIcon failed: $e');
      return false;
    }
  }

  /// Opens file picker for image files
  static Future<String?> pickCustomIconImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        if (kIsWeb) {
          final file = result.files.first;
          if (file.bytes != null) {
            final ext = (file.extension ?? 'png').toLowerCase();
            final mime = ext == 'png'
                ? 'image/png'
                : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
            final base64Data = base64Encode(file.bytes!);
            return 'data:$mime;base64,$base64Data';
          }
        }
        return result.files.first.path;
      }
    } catch (e) {
      debugPrint('[AppIconManager] pickCustomIconImage failed: $e');
    }
    return null;
  }

  static void _setWebFavicon(String iconIdOrPath) {
    if (!kIsWeb) return;
    try {
      updateWebFavicon(iconIdOrPath);
    } catch (e) {
      debugPrint('[AppIconManager] updateWebFavicon failed: $e');
    }
  }
}

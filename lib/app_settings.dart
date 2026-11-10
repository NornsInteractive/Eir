import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global App Settings following docs/APP-SETTINGS.md
/// Supports:
/// 1. Language: system / zh-CN / en-US (persistent, takes effect immediately without session loss)
/// 2. Theme Mode: system / light / dark (persistent)
/// 3. Independent Light and Dark Theme Colors (isolated, persistent, cannot overwrite each other)
/// 4. Default Signaling URL configuration
class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._();
  AppSettings._();

  // Storage keys
  static const String _kLocaleKey = 'eir_setting_locale';
  static const String _kThemeModeKey = 'eir_setting_theme_mode';
  static const String _kLightColorKey = 'eir_setting_light_theme_color';
  static const String _kDarkColorKey = 'eir_setting_dark_theme_color';
  static const String _kSignalingUrlKey = 'eir_setting_signaling_url';

  // Defaults
  static const Color defaultLightColor = Color(0xFF007AFF); // Apple Blue Light
  static const Color defaultDarkColor = Color(0xFF0A84FF);  // Apple Blue Dark
  static const String defaultSignalingUrl = 'ws://127.0.0.1:8080/ws';

  /// Dynamically resolved default signaling URL:
  /// On Web, automatically matches current origin (wss:// for HTTPS, ws:// for HTTP) and appends /ws.
  /// On Native, defaults to defaultSignalingUrl ('ws://127.0.0.1:8080/ws').
  static String get effectiveDefaultSignalingUrl {
    if (kIsWeb) {
      try {
        final base = Uri.base;
        if (base.host.isNotEmpty) {
          final isHttps = base.scheme == 'https';
          final wsScheme = isHttps ? 'wss' : 'ws';
          final portPart = (base.hasPort && base.port != 80 && base.port != 443)
              ? ':${base.port}'
              : '';
          return '$wsScheme://${base.host}$portPart/ws';
        }
      } catch (_) {}
    }
    return defaultSignalingUrl;
  }

  // Language: null = follow system
  Locale? _locale;
  Locale? get locale => _locale;

  // Theme Mode
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  // Independent Light Theme Color
  Color _lightThemeColor = defaultLightColor;
  Color get lightThemeColor => _lightThemeColor;

  // Independent Dark Theme Color
  Color _darkThemeColor = defaultDarkColor;
  Color get darkThemeColor => _darkThemeColor;

  // Configurable Signaling URL
  String _signalingUrl = defaultSignalingUrl;
  String get signalingUrl => _signalingUrl;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Load settings from local storage, with graceful individual fallbacks per docs/APP-SETTINGS.md
  Future<void> init() async {
    if (_isInitialized) return;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('[AppSettings] Warning: Failed to access SharedPreferences: $e');
    }

    if (prefs != null) {
      // 1. Locale (Isolated try-catch)
      try {
        final locStr = prefs.getString(_kLocaleKey);
        if (locStr == 'zh_CN') {
          _locale = const Locale('zh', 'CN');
        } else if (locStr == 'en_US') {
          _locale = const Locale('en', 'US');
        } else {
          _locale = null; // Follow system
        }
      } catch (e) {
        _locale = null;
        debugPrint('[AppSettings] Reset corrupted locale setting: $e');
      }

      // 2. Theme mode (Isolated try-catch)
      try {
        final modeStr = prefs.getString(_kThemeModeKey);
        if (modeStr == 'light') {
          _themeMode = ThemeMode.light;
        } else if (modeStr == 'dark') {
          _themeMode = ThemeMode.dark;
        } else {
          _themeMode = ThemeMode.system;
        }
      } catch (e) {
        _themeMode = ThemeMode.system;
        debugPrint('[AppSettings] Reset corrupted themeMode setting: $e');
      }

      // 3. Independent Light Theme Color (Isolated try-catch)
      try {
        final lightColorVal = prefs.getInt(_kLightColorKey);
        if (lightColorVal != null && lightColorVal != 0) {
          _lightThemeColor = Color(lightColorVal);
        }
      } catch (e) {
        _lightThemeColor = defaultLightColor;
        debugPrint('[AppSettings] Reset corrupted lightThemeColor setting: $e');
      }

      // 4. Independent Dark Theme Color (Isolated try-catch)
      try {
        final darkColorVal = prefs.getInt(_kDarkColorKey);
        if (darkColorVal != null && darkColorVal != 0) {
          _darkThemeColor = Color(darkColorVal);
        }
      } catch (e) {
        _darkThemeColor = defaultDarkColor;
        debugPrint('[AppSettings] Reset corrupted darkThemeColor setting: $e');
      }

      // 5. Signaling URL (Isolated try-catch)
      try {
        final sigUrl = prefs.getString(_kSignalingUrlKey);
        if (sigUrl != null && sigUrl.trim().isNotEmpty) {
          final trimmed = sigUrl.trim();
          // Auto-migrate legacy standalone 8765 port to unified 8080 or dynamic web origin
          if (trimmed == 'ws://127.0.0.1:8765' ||
              trimmed == 'ws://localhost:8765' ||
              trimmed == 'ws://127.0.0.1:8765/' ||
              trimmed == 'ws://localhost:8765/') {
            _signalingUrl = effectiveDefaultSignalingUrl;
            _saveString(_kSignalingUrlKey, _signalingUrl).catchError((_) => null);
          } else {
            _signalingUrl = trimmed;
          }
        } else {
          _signalingUrl = effectiveDefaultSignalingUrl;
        }
      } catch (e) {
        _signalingUrl = effectiveDefaultSignalingUrl;
        debugPrint('[AppSettings] Reset corrupted signalingUrl setting: $e');
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  void setLocale(Locale? loc) {
    if (_locale != loc) {
      _locale = loc;
      notifyListeners();
      _saveLocale(loc);
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      _saveThemeMode(mode);
    }
  }

  void setLightThemeColor(Color color) {
    if (_lightThemeColor != color) {
      _lightThemeColor = color;
      notifyListeners();
      _saveColor(_kLightColorKey, color.value);
    }
  }

  void resetLightThemeColor() {
    setLightThemeColor(defaultLightColor);
  }

  void setDarkThemeColor(Color color) {
    if (_darkThemeColor != color) {
      _darkThemeColor = color;
      notifyListeners();
      _saveColor(_kDarkColorKey, color.value);
    }
  }

  void resetDarkThemeColor() {
    setDarkThemeColor(defaultDarkColor);
  }

  Future<void> setSignalingUrl(String url) async {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      throw ArgumentError('signaling URL must be ws:// or wss://');
    }
    if (_signalingUrl != clean) {
      await _saveString(_kSignalingUrlKey, clean);
      _signalingUrl = clean;
      notifyListeners();
    }
  }

  /// Determines currently active theme color based on themeMode and system brightness
  Color getActiveThemeColor(BuildContext context) {
    return isDarkMode(context) ? darkThemeColor : lightThemeColor;
  }

  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    try {
      return Theme.of(context).brightness == Brightness.dark;
    } catch (_) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  // --- Persistence helpers ---
  Future<void> _saveLocale(Locale? loc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (loc == null) {
        await prefs.remove(_kLocaleKey);
      } else {
        final val = '${loc.languageCode}_${loc.countryCode ?? ""}';
        await prefs.setString(_kLocaleKey, val);
      }
    } catch (_) {}
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system');
      await prefs.setString(_kThemeModeKey, val);
    } catch (_) {}
  }

  Future<void> _saveColor(String key, int val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, val);
    } catch (_) {}
  }

  Future<void> _saveString(String key, String val) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, val)) {
      throw StateError('could not persist signaling configuration');
    }
  }
}

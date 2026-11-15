import 'dart:math';
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
  static const String _kNicknameKey = 'eir_user_nickname';
  static const String _kAvatarKey = 'eir_user_avatar';
  static const String _kHasPendingUpdateKey = 'eir_has_pending_update';
  static const String _kLastUpdateCheckDateKey = 'eir_last_update_check_date';
  static const String _kBackgroundKeepAliveKey = 'eir_setting_background_keep_alive';
  static const String _kTurnServerKey = 'eir_setting_turn_server';
  static const String _kTurnUsernameKey = 'eir_setting_turn_username';
  static const String _kTurnCredentialKey = 'eir_setting_turn_credential';
  static const String _kTransportEngineKey = 'eir_setting_transport_engine';
  static const String _kWaitForPeerBufferingKey = 'eir_setting_wait_for_peer_buffering';
  static const String _kAppIconStyleKey = 'eir_setting_app_icon_style';
  static const String _kCustomAppIconPathKey = 'eir_setting_custom_app_icon_path';
  static const String _kServerDomainKey = 'eir_setting_server_domain';
  static const String _kLastConfigSyncTimeKey = 'eir_last_config_sync_time';
  static const String _kEnableCastFloatingChatKey = 'eir_setting_enable_cast_floating_chat';

  static const List<String> _adjectives = [
    'Starlight', 'Velvet', 'Neon', 'Cosmic', 'Solar', 'Lunar', 'Silent',
    'Crystal', 'Breeze', 'Midnight', 'Echo', 'Glacier', 'Golden', 'Cyber',
    'Radiant', 'Astral', 'Amber', 'Frosty', 'Emerald', 'Wandering',
    'Shadow', 'Ocean', 'Serene', 'Mystic', 'Brisk', 'Cobalt'
  ];

  static const List<String> _nouns = [
    'Otter', 'Falcon', 'Fox', 'Panda', 'Dolphin', 'Raven', 'Voyager',
    'Seeker', 'Drifter', 'Phoenix', 'Dreamer', 'Scout', 'Nomad', 'Pilot',
    'Stalker', 'Surfer', 'Explorer', 'Ranger', 'Specter', 'Chaser',
    'Lynx', 'Badger', 'Sparrow', 'Wolf'
  ];

  /// Generates a fresh random English nickname, e.g., 'StarlightOtter', 'NeonFalcon'.
  static String generateRandomEnglishNickname({Random? random}) {
    final r = random ?? Random();
    final adj = _adjectives[r.nextInt(_adjectives.length)];
    final noun = _nouns[r.nextInt(_nouns.length)];
    return '$adj$noun';
  }

  // Defaults
  static const Color defaultLightColor = Color(0xFF007AFF); // Apple Blue Light
  static const Color defaultDarkColor = Color(0xFF0A84FF);  // Apple Blue Dark
  static const String defaultSignalingUrl = 'wss://eir.norns.cc.cd/ws';
  static const String defaultAvatar = 'preset:aurora';
  static const String defaultNickname = '';
  static const String defaultServerDomain = 'https://eir.norns.cc.cd';
  static const String defaultTurnServer = 'ip.norns.cc.cd:3478';
  static const String defaultTurnUsername = 'norns';
  static const String defaultTurnCredential = 'norns';

  /// Dynamically resolved default signaling URL:
  /// On Web, automatically matches current origin (wss:// for HTTPS, ws:// for HTTP) and appends /ws.
  /// On Native, defaults to global high-availability signaling URL ('wss://eir.norns.cc.cd/ws').
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

  // User Profile: Nickname & Avatar
  String _nickname = defaultNickname;
  String get nickname => _nickname;

  String _avatar = defaultAvatar;
  String get avatar => _avatar;

  // Pending Update & Daily Check
  bool _hasPendingUpdate = false;
  bool get hasPendingUpdate => _hasPendingUpdate;

  String _lastUpdateCheckDate = '';
  String get lastUpdateCheckDate => _lastUpdateCheckDate;

  // Background Keep-Alive
  bool _backgroundKeepAlive = true;
  bool get backgroundKeepAlive => _backgroundKeepAlive;

  // Server Domain Configuration
  String _serverDomain = defaultServerDomain;
  String get serverDomain => _serverDomain;

  int _lastConfigSyncTime = 0;
  int get lastConfigSyncTime => _lastConfigSyncTime;

  // TURN Relay Server Configuration
  String _turnServer = defaultTurnServer;
  String get turnServer => _turnServer;
  String _turnUsername = defaultTurnUsername;
  String get turnUsername => _turnUsername;
  String _turnCredential = defaultTurnCredential;
  String get turnCredential => _turnCredential;

  // Transport Engine Preference: 'webrtc' | 'tailcat'
  String _transportEngine = 'webrtc';
  String get transportEngine => _transportEngine;
  bool get isTailcatEngine => _transportEngine == 'tailcat';

  // Playback sync: wait for peer buffering
  bool _waitForPeerBuffering = true;
  bool get waitForPeerBuffering => _waitForPeerBuffering;

  // App Launcher Icon Style: 'classic' | 'neon' | 'stealth' | 'silver' | 'custom'
  String _appIconStyle = 'classic';
  String get appIconStyle => _appIconStyle;

  String? _customAppIconPath;
  String? get customAppIconPath => _customAppIconPath;

  // Cast Floating Chat Bubble: Enabled by default
  bool _enableCastFloatingChat = true;
  bool get enableCastFloatingChat => _enableCastFloatingChat;

  /// Effective display name: returns trimmed nickname if non-empty, otherwise empty
  String get effectiveDisplayName => _nickname.trim();

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
          // Auto-migrate legacy standalone 8765 / local 8080 to global high-availability signaling URL
          if (trimmed == 'ws://127.0.0.1:8765' ||
              trimmed == 'ws://localhost:8765' ||
              trimmed == 'ws://127.0.0.1:8765/' ||
              trimmed == 'ws://localhost:8765/' ||
              trimmed == 'ws://127.0.0.1:8080/ws' ||
              trimmed == 'ws://localhost:8080/ws' ||
              trimmed == 'ws://127.0.0.1:8080' ||
              trimmed == 'ws://localhost:8080') {
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

      // 6. User Nickname (Isolated try-catch)
      try {
        final nick = prefs.getString(_kNicknameKey);
        if (nick != null && nick.trim().isNotEmpty) {
          _nickname = nick.trim();
        } else {
          _nickname = generateRandomEnglishNickname();
          _saveString(_kNicknameKey, _nickname).catchError((_) => null);
        }
      } catch (e) {
        _nickname = generateRandomEnglishNickname();
        debugPrint('[AppSettings] Reset corrupted nickname setting: $e');
      }

      // 7. User Avatar (Isolated try-catch)
      try {
        final av = prefs.getString(_kAvatarKey);
        if (av != null && av.trim().isNotEmpty) {
          _avatar = av.trim();
        }
      } catch (e) {
        _avatar = defaultAvatar;
        debugPrint('[AppSettings] Reset corrupted avatar setting: $e');
      }

      // 8. Pending Update Flag (Isolated try-catch)
      try {
        _hasPendingUpdate = prefs.getBool(_kHasPendingUpdateKey) ?? false;
      } catch (e) {
        _hasPendingUpdate = false;
        debugPrint('[AppSettings] Reset corrupted pending update flag: $e');
      }

      // 9. Last Update Check Date (Isolated try-catch)
      try {
        _lastUpdateCheckDate = prefs.getString(_kLastUpdateCheckDateKey) ?? '';
      } catch (e) {
        _lastUpdateCheckDate = '';
        debugPrint('[AppSettings] Reset corrupted last update check date: $e');
      }

      // 10. Background Keep-Alive (Isolated try-catch)
      try {
        _backgroundKeepAlive = prefs.getBool(_kBackgroundKeepAliveKey) ?? true;
      } catch (e) {
        _backgroundKeepAlive = true;
        debugPrint('[AppSettings] Reset corrupted background keep-alive setting: $e');
      }

      // 11. TURN Relay Server Configuration (Isolated try-catch)
      try {
        final savedTurn = prefs.getString(_kTurnServerKey);
        _turnServer = (savedTurn != null && savedTurn.isNotEmpty)
            ? savedTurn
            : defaultTurnServer;
        final savedUser = prefs.getString(_kTurnUsernameKey);
        _turnUsername = (savedUser != null && savedUser.isNotEmpty)
            ? savedUser
            : defaultTurnUsername;
        final savedCred = prefs.getString(_kTurnCredentialKey);
        _turnCredential = (savedCred != null && savedCred.isNotEmpty)
            ? savedCred
            : defaultTurnCredential;
      } catch (e) {
        _turnServer = defaultTurnServer;
        _turnUsername = defaultTurnUsername;
        _turnCredential = defaultTurnCredential;
        debugPrint('[AppSettings] Reset corrupted TURN settings: $e');
      }

      // 11.1 Server Domain & Last Config Sync (Isolated try-catch)
      try {
        final savedDomain = prefs.getString(_kServerDomainKey);
        _serverDomain = (savedDomain != null && savedDomain.isNotEmpty)
            ? savedDomain
            : defaultServerDomain;
        _lastConfigSyncTime = prefs.getInt(_kLastConfigSyncTimeKey) ?? 0;
      } catch (e) {
        _serverDomain = defaultServerDomain;
        _lastConfigSyncTime = 0;
        debugPrint('[AppSettings] Reset corrupted Server Domain settings: $e');
      }

      // 12. Transport Engine Preference (Isolated try-catch)
      try {
        final engine = prefs.getString(_kTransportEngineKey) ?? 'webrtc';
        _transportEngine = engine == 'tailcat' ? 'tailcat' : 'webrtc';
      } catch (e) {
        _transportEngine = 'webrtc';
        debugPrint('[AppSettings] Reset corrupted transport engine setting: $e');
      }

      // 13. Wait for Peer Buffering (Isolated try-catch)
      try {
        _waitForPeerBuffering = prefs.getBool(_kWaitForPeerBufferingKey) ?? true;
      } catch (e) {
        _waitForPeerBuffering = true;
        debugPrint('[AppSettings] Reset corrupted wait for peer buffering setting: $e');
      }

      // 14. App Icon Style (Isolated try-catch)
      try {
        _appIconStyle = prefs.getString(_kAppIconStyleKey) ?? 'classic';
      } catch (e) {
        _appIconStyle = 'classic';
        debugPrint('[AppSettings] Reset corrupted app icon style setting: $e');
      }

      // 15. Custom App Icon Path (Isolated try-catch)
      try {
        _customAppIconPath = prefs.getString(_kCustomAppIconPathKey);
      } catch (e) {
        _customAppIconPath = null;
        debugPrint('[AppSettings] Reset corrupted custom app icon path setting: $e');
      }

      // 16. Enable Cast Floating Chat (Isolated try-catch)
      try {
        _enableCastFloatingChat = prefs.getBool(_kEnableCastFloatingChatKey) ?? true;
      } catch (e) {
        _enableCastFloatingChat = true;
        debugPrint('[AppSettings] Reset corrupted enable cast floating chat setting: $e');
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setWaitForPeerBuffering(bool value) async {
    if (_waitForPeerBuffering != value) {
      _waitForPeerBuffering = value;
      notifyListeners();
      await _saveBool(_kWaitForPeerBufferingKey, value);
    }
  }

  Future<void> setBackgroundKeepAlive(bool value) async {
    if (_backgroundKeepAlive != value) {
      _backgroundKeepAlive = value;
      notifyListeners();
      await _saveBool(_kBackgroundKeepAliveKey, value);
    }
  }

  Future<void> setPendingUpdate(bool value) async {
    if (_hasPendingUpdate != value) {
      _hasPendingUpdate = value;
      notifyListeners();
      await _saveBool(_kHasPendingUpdateKey, value);
    }
  }

  Future<void> setLastUpdateCheckDate(String dateStr) async {
    if (_lastUpdateCheckDate != dateStr) {
      _lastUpdateCheckDate = dateStr;
      await _saveString(_kLastUpdateCheckDateKey, dateStr).catchError((_) => null);
    }
  }

  Future<void> setTurnConfig({
    required String server,
    required String username,
    required String credential,
  }) async {
    _turnServer = server.trim();
    _turnUsername = username.trim();
    _turnCredential = credential.trim();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTurnServerKey, _turnServer);
      await prefs.setString(_kTurnUsernameKey, _turnUsername);
      await prefs.setString(_kTurnCredentialKey, _turnCredential);
    } catch (e) {
      debugPrint('[AppSettings] Failed to persist TURN config: $e');
    }
  }

  Future<void> setServerDomain(String domain) async {
    final trimmed = domain.trim();
    final target = trimmed.isNotEmpty ? trimmed : defaultServerDomain;
    if (_serverDomain == target) return;
    _serverDomain = target;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kServerDomainKey, _serverDomain);
    } catch (e) {
      debugPrint('[AppSettings] Failed to persist Server Domain: $e');
    }
  }

  Future<void> setLastConfigSyncTime(int timestamp) async {
    _lastConfigSyncTime = timestamp;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastConfigSyncTimeKey, timestamp);
    } catch (e) {
      debugPrint('[AppSettings] Failed to persist Last Config Sync Time: $e');
    }
  }

  Future<void> setTransportEngine(String engine) async {
    final valid = engine == 'tailcat' ? 'tailcat' : 'webrtc';
    if (_transportEngine != valid) {
      _transportEngine = valid;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kTransportEngineKey, valid);
      } catch (e) {
        debugPrint('[AppSettings] Failed to persist transport engine: $e');
      }
    }
  }

  Future<void> setEnableCastFloatingChat(bool enable) async {
    if (_enableCastFloatingChat != enable) {
      _enableCastFloatingChat = enable;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kEnableCastFloatingChatKey, enable);
      } catch (e) {
        debugPrint('[AppSettings] Failed to persist enable cast floating chat: $e');
      }
    }
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

  Future<void> setNickname(String name) async {
    final clean = name.trim();
    if (_nickname != clean) {
      _nickname = clean;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kNicknameKey, clean);
      } catch (e) {
        debugPrint('[AppSettings] Failed to persist nickname: $e');
      }
    }
  }

  /// Randomizes and updates the nickname with a new English name.
  Future<String> randomizeNickname() async {
    final newNick = generateRandomEnglishNickname();
    await setNickname(newNick);
    return newNick;
  }

  Future<void> setAvatar(String avatarKeyOrPath) async {
    final clean = avatarKeyOrPath.trim();
    if (_avatar != clean) {
      _avatar = clean;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAvatarKey, clean);
      } catch (e) {
        debugPrint('[AppSettings] Failed to persist avatar: $e');
      }
    }
  }

  Future<void> setAppIconStyle(String style) async {
    final clean = style.trim();
    if (_appIconStyle != clean) {
      _appIconStyle = clean;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAppIconStyleKey, clean);
      } catch (e) {
        debugPrint('[AppSettings] Failed to persist app icon style: $e');
      }
    }
  }

  Future<void> setCustomAppIconPath(String? path) async {
    final clean = path?.trim();
    if (_customAppIconPath != clean) {
      _customAppIconPath = clean;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        if (clean != null && clean.isNotEmpty) {
          await prefs.setString(_kCustomAppIconPathKey, clean);
        } else {
          await prefs.remove(_kCustomAppIconPathKey);
        }
      } catch (e) {
        debugPrint('[AppSettings] Failed to persist custom app icon path: $e');
      }
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

  Future<void> _saveBool(String key, bool val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, val);
    } catch (_) {}
  }
}

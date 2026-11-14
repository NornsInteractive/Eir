import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_localization.dart';
import 'apple_glass.dart';
import 'core/app_icon_manager.dart';
import 'core/remote_config_service.dart';
import 'core/room_session.dart';
import 'core/update_service.dart';
import 'views/lobby_view.dart';
import 'views/cinema_view.dart';
import 'views/screen_share_live_view.dart';
import 'views/screen_share_broadcaster_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize();
  await AppSettings.instance.init();
  await AppIconManager.init();
  await UpdateService.ensureInitialized();
  unawaited(RemoteConfigService.syncOnStartup());

  runApp(
    LiquidGlassWidgets.wrap(
      adaptiveQuality: true,
      respectSystemAccessibility: true,
      brightnessResolver: Theme.maybeBrightnessOf,
      theme: GlassThemeData.simple(
        blur: 16,
        thickness: 25,
        quality: GlassQuality.standard,
      ),
      child: const EirApp(),
    ),
  );
}

class EirApp extends StatelessWidget {
  const EirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;

        final lightScheme = ColorScheme.fromSeed(
          seedColor: settings.lightThemeColor,
          brightness: Brightness.light,
          primary: settings.lightThemeColor,
          surface: const Color(0xFFF3F5F9),
          onSurface: const Color(0xFF0F172A),
        );

        final darkScheme = ColorScheme.fromSeed(
          seedColor: settings.darkThemeColor,
          brightness: Brightness.dark,
          primary: settings.darkThemeColor,
          surface: const Color(0xFF090B10),
          onSurface: Colors.white,
        );

        return MaterialApp(
          title: 'Eir · P2P Synchronized Cinema',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          locale: settings.locale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            if (deviceLocale != null) {
              for (final supported in supportedLocales) {
                if (supported.languageCode == deviceLocale.languageCode) {
                  return supported;
                }
              }
            }
            return const Locale('en', 'US');
          },
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: lightScheme,
            scaffoldBackgroundColor: const Color(0xFFF3F5F9),
            fontFamilyFallback: const [
              '-apple-system',
              'BlinkMacSystemFont',
              'Segoe UI',
              'Roboto',
              'PingFang SC',
              'Microsoft YaHei',
              'sans-serif',
            ],
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: darkScheme,
            scaffoldBackgroundColor: const Color(0xFF090B10),
            fontFamilyFallback: const [
              '-apple-system',
              'BlinkMacSystemFont',
              'Segoe UI',
              'Roboto',
              'PingFang SC',
              'Microsoft YaHei',
              'sans-serif',
            ],
          ),
          builder: (context, child) {
            return Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontFamilyFallback: [
                    '-apple-system',
                    'BlinkMacSystemFont',
                    'Segoe UI',
                    'Roboto',
                    'PingFang SC',
                    'Microsoft YaHei',
                    'sans-serif',
                  ],
                  decoration: TextDecoration.none,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const EirRootPage(),
        );
      },
    );
  }
}

class EirRootPage extends StatefulWidget {
  const EirRootPage({super.key});

  @override
  State<EirRootPage> createState() => _EirRootPageState();
}

class _EirRootPageState extends State<EirRootPage> {
  late final RoomSession _session;
  bool _isInitialized = false;
  String? _initError;
  bool _lastIsInRoom = false;

  @override
  void initState() {
    super.initState();
    _session = RoomSession();
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    setState(() {
      _isInitialized = false;
      _initError = null;
    });
    try {
      await _session.init();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _initError = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _session.roomId == null) {
            UpdateService.checkDailyUpdate(context);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString();
        setState(() {
          _isInitialized = false;
          _initError = err;
        });
      }
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _session,
        _session.screenShareService,
        AppSettings.instance,
      ]),
      builder: (context, _) {
        final screenShare = _session.screenShareService;
        final isBroadcasting = screenShare.isBroadcaster && screenShare.isActive;
        final isViewing = screenShare.isViewer;
        final isScreenSharing = isBroadcasting || isViewing;
        final isInRoom = _session.roomId != null && !isScreenSharing;
        if (isInRoom != _lastIsInRoom) {
          _lastIsInRoom = isInRoom;
          hideLiquidGlassSnackBar();
        }

        Widget page;
        if (isBroadcasting) {
          page = ScreenShareBroadcasterView(
            key: const ValueKey('screen-share-broadcaster-view'),
            session: _session,
            onStopCast: () async {
              await screenShare.stop(reason: 'user_stopped');
              await _session.leaveRoom();
            },
          );
        } else if (isViewing) {
          page = ScreenShareLiveView(
            key: const ValueKey('screen-share-live-view'),
            session: _session,
            onExit: () async {
              await screenShare.stop(reason: 'user_exit');
              await _session.leaveRoom();
            },
          );
        } else if (isInRoom) {
          page = CinemaView(
            key: ValueKey('cinema-view-${_session.roomId}'),
            session: _session,
            onLeaveRoom: () {
              setState(() {});
            },
          );
        } else {
          page = LobbyView(
            key: const ValueKey('lobby-view'),
            session: _session,
            isInitialized: _isInitialized,
            initError: _initError,
            onRetryInit: _initializeSession,
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
                  child: child,
                ),
              );
            },
            child: page,
          ),
        );
      },
    );
  }
}

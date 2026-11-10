import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'media_kit_video VideoController + Video surface rendering test with liquid glass card',
    (WidgetTester tester) async {
      // 1. Pre-warm shaders per liquid_glass_widgets skill architectural lifecycle rules
      await LiquidGlassWidgets.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('LiquidGlassWidgets.initialize timed out after 10s'),
      );

      // 2. Load sample through rootBundle into a temp file to avoid hardcoding project working directory paths.
      // Note: This integration test verifies Linux desktop rendering. Mobile and Web remain untested in this slice.
      final byteData = await rootBundle.load('assets/sample.mp4');
      final tempDir = await Directory.systemTemp.createTemp('eir_player_surface_');
      final sampleFile = File('${tempDir.path}/sample.mp4');
      await sampleFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      final player = Player();
      final controller = VideoController(player);

      try {
        // Mount minimal test UI using liquid_glass_widgets solid card container (Rule 1: solid platter for media)
        await tester.pumpWidget(
          LiquidGlassWidgets.wrap(
            brightnessResolver: Theme.maybeBrightnessOf,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              home: Scaffold(
                backgroundColor: const Color(0xFF090B10),
                body: Center(
                  child: GlassContainer.card(
                    surfaceStyle: GlassSurfaceStyle.solid,
                    shape: const LiquidRoundedSuperellipse(borderRadius: 16),
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 640,
                      height: 360,
                      child: Video(
                        controller: controller,
                        fit: BoxFit.contain,
                        controls: NoVideoControls,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester
            .pumpAndSettle(const Duration(milliseconds: 100))
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => 1,
            );

        expect(find.byType(Video), findsOneWidget);

        // Open media with explicit timeout
        final mediaUri = 'file://${sampleFile.absolute.path}';
        await player
            .open(Media(mediaUri), play: true)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw TimeoutException('player.open timed out after 10s'),
            );

        // 3. Wait for official first frame rendered API (bounded timeout)
        await controller.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw TimeoutException('waitUntilFirstFrameRendered timed out after 15s'),
        );

        // 4. Assert verifiable video output frame API evidence:
        // Do NOT accept the initial 1x1 placeholder texture. Bounded wait until native decoder
        // reports the exact sample dimensions 320x240.
        expect(
          controller.id.value,
          isNotNull,
          reason: 'Engine texture ID must be registered',
        );

        final rectDeadline = DateTime.now().add(const Duration(seconds: 10));
        while (controller.rect.value == null ||
            controller.rect.value!.width != 320.0 ||
            controller.rect.value!.height != 240.0) {
          if (DateTime.now().isAfter(rectDeadline)) {
            throw TimeoutException(
              'Video output rect failed to match sample dimensions 320x240 within 10s. '
              'Current rect: ${controller.rect.value}',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          controller.rect.value!.width,
          equals(320.0),
          reason: 'Sample video pixel width must be exactly 320',
        );
        expect(
          controller.rect.value!.height,
          equals(240.0),
          reason: 'Sample video pixel height must be exactly 240',
        );

        debugPrint(
          '[PlayerSurfaceTest] Verified video surface frame rendered: '
          'textureId=${controller.id.value}, '
          'dimensions=${controller.rect.value!.width}x${controller.rect.value!.height}',
        );

        // 5. Verify position advancement (playback actually progresses)
        final posInitial = player.state.position;
        final advanceDeadline = DateTime.now().add(const Duration(seconds: 10));
        Duration currentPos = posInitial;

        while (currentPos <= posInitial + const Duration(milliseconds: 300)) {
          if (DateTime.now().isAfter(advanceDeadline)) {
            throw TimeoutException(
              'Playback failed to advance position by 300ms within 10s. '
              'start=$posInitial, current=$currentPos',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
          currentPos = player.state.position;
        }

        expect(currentPos, greaterThan(posInitial));
        debugPrint(
          '[PlayerSurfaceTest] Verified position advancement: '
          'initial=$posInitial -> current=$currentPos',
        );

        // 6. Verify pause halts position advancement (with timeout)
        await player
            .pause()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw TimeoutException('player.pause timed out after 10s'),
            );
        await tester.pump(const Duration(milliseconds: 200));
        expect(player.state.playing, isFalse);

        final pausedPos = player.state.position;
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          player.state.position,
          equals(pausedPos),
          reason: 'Position must not advance while paused',
        );
        debugPrint(
          '[PlayerSurfaceTest] Verified pause: position held at $pausedPos',
        );

        // 7. Verify seek to a specific position (with timeout)
        const seekTarget = Duration(milliseconds: 1800);
        await player
            .seek(seekTarget)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw TimeoutException('player.seek timed out after 10s'),
            );

        final seekDeadline = DateTime.now().add(const Duration(seconds: 10));
        while ((player.state.position - seekTarget).abs() >
            const Duration(milliseconds: 400)) {
          if (DateTime.now().isAfter(seekDeadline)) {
            throw TimeoutException(
              'Seek to $seekTarget timed out. Current pos: ${player.state.position}',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          (player.state.position - seekTarget).abs(),
          lessThanOrEqualTo(const Duration(milliseconds: 400)),
        );
        debugPrint(
          '[PlayerSurfaceTest] Verified seek: target=$seekTarget, actual=${player.state.position}',
        );
      } finally {
        try {
          await player
              .dispose()
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => debugPrint('[PlayerSurfaceTest] Warning: player.dispose timed out'),
              );
        } catch (e) {
          debugPrint('[PlayerSurfaceTest] player.dispose error: $e');
        }
        try {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        } catch (_) {}
      }
    },
  );
}

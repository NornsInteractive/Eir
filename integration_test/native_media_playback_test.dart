import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/media_validation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('media_kit local asset playback', (tester) async {
    final result = await probeMediaPlayback(
      uri: 'asset:///assets/sample.mp4',
      play: true,
    );
    debugPrint(result.toString());
    expect(result.success, isTrue);
    expect(result.duration, isNotNull);
    expect(result.duration!.inMilliseconds, greaterThan(0));
    expect(result.playbackObserved, isTrue);
  });

  testWidgets('media_kit local file playback', (tester) async {
    final data = await rootBundle.load('assets/sample.mp4');
    final bytes = data.buffer.asUint8List();
    final dir = await Directory.systemTemp.createTemp('eir_media_');
    final file = File('${dir.path}/sample.mp4');
    await file.writeAsBytes(bytes, flush: true);

    try {
      final result = await probeMediaPlayback(uri: 'file://${file.path}', play: true);
      debugPrint(result.toString());
      expect(result.success, isTrue);
      expect(result.duration, isNotNull);
      expect(result.duration!.inMilliseconds, greaterThan(0));
      expect(result.playbackObserved, isTrue);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });

  testWidgets('media_kit HTTP URL playback', (tester) async {
    final data = await rootBundle.load('assets/sample.mp4');
    final bytes = data.buffer.asUint8List();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      server.listen((request) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('video', 'mp4')
          ..add(bytes)
          ..close();
      });

      final uri = 'http://127.0.0.1:${server.port}/sample.mp4';
      final result = await probeMediaPlayback(uri: uri, play: true);
      debugPrint(result.toString());
      expect(result.success, isTrue);
      expect(result.duration, isNotNull);
      expect(result.duration!.inMilliseconds, greaterThan(0));
      expect(result.playbackObserved, isTrue);
    } finally {
      await server.close(force: true);
    }
  });
}

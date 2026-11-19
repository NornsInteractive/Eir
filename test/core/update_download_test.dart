import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:eir/core/update_service.dart';

Future<Directory> _ownedDir() async {
  Directory base;
  try {
    base = await getTemporaryDirectory();
  } catch (_) {
    base = Directory.systemTemp;
  }
  return Directory(
    '${base.path}${Platform.pathSeparator}${UpdateService.updateTempDirectoryName}',
  );
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

List<int> _payload() => List<int>.generate(4096, (i) => i % 251);

String _hashOf(List<int> bytes) => crypto.sha256.convert(bytes).toString();

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  group('downloadUpdateFile checksum and size verification', () {
    test(
      'accepts matching checksum/size and returns only the finished file',
      () async {
        final payload = _payload();
        final hash = _hashOf(payload);
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.contentLength = payload.length;
          request.response.add(payload);
          await request.response.close();
        });
        addTearDown(() => server.close(force: true));

        final name = 'eir_test_${DateTime.now().microsecondsSinceEpoch}.apk';
        var received = -1;
        var total = -1;
        final file = await UpdateService.downloadUpdateFile(
          'http://127.0.0.1:${server.port}/eir.apk',
          preferredFileName: name,
          expectedSha256: 'SHA256:${hash.toUpperCase()}',
          expectedSize: payload.length,
          onProgress: (r, t, _) {
            received = r;
            total = t;
          },
        );

        expect(file, isNotNull);
        addTearDown(() async {
          if (await file!.exists()) await file.delete();
        });
        expect(await file!.readAsBytes(), payload);
        expect(file.parent.path, (await _ownedDir()).path);
        expect(file.path.endsWith(name), isTrue);
        expect(received, payload.length);
        expect(total, payload.length);

        final leftovers = (await _ownedDir())
            .listSync()
            .where((e) => e.path.contains(name) && e.path.endsWith('.part'))
            .toList();
        expect(leftovers, isEmpty);
      },
    );

    test('wrong checksum returns null and removes the partial file', () async {
      final payload = _payload();
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final name = 'eir_hash_${DateTime.now().microsecondsSinceEpoch}.apk';
      final file = await UpdateService.downloadUpdateFile(
        'http://127.0.0.1:${server.port}/eir.apk',
        preferredFileName: name,
        expectedSha256: '0' * 64,
        expectedSize: payload.length,
        onProgress: (_, __, ___) {},
      );

      expect(file, isNull);
      final dir = await _ownedDir();
      final leftovers = dir.existsSync()
          ? dir.listSync().where((e) => e.path.contains(name)).toList()
          : <FileSystemEntity>[];
      expect(leftovers, isEmpty);
    });

    test('expected size mismatch is rejected before writing', () async {
      final payload = _payload();
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final name = 'eir_size_${DateTime.now().microsecondsSinceEpoch}.apk';
      final file = await UpdateService.downloadUpdateFile(
        'http://127.0.0.1:${server.port}/eir.apk',
        preferredFileName: name,
        expectedSize: payload.length + 1,
        onProgress: (_, __, ___) {},
      );

      expect(file, isNull);
      final dir = await _ownedDir();
      final leftovers = dir.existsSync()
          ? dir.listSync().where((e) => e.path.contains(name)).toList()
          : <FileSystemEntity>[];
      expect(leftovers, isEmpty);
    });

    test(
      'declared content length mismatch with expected size is rejected',
      () async {
        final payload = _payload();
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.contentLength = payload.length + 7;
          request.response.add(payload);
          try {
            await request.response.close();
          } catch (_) {}
        });
        addTearDown(() => server.close(force: true));

        final file = await UpdateService.downloadUpdateFile(
          'http://127.0.0.1:${server.port}/eir.apk',
          expectedSize: payload.length,
          onProgress: (_, __, ___) {},
        );

        expect(file, isNull);
      },
    );

    test('invalid checksum format is rejected without a request', () async {
      final file = await UpdateService.downloadUpdateFile(
        'http://127.0.0.1:1/eir.apk',
        expectedSha256: 'not-a-sha256',
        onProgress: (_, __, ___) {},
      );
      expect(file, isNull);
    });
  });

  group('downloadUpdateFile path and scheme safety', () {
    test('unsafe preferred names fall back to a safe basename', () async {
      final payload = _payload();
      final hash = _hashOf(payload);
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final unsafeNames = <String>[
        '../evil.apk',
        r'..\evil.apk',
        '/tmp/evil.apk',
        r'C:\Windows\evil.apk',
        'con.apk',
        'bad:name.apk',
      ];

      for (final badName in unsafeNames) {
        final file = await UpdateService.downloadUpdateFile(
          'http://127.0.0.1:${server.port}/eir.apk',
          preferredFileName: badName,
          expectedSha256: hash,
          expectedSize: payload.length,
          onProgress: (_, __, ___) {},
        );
        expect(file, isNotNull, reason: 'name=$badName');
        addTearDown(() async {
          if (await file!.exists()) await file.delete();
        });
        expect(
          file!.parent.path,
          (await _ownedDir()).path,
          reason: 'name=$badName',
        );
        expect(
          file.path.split(Platform.pathSeparator).last.contains('evil'),
          isFalse,
          reason: 'name=$badName',
        );
        expect(file.path.contains('../'), isFalse, reason: 'name=$badName');
      }
    });

    test('rejects unsupported URL schemes', () async {
      final file = await UpdateService.downloadUpdateFile(
        'ftp://127.0.0.1/eir.apk',
        onProgress: (_, __, ___) {},
      );
      expect(file, isNull);
    });

    test('rejects remote plain HTTP without a checksum', () async {
      final file = await UpdateService.downloadUpdateFile(
        'http://192.0.2.1/eir.apk',
        onProgress: (_, __, ___) {},
      ).timeout(const Duration(seconds: 3));
      expect(file, isNull);
    });

    test('allows loopback HTTP without a checksum for fixtures', () async {
      final payload = _payload();
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final file = await UpdateService.downloadUpdateFile(
        'http://localhost:${server.port}/eir.apk',
        onProgress: (_, __, ___) {},
      );
      expect(file, isNotNull);
      addTearDown(() async {
        if (await file!.exists()) await file.delete();
      });
      expect(await file!.readAsBytes(), payload);
    });
  });

  group('downloadUpdateFile redirects', () {
    test('follows a bounded HTTPS-compatible redirect', () async {
      final payload = _payload();
      final server = await _startServer((request) async {
        if (request.uri.path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/file');
          await request.response.close();
          return;
        }
        request.response.statusCode = 200;
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final file = await UpdateService.downloadUpdateFile(
        'http://127.0.0.1:${server.port}/redirect',
        expectedSha256: _hashOf(payload),
        expectedSize: payload.length,
        onProgress: (_, __, ___) {},
      );
      expect(file, isNotNull);
      addTearDown(() async {
        if (await file!.exists()) await file.delete();
      });
      expect(await file!.readAsBytes(), payload);
    });

    test('stops after the redirect limit', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader, '/loop');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final file = await UpdateService.downloadUpdateFile(
        'http://127.0.0.1:${server.port}/loop',
        onProgress: (_, __, ___) {},
      );
      expect(file, isNull);
    });

    test('rejects a redirect to an unsupported scheme', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'ftp://127.0.0.1/eir.apk',
        );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final file = await UpdateService.downloadUpdateFile(
        'http://127.0.0.1:${server.port}/redirect',
        onProgress: (_, __, ___) {},
      );
      expect(file, isNull);
    });
  });

  group('installDownloadedFile Windows packages', () {
    late Directory dir;
    late bool? originalWindowsOverride;
    late Future<ProcessResult> Function(String, List<String>) originalRunner;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('eir_windows_install');
      originalWindowsOverride = UpdateService.debugWindowsPlatformOverride;
      originalRunner = UpdateService.processRunner;
      UpdateService.debugWindowsPlatformOverride = true;
      UpdateService.processRunner =
          (executable, arguments) async => ProcessResult(1, 0, '', '');
    });

    tearDown(() async {
      UpdateService.debugWindowsPlatformOverride = originalWindowsOverride;
      UpdateService.processRunner = originalRunner;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<String> writePackage(String name) async {
      final file = File('${dir.path}$Platform.pathSeparator$name');
      await file.writeAsBytes(const [1, 2, 3]);
      return file.path;
    }

    test(
      'msix family launches explorer with the path as one argument',
      () async {
        for (final extension in const [
          '.msix',
          '.msixbundle',
          '.appx',
          '.appxbundle',
        ]) {
          final path = await writePackage('Eir Update 1.0.40$extension');
          String? executable;
          List<String>? arguments;
          UpdateService.processRunner = (e, a) async {
            executable = e;
            arguments = a;
            return ProcessResult(1, 0, '', '');
          };

          expect(await UpdateService.installDownloadedFile(path), isTrue);
          expect(executable, 'explorer.exe');
          expect(arguments, <String>[path]);
        }
      },
    );

    test('nonzero opener exit is reported as failure', () async {
      final path = await writePackage('Eir.msix');
      UpdateService.processRunner =
          (executable, arguments) async => ProcessResult(1, 1, '', '');
      expect(await UpdateService.installDownloadedFile(path), isFalse);
    });

    test('opener exception is reported as failure', () async {
      final path = await writePackage('Eir.msix');
      UpdateService.processRunner = (executable, arguments) async =>
          throw const ProcessException('explorer.exe', <String>[]);
      expect(await UpdateService.installDownloadedFile(path), isFalse);
    });

    test(
      'exe and msi start through the shell opener without blocking',
      () async {
        final exePath = await writePackage('Eir Setup.exe');
        String? executable;
        List<String>? arguments;
        UpdateService.processRunner = (e, a) async {
          executable = e;
          arguments = a;
          return ProcessResult(1, 0, '', '');
        };
        expect(await UpdateService.installDownloadedFile(exePath), isTrue);
        expect(executable, 'explorer.exe');
        expect(arguments, <String>[exePath]);

        final msiPath = await writePackage('Eir Setup.msi');
        UpdateService.processRunner = (e, a) async {
          executable = e;
          arguments = a;
          return ProcessResult(1, 0, '', '');
        };
        expect(await UpdateService.installDownloadedFile(msiPath), isTrue);
        expect(executable, 'explorer.exe');
        expect(arguments, <String>[msiPath]);
      },
    );

    test('zip is rejected without launching any process', () async {
      final path = await writePackage('Eir-1.0.40-windows-x64.zip');
      var calls = 0;
      UpdateService.processRunner = (executable, arguments) async {
        calls++;
        return ProcessResult(1, 0, '', '');
      };
      expect(await UpdateService.installDownloadedFile(path), isFalse);
      expect(calls, 0);
    });
  });

  group('installDownloadedFile desktop exit status', () {
    test('linux opener nonzero exit is reported as failure', () async {
      if (Platform.isMacOS || Platform.isWindows || Platform.isAndroid) {
        return;
      }
      final dir = await Directory.systemTemp.createTemp('eir_install_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/update.apk');
      await file.writeAsBytes(const [1, 2, 3]);

      final original = UpdateService.processRunner;
      addTearDown(() => UpdateService.processRunner = original);

      UpdateService.processRunner =
          (executable, arguments) async => ProcessResult(1, 1, '', '');
      expect(await UpdateService.installDownloadedFile(file.path), isFalse);

      UpdateService.processRunner =
          (executable, arguments) async => ProcessResult(2, 0, '', '');
      expect(await UpdateService.installDownloadedFile(file.path), isTrue);
    });
  });
}

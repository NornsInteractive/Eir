import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eir/platform/signaling_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LoopbackWsServer {
  HttpServer? _http;
  final List<WebSocket> sockets = <WebSocket>[];
  final List<String> received = <String>[];

  Duration upgradeDelay = Duration.zero;
  Completer<void>? upgradeGate;
  bool rejectAfterGate = false;

  Future<int> start() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http!.listen(_onRequest, onError: (_) {}, cancelOnError: false);
    return _http!.port;
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (upgradeGate != null) {
      await upgradeGate!.future;
    }
    if (upgradeDelay != Duration.zero) {
      await Future<void>.delayed(upgradeDelay);
    }
    if (rejectAfterGate) {
      try {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
      } catch (_) {}
      return;
    }
    try {
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen(
        (dynamic d) {
          received.add(d.toString());
        },
        onDone: () {},
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void push(String value) {
    for (final ws in List<WebSocket>.from(sockets)) {
      try {
        ws.add(value);
      } catch (_) {}
    }
  }

  Future<void> closeSockets() async {
    for (final ws in List<WebSocket>.from(sockets)) {
      try {
        await ws.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await closeSockets();
    await _http?.close(force: true);
    _http = null;
  }
}

Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String reason = '',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('waitUntil timed out: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> settle([Duration d = const Duration(milliseconds: 250)]) async {
  await Future<void>.delayed(d);
}

void main() {
  group('SignalingClient loopback race regression', () {
    test('normal message round-trip', () async {
      final server = LoopbackWsServer();
      final port = await server.start();
      final client = SignalingClient();
      final conns = <bool>[];
      final msgs = <Map<String, dynamic>>[];
      client.connection.listen(conns.add);
      client.messages.listen(msgs.add);
      try {
        await client.connect('ws://127.0.0.1:$port');
        await waitUntil(
          () => conns.length == 1 && conns[0],
          reason: 'connect true',
        );
        expect(client.isConnected, isTrue);

        await client.send(<String, dynamic>{'type': 'ping', 'n': 1});
        await waitUntil(
          () => server.received.contains('{"type":"ping","n":1}'),
          reason: 'client send reaches server',
        );

        server.push(jsonEncode(<String, dynamic>{'type': 'hello', 'n': 7}));
        await waitUntil(
          () => msgs.any((m) => m['type'] == 'hello' && m['n'] == 7),
          reason: 'server push reaches client',
        );
      } finally {
        await client.disconnect();
        await server.stop();
      }
    });

    test('length limit: send boundary and throw', () async {
      final server = LoopbackWsServer();
      final port = await server.start();
      final client = SignalingClient();
      final conns = <bool>[];
      client.connection.listen(conns.add);
      try {
        await client.connect('ws://127.0.0.1:$port');
        await waitUntil(
          () => conns.length == 1 && conns[0],
          reason: 'connect true',
        );

        final base = jsonEncode(<String, dynamic>{'type': 'ping', 'pad': ''});
        final need = SignalingClient.maxMessageBytes - utf8.encode(base).length;
        final exact = <String, dynamic>{'type': 'ping', 'pad': 'x' * need};
        expect(
          utf8.encode(jsonEncode(exact)).length,
          SignalingClient.maxMessageBytes,
        );
        await client.send(exact);
        await waitUntil(
          () => server.received.any(
            (s) => s.length == SignalingClient.maxMessageBytes,
          ),
          reason: 'exact-size send reaches server',
        );

        final plus = <String, dynamic>{'type': 'ping', 'pad': 'x' * (need + 1)};
        expect(
          utf8.encode(jsonEncode(plus)).length,
          SignalingClient.maxMessageBytes + 1,
        );
        await expectLater(client.send(plus), throwsA(isA<ArgumentError>()));
        await expectLater(
          client.send(<String, dynamic>{'type': 'ping', 'pad': 'x' * 40000}),
          throwsA(isA<ArgumentError>()),
        );
        await settle(const Duration(milliseconds: 150));
        expect(
          server.received.where(
            (s) => s.length > SignalingClient.maxMessageBytes,
          ),
          isEmpty,
        );
        expect(client.isConnected, isTrue);
      } finally {
        await client.disconnect();
        await server.stop();
      }
    });

    test(
      'length limit: oversized received is dropped and stays usable',
      () async {
        final server = LoopbackWsServer();
        final port = await server.start();
        final client = SignalingClient();
        final conns = <bool>[];
        final msgs = <Map<String, dynamic>>[];
        client.connection.listen(conns.add);
        client.messages.listen(msgs.add);
        try {
          await client.connect('ws://127.0.0.1:$port');
          await waitUntil(
            () => conns.length == 1 && conns[0],
            reason: 'connect true',
          );

          server.push(
            jsonEncode(<String, dynamic>{'type': 'big', 'pad': 'x' * 40000}),
          );
          server.push('not-json-${'x' * 40000}');
          server.push('{not json');
          await settle(const Duration(milliseconds: 200));
          expect(msgs, isEmpty);

          server.push(jsonEncode(<String, dynamic>{'type': 'after', 'n': 2}));
          await waitUntil(
            () => msgs.any((m) => m['type'] == 'after'),
            reason: 'normal after oversized',
          );
          expect(msgs, hasLength(1));
          expect(conns, <bool>[true]);
          expect(client.isConnected, isTrue);
        } finally {
          await client.disconnect();
          await server.stop();
        }
      },
    );

    test('explicit disconnect emits false once; repeat is no-op', () async {
      final server = LoopbackWsServer();
      final port = await server.start();
      final client = SignalingClient();
      final conns = <bool>[];
      client.connection.listen(conns.add);
      try {
        await client.disconnect();
        await settle(const Duration(milliseconds: 150));
        expect(conns, isEmpty);
        expect(client.isConnected, isFalse);

        await client.connect('ws://127.0.0.1:$port');
        await waitUntil(
          () => conns.length == 1 && conns[0],
          reason: 'connect true',
        );

        await client.disconnect();
        await waitUntil(
          () => conns.length == 2 && !conns[1],
          reason: 'disconnect false',
        );
        expect(conns, <bool>[true, false]);
        expect(client.isConnected, isFalse);

        await client.disconnect();
        await settle(const Duration(milliseconds: 150));
        expect(conns, <bool>[true, false]);

        await client.send(<String, dynamic>{'type': 'late'});
        await expectLater(
          client.send(<String, dynamic>{'type': 'ping', 'pad': 'x' * 40000}),
          throwsA(isA<ArgumentError>()),
        );
        await settle(const Duration(milliseconds: 100));
        expect(server.received, isEmpty);
      } finally {
        await client.disconnect();
        await server.stop();
      }
    });

    test('server-initiated close emits false and clears isConnected', () async {
      final server = LoopbackWsServer();
      final port = await server.start();
      final client = SignalingClient();
      final conns = <bool>[];
      client.connection.listen(conns.add);
      try {
        await client.connect('ws://127.0.0.1:$port');
        await waitUntil(
          () => conns.length == 1 && conns[0],
          reason: 'connect true',
        );

        for (final ws in List<WebSocket>.from(server.sockets)) {
          await ws.close(1001, 'bye');
        }
        await waitUntil(
          () => conns.length == 2 && !conns[1],
          reason: 'server close false',
        );
        expect(conns, <bool>[true, false]);
        expect(client.isConnected, isFalse);
      } finally {
        await client.disconnect();
        await server.stop();
      }
    });

    test(
      'sequential reconnect emits true false true and follows new',
      () async {
        final a = LoopbackWsServer();
        final b = LoopbackWsServer();
        final pa = await a.start();
        final pb = await b.start();
        final client = SignalingClient();
        final conns = <bool>[];
        final msgs = <Map<String, dynamic>>[];
        client.connection.listen(conns.add);
        client.messages.listen(msgs.add);
        try {
          await client.connect('ws://127.0.0.1:$pa');
          await waitUntil(
            () => conns.length == 1 && conns[0],
            reason: 'A true',
          );
          a.push(jsonEncode(<String, dynamic>{'type': 'fromA', 'n': 1}));
          await waitUntil(
            () => msgs.any((m) => m['type'] == 'fromA'),
            reason: 'fromA',
          );

          await client.connect('ws://127.0.0.1:$pb');
          await waitUntil(
            () => conns.length == 3 && conns[2],
            reason: 'B true',
          );
          expect(conns, <bool>[true, false, true]);
          expect(client.isConnected, isTrue);

          await client.send(<String, dynamic>{'type': 'ping', 'tag': 'toB'});
          await waitUntil(
            () => b.received.contains('{"type":"ping","tag":"toB"}'),
            reason: 'send follows B',
          );
          expect(a.received.contains('{"type":"ping","tag":"toB"}'), isFalse);

          b.push(jsonEncode(<String, dynamic>{'type': 'fromB', 'n': 2}));
          await waitUntil(
            () => msgs.any((m) => m['type'] == 'fromB'),
            reason: 'fromB',
          );
        } finally {
          await client.disconnect();
          await a.stop();
          await b.stop();
        }
      },
    );

    test('rapid alternating burst follows last without flapping', () async {
      final a = LoopbackWsServer();
      final b = LoopbackWsServer();
      final pa = await a.start();
      final pb = await b.start();
      final client = SignalingClient();
      final conns = <bool>[];
      final msgs = <Map<String, dynamic>>[];
      client.connection.listen(conns.add);
      client.messages.listen(msgs.add);
      try {
        final f1 = client.connect('ws://127.0.0.1:$pa');
        final f2 = client.connect('ws://127.0.0.1:$pb');
        final f3 = client.connect('ws://127.0.0.1:$pa');
        await Future.wait([f1, f2, f3]);
        await waitUntil(
          () => conns.isNotEmpty && conns.last,
          reason: 'burst true',
        );
        await settle(const Duration(milliseconds: 300));
        expect(conns, <bool>[true]);
        expect(client.isConnected, isTrue);

        await client.send(<String, dynamic>{
          'type': 'ping',
          'tag': 'afterBurst',
        });
        await waitUntil(
          () => a.received.contains('{"type":"ping","tag":"afterBurst"}'),
          reason: 'send follows last A',
        );
        expect(
          b.received.contains('{"type":"ping","tag":"afterBurst"}'),
          isFalse,
        );

        a.push(jsonEncode(<String, dynamic>{'type': 'fromA'}));
        b.push(jsonEncode(<String, dynamic>{'type': 'staleB'}));
        await waitUntil(
          () => msgs.any((m) => m['type'] == 'fromA'),
          reason: 'fromA delivered',
        );
        await settle(const Duration(milliseconds: 200));
        expect(msgs.any((m) => m['type'] == 'staleB'), isFalse);
        expect(conns, <bool>[true]);
        expect(client.isConnected, isTrue);
      } finally {
        await client.disconnect();
        await a.stop();
        await b.stop();
      }
    });

    test('old close and old data do not affect new connection', () async {
      final a = LoopbackWsServer();
      final b = LoopbackWsServer();
      final pa = await a.start();
      final pb = await b.start();
      final client = SignalingClient();
      final conns = <bool>[];
      final msgs = <Map<String, dynamic>>[];
      client.connection.listen(conns.add);
      client.messages.listen(msgs.add);
      try {
        await client.connect('ws://127.0.0.1:$pa');
        await waitUntil(() => conns.length == 1 && conns[0], reason: 'A');
        await client.connect('ws://127.0.0.1:$pb');
        await waitUntil(() => conns.length == 3 && conns[2], reason: 'B');
        expect(conns, <bool>[true, false, true]);

        await a.closeSockets();
        await settle(const Duration(milliseconds: 300));
        expect(conns, <bool>[true, false, true]);
        expect(client.isConnected, isTrue);

        a.push(jsonEncode(<String, dynamic>{'type': 'stale', 'n': 99}));
        b.push(jsonEncode(<String, dynamic>{'type': 'fresh', 'n': 3}));
        await waitUntil(
          () => msgs.any((m) => m['type'] == 'fresh'),
          reason: 'fresh',
        );
        await settle(const Duration(milliseconds: 150));
        expect(msgs.any((m) => m['type'] == 'stale'), isFalse);
        expect(conns, <bool>[true, false, true]);
        expect(client.isConnected, isTrue);

        await client.send(<String, dynamic>{'type': 'ping', 'tag': 'new'});
        await waitUntil(
          () => b.received.contains('{"type":"ping","tag":"new"}'),
          reason: 'new still sends to B',
        );
      } finally {
        await client.disconnect();
        await a.stop();
        await b.stop();
      }
    });

    test('old ready does not overwrite new: slow old fast new', () async {
      final slow = LoopbackWsServer();
      slow.upgradeDelay = const Duration(milliseconds: 250);
      final fast = LoopbackWsServer();
      final pSlow = await slow.start();
      final pFast = await fast.start();
      final client = SignalingClient();
      final conns = <bool>[];
      client.connection.listen(conns.add);
      try {
        final g1 = client.connect('ws://127.0.0.1:$pSlow');
        final g2 = client.connect('ws://127.0.0.1:$pFast');
        await Future.wait([g1, g2]);
        await waitUntil(
          () => conns.isNotEmpty && conns.last,
          reason: 'fast true',
        );
        await settle(const Duration(milliseconds: 300));
        expect(conns, <bool>[true]);
        expect(client.isConnected, isTrue);

        await client.send(<String, dynamic>{'type': 'ping', 'tag': 'slowRace'});
        await waitUntil(
          () => fast.received.contains('{"type":"ping","tag":"slowRace"}'),
          reason: 'follows fast',
        );
        expect(slow.received, isEmpty);
      } finally {
        await client.disconnect();
        await slow.stop();
        await fast.stop();
      }
    });

    test('old failure late does not disturb new success', () async {
      final bad = LoopbackWsServer();
      bad.upgradeGate = Completer<void>();
      bad.rejectAfterGate = true;
      final good = LoopbackWsServer();
      final pBad = await bad.start();
      final pGood = await good.start();
      final client = SignalingClient();
      final conns = <bool>[];
      final msgs = <Map<String, dynamic>>[];
      client.connection.listen(conns.add);
      client.messages.listen(msgs.add);
      try {
        final fOld = client.connect('ws://127.0.0.1:$pBad');
        final fNew = client.connect('ws://127.0.0.1:$pGood');
        await fNew;
        await waitUntil(
          () => conns.isNotEmpty && conns.last,
          reason: 'new true',
        );
        expect(client.isConnected, isTrue);

        bad.upgradeGate!.complete();
        await expectLater(fOld, throwsA(isA<WebSocketChannelException>()));
        await settle(const Duration(milliseconds: 300));
        expect(conns, <bool>[true]);
        expect(client.isConnected, isTrue);

        await client.send(<String, dynamic>{
          'type': 'ping',
          'tag': 'afterFail',
        });
        await waitUntil(
          () => good.received.contains('{"type":"ping","tag":"afterFail"}'),
          reason: 'still follows good',
        );
        good.push(jsonEncode(<String, dynamic>{'type': 'stillOk'}));
        await waitUntil(
          () => msgs.any((m) => m['type'] == 'stillOk'),
          reason: 'still receives',
        );
        expect(conns, <bool>[true]);
      } finally {
        await client.disconnect();
        await bad.stop();
        await good.stop();
      }
    });

    test('permanently pending handshake does not block sequential connect to good', () async {
      final bad = LoopbackWsServer();
      bad.upgradeGate = Completer<void>();
      bad.rejectAfterGate = false;
      final good = LoopbackWsServer();
      final pBad = await bad.start();
      final pGood = await good.start();
      final client = SignalingClient();
      final conns = <bool>[];
      final msgs = <Map<String, dynamic>>[];
      client.connection.listen(conns.add);
      client.messages.listen(msgs.add);
      final fOld = client.connect('ws://127.0.0.1:$pBad');
      fOld.then((_) {}, onError: (_) {});
      try {
        await waitUntil(
          () => client.isConnected,
          reason: 'old pending channel assigned',
        );
        await settle(const Duration(milliseconds: 150));
        expect(conns, isEmpty,
            reason: 'pending handshake must not emit true yet');
        await client
            .connect('ws://127.0.0.1:$pGood')
            .timeout(const Duration(seconds: 3));
        await waitUntil(
          () => conns.length == 2 && !conns[0] && conns[1],
          reason: 'disconnect false then good true',
        );
        expect(conns, <bool>[false, true]);
        expect(client.isConnected, isTrue);
        await client.send(<String, dynamic>{'type': 'ping', 'tag': 'afterPending'});
        await waitUntil(
          () => good.received.contains('{"type":"ping","tag":"afterPending"}'),
          reason: 'send follows good',
        );
        expect(bad.received, isEmpty);
        good.push(jsonEncode(<String, dynamic>{'type': 'fromGood', 'n': 5}));
        await waitUntil(
          () => msgs.any((m) => m['type'] == 'fromGood'),
          reason: 'receives from good',
        );
        expect(conns, <bool>[false, true]);
        expect(client.isConnected, isTrue);
      } finally {
        if (bad.upgradeGate != null && !bad.upgradeGate!.isCompleted) {
          bad.upgradeGate!.complete();
        }
        await client.disconnect();
        await bad.stop();
        await good.stop();
      }
    });

    test('sequential awaited failure does not block next success', () async {
      final bad = LoopbackWsServer();
      bad.rejectAfterGate = true;
      final good = LoopbackWsServer();
      final pBad = await bad.start();
      final pGood = await good.start();
      final client = SignalingClient();
      final conns = <bool>[];
      client.connection.listen(conns.add);
      try {
        await expectLater(
          client.connect('ws://127.0.0.1:$pBad'),
          throwsA(isA<WebSocketChannelException>()),
        );
        await waitUntil(
          () => conns.length == 1 && !conns[0],
          reason: 'bad false',
        );
        expect(client.isConnected, isFalse);

        await client.connect('ws://127.0.0.1:$pGood');
        await waitUntil(
          () => conns.length == 2 && conns[1],
          reason: 'good true',
        );
        expect(conns, <bool>[false, true]);
        expect(client.isConnected, isTrue);
      } finally {
        await client.disconnect();
        await bad.stop();
        await good.stop();
      }
    });
  });
}

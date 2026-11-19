import 'dart:ffi';
import 'dart:typed_data';

import 'package:eir/core/transport/tailcat_ffi.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<int> freed;

  setUp(() {
    freed = <int>[];
    // Stand in for the library-owned allocator: production resolves
    // TailcatFree from the same library that allocated the buffer.
    TailcatTransport.freeOverride = (ptr) {
      freed.add(ptr.address);
      calloc.free(ptr);
    };
  });

  tearDown(() {
    TailcatTransport.freeOverride = null;
  });

  group('TailcatTransport session routing and buffer ownership', () {
    test('delivers text from a live route and releases the buffer once',
        () async {
      final transport = TailcatTransport();
      final received = transport.textStream.first;
      transport.debugRegisterRoute(42);

      final ptr = calloc<Uint8>(5);
      final address = ptr.address;
      ptr.asTypedList(5).setAll(0, 'hello'.codeUnits);
      TailcatTransport.debugReceiveData(42, 0, ptr, 5);

      expect(await received, 'hello');
      expect(freed, <int>[address]);
      expect(TailcatTransport.debugHasRoute(42), isTrue);
      await transport.close();
    });

    test('delivers binary from a live route and releases the buffer once',
        () async {
      final transport = TailcatTransport();
      final received = transport.binaryStream.first;
      transport.debugRegisterRoute(43);

      final ptr = calloc<Uint8>(3);
      final address = ptr.address;
      ptr.asTypedList(3).setAll(0, [1, 2, 3]);
      TailcatTransport.debugReceiveData(43, 1, ptr, 3);

      expect(await received, Uint8List.fromList([1, 2, 3]));
      expect(freed, <int>[address]);
      await transport.close();
    });

    test('routes state to the live transport and releases info once', () async {
      final transport = TailcatTransport();
      var connected = 0;
      transport.onConnected = () => connected++;
      transport.debugRegisterRoute(7);

      final info = 'listening'.toNativeUtf8();
      final address = info.address;
      TailcatTransport.debugReceiveState(7, 1, info);

      expect(transport.isOpen, isTrue);
      expect(connected, 1);
      expect(freed, <int>[address]);
      await transport.close();
    });

    test('late queued callbacks after close free buffers without delivery',
        () async {
      final transport = TailcatTransport();
      final received = <String>[];
      transport.textStream.listen(received.add);
      transport.debugRegisterRoute(9);
      await transport.close();

      expect(TailcatTransport.debugHasRoute(9), isFalse);

      final ptr = calloc<Uint8>(4);
      final address = ptr.address;
      ptr.asTypedList(4).setAll(0, 'late'.codeUnits);
      expect(
          () => TailcatTransport.debugReceiveData(9, 0, ptr, 4), returnsNormally);
      expect(received, isEmpty);
      expect(freed, <int>[address]);

      final lateInfo = 'late'.toNativeUtf8();
      final infoAddress = lateInfo.address;
      expect(() => TailcatTransport.debugReceiveState(9, 1, lateInfo),
          returnsNormally);
      expect(freed, <int>[address, infoAddress]);
    });

    test('callback for an unknown session still releases its buffer', () {
      final ptr = calloc<Uint8>(1);
      final address = ptr.address;
      ptr.asTypedList(1)[0] = 7;
      expect(() => TailcatTransport.debugReceiveData(999, 1, ptr, 1),
          returnsNormally);
      expect(freed, <int>[address]);
    });

    test('delivery failure does not escape native boundary and frees once',
        () async {
      final transport = TailcatTransport();
      transport.debugRegisterRoute(11);

      final ptr = calloc<Uint8>(2);
      final address = ptr.address;
      ptr.asTypedList(2).setAll(0, [0xff, 0xfe]); // invalid UTF-8
      expect(() => TailcatTransport.debugReceiveData(11, 0, ptr, 2),
          returnsNormally);
      expect(freed, <int>[address]);
      await transport.close();
    });

    test('close removes the route and is idempotent', () async {
      final transport = TailcatTransport();
      transport.debugRegisterRoute(5);
      await transport.close();
      expect(TailcatTransport.debugHasRoute(5), isFalse);
      await expectLater(transport.close(), completes);
    });
  });

  group('TailcatTransport send result propagation', () {
    test('throws on negative native send results', () {
      final ptr = calloc<Uint8>(3);
      ptr.asTypedList(3).setAll(0, [1, 2, 3]);

      expect(
        () => TailcatTransport.sendFrame(
            (id, isBinary, data, len) => -1, 1, 1, ptr, 3),
        throwsStateError,
      );
      expect(
        () => TailcatTransport.sendFrame(
            (id, isBinary, data, len) => -2, 1, 1, ptr, 3),
        throwsStateError,
      );

      calloc.free(ptr);
    });

    test('returns normally on successful native send', () {
      final ptr = calloc<Uint8>(3);
      ptr.asTypedList(3).setAll(0, [1, 2, 3]);

      expect(
        TailcatTransport.sendFrame(
            (id, isBinary, data, len) => 0, 1, 1, ptr, 3),
        0,
      );

      calloc.free(ptr);
    });
  });
}

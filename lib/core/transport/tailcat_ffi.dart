import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'room_transport.dart';

typedef DataCallbackNative = Void Function(
    Uint64 id, Int32 isBinary, Pointer<Uint8> data, Int32 len);
typedef StateCallbackNative = Void Function(
    Uint64 id, Int32 state, Pointer<Utf8> info);

final class TailcatStartServerReturn extends Struct {
  external Pointer<Utf8> r0;
  @UintPtr()
  external int r1;
}

typedef TailcatStartServerC = TailcatStartServerReturn Function(
    Pointer<NativeFunction<DataCallbackNative>> dataCb,
    Pointer<NativeFunction<StateCallbackNative>> stateCb);
typedef TailcatStartServerDart = TailcatStartServerReturn Function(
    Pointer<NativeFunction<DataCallbackNative>> dataCb,
    Pointer<NativeFunction<StateCallbackNative>> stateCb);

typedef TailcatStartClientC = Int64 Function(
    Pointer<Utf8> serverAddr,
    Pointer<NativeFunction<DataCallbackNative>> dataCb,
    Pointer<NativeFunction<StateCallbackNative>> stateCb);
typedef TailcatStartClientDart = int Function(
    Pointer<Utf8> serverAddr,
    Pointer<NativeFunction<DataCallbackNative>> dataCb,
    Pointer<NativeFunction<StateCallbackNative>> stateCb);

typedef TailcatSendC = Int32 Function(
    Int64 id, Int32 isBinary, Pointer<Uint8> data, Int32 length);
typedef TailcatSendDart = int Function(
    int id, int isBinary, Pointer<Uint8> data, int length);

typedef TailcatIsDirectC = Int32 Function(Int64 id);
typedef TailcatIsDirectDart = int Function(int id);

typedef TailcatCloseC = Void Function(Int64 id);
typedef TailcatCloseDart = void Function(int id);

// Go hands Dart buffers it allocated with C.CString/C.CBytes. They must be
// released by the same library's allocator, not by Dart's calloc (a different
// heap on Windows).
typedef TailcatFreeC = Void Function(Pointer<Void> ptr);
typedef TailcatFreeDart = void Function(Pointer<Void> ptr);

class TailcatTransport implements RoomTransport {
  static DynamicLibrary? _lib;
  static bool _libLoaded = false;

  static DynamicLibrary? get lib {
    if (_libLoaded) return _lib;
    _libLoaded = true;
    try {
      if (Platform.isLinux) {
        _lib = DynamicLibrary.open('libtailcat.so');
      } else if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libtailcat.so');
      } else if (Platform.isWindows) {
        _lib = DynamicLibrary.open('tailcat.dll');
      } else if (Platform.isMacOS) {
        _lib = DynamicLibrary.open('libtailcat.dylib');
      }
    } catch (_) {
      _lib = null;
    }
    return _lib;
  }

  static bool get isAvailable => lib != null;

  // One listener pair for the whole process. Native callbacks are posted to
  // the isolate's event loop, so a per-session callable could be closed while
  // a call is still queued. Keeping these alive for the process lifetime lets
  // every late call be routed and its C buffer released safely.
  static NativeCallable<DataCallbackNative>? _dataCallable;
  static NativeCallable<StateCallbackNative>? _stateCallable;

  // Session id -> live transport. Listener callbacks and start/close all run
  // on the isolate's event loop, so this map needs no lock.
  static final Map<int, TailcatTransport> _routes = <int, TailcatTransport>{};

  static TailcatFreeDart? _freeFn;

  // Test seam: inject the allocator to exercise routing and free-once logic
  // without loading a native library (which may be an older binary in tests).
  @visibleForTesting
  static TailcatFreeDart? freeOverride;

  static void _ensureNativeAllocator() {
    if (_freeFn != null) return;
    final dylib = lib;
    if (dylib == null) {
      throw UnsupportedError('Tailcat native library not available');
    }
    try {
      _freeFn = dylib.lookupFunction<TailcatFreeC, TailcatFreeDart>('TailcatFree');
    } catch (e) {
      // A stale native library must fail loudly, not fall back to calloc.free
      // on a buffer from a foreign heap.
      throw UnsupportedError(
          'Tailcat native library is missing TailcatFree; rebuild native/tailcat ($e)');
    }
  }

  static void _ensureCallables() {
    _dataCallable ??= NativeCallable<DataCallbackNative>.listener(_nativeData);
    _stateCallable ??= NativeCallable<StateCallbackNative>.listener(_nativeState);
  }

  static void _releaseNative(Pointer<Void> ptr) {
    if (ptr == nullptr) return;
    try {
      final fn = freeOverride ?? _freeFn;
      if (fn != null) fn(ptr);
    } catch (_) {
      // A callback must never throw back into native code. Production
      // resolves the allocator before starting a session, so this only
      // guards unexpected teardown states.
    }
  }

  // Native entry points. Delivery and free follow the same route: a live
  // transport receives the payload, and the buffer is released exactly once
  // even when the route is gone or delivery throws.
  static void _nativeData(int id, int isBinary, Pointer<Uint8> data, int len) {
    try {
      final transport = _routes[id];
      if (transport != null) {
        transport._deliverData(isBinary, data, len);
      }
    } catch (_) {
      // Swallow so a Dart exception cannot cross the native boundary.
    }
    _releaseNative(data.cast<Void>());
  }

  static void _nativeState(int id, int state, Pointer<Utf8> info) {
    try {
      final transport = _routes[id];
      if (transport != null) {
        transport._deliverState(state, info);
      }
    } catch (_) {
      // Swallow so a Dart exception cannot cross the native boundary.
    }
    _releaseNative(info.cast<Void>());
  }

  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _binaryController =
      StreamController<Uint8List>.broadcast();

  int _sessionId = 0;
  bool _isOpen = false;
  bool _closed = false;
  String _badgeLabel = 'Tailcat (Connecting)';

  void Function()? onConnected;
  void Function()? onDisconnected;

  @override
  TransportEngineType get type => TransportEngineType.tailcat;

  @override
  bool get isOpen => _isOpen;

  @override
  bool get isDirectP2p {
    final dylib = lib;
    if (dylib == null || _sessionId == 0) return false;
    final isDirectFn = dylib.lookupFunction<TailcatIsDirectC, TailcatIsDirectDart>(
        'TailcatIsDirect');
    return isDirectFn(_sessionId) == 1;
  }

  @override
  String get badgeLabel =>
      isDirectP2p ? 'P2P (Tailcat)' : (isOpen ? 'DERP Relay (Tailcat)' : _badgeLabel);

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  Stream<Uint8List> get binaryStream => _binaryController.stream;

  void _deliverData(int isBinary, Pointer<Uint8> data, int len) {
    if (_closed || data == nullptr || len <= 0) return;
    final bytes = Uint8List.fromList(data.asTypedList(len));
    if (isBinary == 1) {
      if (!_binaryController.isClosed) _binaryController.add(bytes);
    } else {
      if (!_textController.isClosed) _textController.add(utf8.decode(bytes));
    }
  }

  void _deliverState(int state, Pointer<Utf8> info) {
    if (_closed) return;
    if (state == 1) {
      _isOpen = true;
      _badgeLabel = isDirectP2p ? 'P2P (Tailcat)' : 'DERP Relay (Tailcat)';
      onConnected?.call();
    } else if (state == 2) {
      _isOpen = false;
      _badgeLabel = 'Tailcat (Disconnected)';
      onDisconnected?.call();
    }
  }

  @visibleForTesting
  static void debugReceiveData(int id, int isBinary, Pointer<Uint8> data, int len) {
    _nativeData(id, isBinary, data, len);
  }

  @visibleForTesting
  static void debugReceiveState(int id, int state, Pointer<Utf8> info) {
    _nativeState(id, state, info);
  }

  @visibleForTesting
  void debugRegisterRoute(int id) {
    _sessionId = id;
    _routes[id] = this;
  }

  @visibleForTesting
  static bool debugHasRoute(int id) => _routes.containsKey(id);

  @visibleForTesting
  static int sendFrame(
      TailcatSendDart send, int id, int isBinary, Pointer<Uint8> data, int len) {
    final result = send(id, isBinary, data, len);
    if (result < 0) {
      throw StateError('tailcat send failed ($result)');
    }
    return result;
  }

  Future<String> startServer() async {
    final dylib = lib;
    if (dylib == null) {
      throw UnsupportedError('Tailcat native library not available');
    }
    _ensureNativeAllocator();
    _ensureCallables();

    final startServerFn = dylib.lookupFunction<TailcatStartServerC,
        TailcatStartServerDart>('TailcatStartServer');
    final ret = startServerFn(
        _dataCallable!.nativeFunction, _stateCallable!.nativeFunction);
    final addrPtr = ret.r0;
    final addr = addrPtr == nullptr ? '' : addrPtr.toDartString();
    if (addrPtr != nullptr) _freeFn!(addrPtr.cast<Void>());
    if (ret.r1 != 0) {
      _sessionId = ret.r1;
      // Listener callbacks are delivered on the event loop, so registration
      // completes before any callback posted during the native call arrives.
      _routes[_sessionId] = this;
    }
    return addr;
  }

  Future<void> startClient(String serverAddr) async {
    final dylib = lib;
    if (dylib == null) {
      throw UnsupportedError('Tailcat native library not available');
    }
    _ensureNativeAllocator();
    _ensureCallables();

    final startClientFn = dylib.lookupFunction<TailcatStartClientC,
        TailcatStartClientDart>('TailcatStartClient');
    final addrPtr = serverAddr.toNativeUtf8();
    try {
      _sessionId = startClientFn(
          addrPtr, _dataCallable!.nativeFunction, _stateCallable!.nativeFunction);
      if (_sessionId != 0) {
        _routes[_sessionId] = this;
      }
      if (_isOpen) {
        onConnected?.call();
      }
    } finally {
      calloc.free(addrPtr);
    }
  }

  @override
  Future<void> sendText(String text) async {
    final bytes = utf8.encode(text);
    await sendBinary(Uint8List.fromList(bytes), isBinary: false);
  }

  @override
  Future<void> sendBinary(Uint8List bytes, {bool isBinary = true}) async {
    final dylib = lib;
    if (dylib == null || _sessionId == 0 || !_isOpen) return;

    final sendFn =
        dylib.lookupFunction<TailcatSendC, TailcatSendDart>('TailcatSend');
    final ptr = calloc<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      TailcatTransport.sendFrame(
          sendFn, _sessionId, isBinary ? 1 : 0, ptr, bytes.length);
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _isOpen = false;
    final dylib = lib;
    final sessionId = _sessionId;
    _sessionId = 0;
    // Remove the route first: a callback already queued by native code will
    // release its C buffer without reaching this closed transport.
    if (sessionId != 0) _routes.remove(sessionId);
    try {
      if (dylib != null && sessionId != 0) {
        final closeFn = dylib.lookupFunction<TailcatCloseC, TailcatCloseDart>('TailcatClose');
        closeFn(sessionId);
      }
    } finally {
      if (!_textController.isClosed) await _textController.close();
      if (!_binaryController.isClosed) await _binaryController.close();
    }
  }
}

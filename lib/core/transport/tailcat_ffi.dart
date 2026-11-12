import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
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

  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _binaryController =
      StreamController<Uint8List>.broadcast();

  int _sessionId = 0;
  bool _isOpen = false;
  String _badgeLabel = 'Tailcat (Connecting)';
  NativeCallable<DataCallbackNative>? _dataCallable;
  NativeCallable<StateCallbackNative>? _stateCallable;

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
      isDirectP2p ? 'P2P (Tailcat)' : (isOpen ? 'DERP 中继 (Tailcat)' : _badgeLabel);

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  Stream<Uint8List> get binaryStream => _binaryController.stream;

  void _onData(int id, int isBinary, Pointer<Uint8> data, int len) {
    if (_sessionId == 0 && id != 0) {
      _sessionId = id;
    }
    if (id != _sessionId) return;
    final bytes = Uint8List.fromList(data.asTypedList(len));
    if (isBinary == 1) {
      _binaryController.add(bytes);
    } else {
      _textController.add(utf8.decode(bytes));
    }
  }

  void _onState(int id, int state, Pointer<Utf8> info) {
    if (_sessionId == 0 && id != 0) {
      _sessionId = id;
    }
    if (id != _sessionId) return;
    if (state == 1) {
      _isOpen = true;
      _badgeLabel = isDirectP2p ? 'P2P (Tailcat)' : 'DERP 中继 (Tailcat)';
      onConnected?.call();
    } else if (state == 2) {
      _isOpen = false;
      _badgeLabel = 'Tailcat (Disconnected)';
      onDisconnected?.call();
    }
  }

  Future<String> startServer() async {
    final dylib = lib;
    if (dylib == null) {
      throw UnsupportedError('Tailcat native library not available');
    }

    _dataCallable = NativeCallable<DataCallbackNative>.listener(_onData);
    _stateCallable = NativeCallable<StateCallbackNative>.listener(_onState);

    final startServerFn = dylib.lookupFunction<TailcatStartServerC,
        TailcatStartServerDart>('TailcatStartServer');
    final ret = startServerFn(
        _dataCallable!.nativeFunction, _stateCallable!.nativeFunction);
    final addr = ret.r0.toDartString();
    calloc.free(ret.r0);
    if (ret.r1 != 0) {
      _sessionId = ret.r1;
    }
    return addr;
  }

  Future<void> startClient(String serverAddr) async {
    final dylib = lib;
    if (dylib == null) {
      throw UnsupportedError('Tailcat native library not available');
    }

    _dataCallable = NativeCallable<DataCallbackNative>.listener(_onData);
    _stateCallable = NativeCallable<StateCallbackNative>.listener(_onState);

    final startClientFn = dylib.lookupFunction<TailcatStartClientC,
        TailcatStartClientDart>('TailcatStartClient');
    final addrPtr = serverAddr.toNativeUtf8();
    try {
      _sessionId = startClientFn(
          addrPtr, _dataCallable!.nativeFunction, _stateCallable!.nativeFunction);
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
      sendFn(_sessionId, isBinary ? 1 : 0, ptr, bytes.length);
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  Future<void> close() async {
    _isOpen = false;
    final dylib = lib;
    if (dylib != null && _sessionId != 0) {
      final closeFn =
          dylib.lookupFunction<TailcatCloseC, TailcatCloseDart>('TailcatClose');
      closeFn(_sessionId);
      _sessionId = 0;
    }
    _dataCallable?.close();
    _stateCallable?.close();
    await _textController.close();
    await _binaryController.close();
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'room_transport.dart';

class TailcatTransport implements RoomTransport {
  static bool get isAvailable => false;

  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _binaryController =
      StreamController<Uint8List>.broadcast();

  void Function()? onConnected;
  void Function()? onDisconnected;

  @override
  TransportEngineType get type => TransportEngineType.tailcat;

  @override
  bool get isOpen => false;

  @override
  bool get isDirectP2p => false;

  @override
  String get badgeLabel => 'Tailcat (Unavailable)';

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  Stream<Uint8List> get binaryStream => _binaryController.stream;

  Future<String> startServer() async {
    throw UnsupportedError('Tailcat native library not available');
  }

  Future<void> startClient(String serverAddr) async {
    throw UnsupportedError('Tailcat native library not available');
  }

  @override
  Future<void> sendText(String text) async {}

  @override
  Future<void> sendBinary(Uint8List bytes, {bool isBinary = true}) async {}

  @override
  Future<void> close() async {
    await _textController.close();
    await _binaryController.close();
  }
}

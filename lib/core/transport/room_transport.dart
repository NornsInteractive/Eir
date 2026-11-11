import 'dart:typed_data';

enum TransportEngineType {
  webrtc,
  tailcat,
}

abstract class RoomTransport {
  TransportEngineType get type;
  bool get isOpen;
  bool get isDirectP2p;
  String get badgeLabel;

  Future<void> sendText(String text);
  Future<void> sendBinary(Uint8List bytes);
  Stream<String> get textStream;
  Stream<Uint8List> get binaryStream;

  Future<void> close();
}

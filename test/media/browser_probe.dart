import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

import 'package:eir/media/local_media_service.dart';
const int _fixtureBytes = 9 * 1024 * 1024 + 17;

LocalMediaService? _source;
LocalMediaService? _recv;
MediaManifest? _manifest;
Uint8List? _bytes;

@JS()
extension type ProbeApi._(JSObject _) implements JSObject {
  factory ProbeApi() => ProbeApi._(JSObject());
  external set start(JSFunction? value);
  external set uri(JSString? value);
  external set size(JSNumber? value);
  external set mediaId(JSString? value);
  external set dispose(JSFunction? value);
  external set sentBytes(JSFunction? value);
}

@JS()
extension type ProbeGlobal._(JSObject _) implements JSObject {
  external set __eirMediaProbe(ProbeApi value);
}

@JS('globalThis')
external ProbeGlobal get probeGlobal;

Uint8List makeBytes() => Uint8List.fromList(List<int>.generate(_fixtureBytes, (i) => (i * 37 + 11) % 256));

JSPromise<JSString> _startJs() => _start().toJS;
Future<JSString> _start() async {
  if (_source != null) {
    final uri = _recv!.uriFor(_manifest!.mediaId);
    final b = _bytes!;
    return '{"uri":"$uri","size":${b.length},"chunkCount":${_manifest!.chunkCount},"mediaId":"${_manifest!.mediaId}"}'.toJS;
  }
  final bytes = makeBytes();
  late LocalMediaService source;
  late LocalMediaService recv;
  source = LocalMediaService(
    sendControl: (m) => recv.onControl(m),
    sendBinary: (f) async => recv.onBinary(f),
    bufferedAmount: () => 0,
    localDeviceId: 'a' * 64,
  );
  recv = LocalMediaService(
    sendControl: (m) => source.onControl(m),
    sendBinary: (f) async => source.onBinary(f),
    bufferedAmount: () => 0,
    localDeviceId: 'b' * 64,
    manifestAuthorizer: (_) async => true,
  );
  final manifest = await source.registerFile(XFile.fromData(bytes, name: 'dummy.bin', mimeType: 'video/mp4'));
  await recv.registerRemoteManifest(manifest.toJson(), trustedByCore: true);
  await recv.start();
  final uri = recv.uriFor(manifest.mediaId);
  _source = source;
  _recv = recv;
  _manifest = manifest;
  _bytes = bytes;
  final api = _currentApi!;
  api.uri = uri.toJS;
  api.size = bytes.length.toJS;
  api.mediaId = manifest.mediaId.toJS;
  return '{"uri":"$uri","size":${bytes.length},"chunkCount":${manifest.chunkCount},"mediaId":"${manifest.mediaId}"}'.toJS;
}

JSPromise<JSBoolean> _disposeJs() => _dispose().then((v) => v.toJS).toJS;
JSPromise<JSNumber> _sentBytesJs() => _sentBytes().then((v) => v.toJS).toJS;
Future<num> _sentBytes() async => _source?.transferTelemetry.sentBytes ?? 0;
Future<bool> _dispose() async {
  final source = _source;
  final recv = _recv;
  _source = null;
  _recv = null;
  _manifest = null;
  _bytes = null;
  if (source != null) await source.dispose();
  if (recv != null) await recv.dispose();
  _currentApi?.uri = null;
  _currentApi?.mediaId = null;
  _currentApi?.size = null;
  return true;
}

ProbeApi? _currentApi;

Future<void> main() async {
  // NOTE: the ServiceWorker bridge (eir_media_bridge.js) is loaded by the
  // production path itself — LocalMediaService.start() -> _WebHost.start()
  // injects it via createScriptElement + appendToBody. This probe only sets
  // up the __eirMediaProbe API; it relies on that same production path.
  final api = ProbeApi();
  _currentApi = api;
  probeGlobal.__eirMediaProbe = api;
  api.start = _startJs.toJS;
  api.dispose = _disposeJs.toJS;
  api.sentBytes = _sentBytesJs.toJS;
}

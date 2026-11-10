import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'media_format.dart';
import 'media_limits.dart';
import 'media_server_interface.dart';

@JS('document.createElement')
external JSObject createScriptElement(JSString tagName);

@JS('document.body.appendChild')
external void appendToBody(JSObject node);

@JS('location.origin')
external String get locationOrigin;

@JS('navigator.serviceWorker.controller.postMessage')
external void postSwMessage(JSObject message);

@JS()
extension type EirMediaQuery._(JSObject _) implements JSObject {
  static EirMediaQuery fromInterop(JSObject js) => EirMediaQuery._(js);
  external String get type;
  external String get method;
  external String? get mediaId;
  external int? get length;
  external int? get start;
  external String? get requestId;
}

@JS()
extension type EirMediaResponse._(JSObject _) implements JSObject {
  factory EirMediaResponse() => EirMediaResponse.fromInterop(JSObject());
  static EirMediaResponse fromInterop(JSObject js) {
    final r = EirMediaResponse._(js);
    r.status = 404.toJS;
    r.size = 0.toJS;
    return r;
  }
  external set status(JSNumber v);
  external set size(JSNumber v);
  external set start(JSNumber v);
  external set end(JSNumber v);
  external set contentType(JSString v);
  external set buffer(JSAny? v);
  external set cancelled(JSBoolean v);
}

@JS()
extension type EirGlobal._(JSObject _) implements JSObject {
  external String? get eirMediaState;
  external set __eirMediaFetch(JSFunction? value);
}

@JS('globalThis')
external EirGlobal get eirGlobal;

@JS('eirMediaRegister')
external JSPromise<JSBoolean> eirMediaRegister(JSString token);

@JS('eirMediaRevoke')
external void eirMediaRevoke(JSString token);

@JS()
extension type EirCancelled._(JSObject _) implements JSObject {
  external bool has(JSString value);
}

@JS()
extension type JsScript._(JSObject _) implements JSObject {
  static JsScript fromInterop(JSObject js) => JsScript._(js);
  external set src(JSString value);
}

@JS()
extension type JsTypedArray._(JSObject _) implements JSObject {
  static JsTypedArray fromInterop(JSObject js) => JsTypedArray._(js);
  external JSObject get buffer;
}

@JS('__eirMediaCancelled')
external EirCancelled? get cancelledSet;

MediaServerHost createMediaServerHost({
  required MediaWriteRange writeRange,
  required MediaReadRangeBytes readRangeBytes,
  required MediaManifestLookup manifestFor,
  required String token,
}) {
  return _WebHost(readRangeBytes: readRangeBytes, manifestFor: manifestFor, token: token);
}

class _WebHost implements MediaServerHost {
  _WebHost({required this.readRangeBytes, required this.manifestFor, required this.token});

  final MediaReadRangeBytes readRangeBytes;
  final MediaManifestLookup manifestFor;
  final String token;
  String _origin = '';

  @override
  String get baseUrl => _origin.isEmpty ? '' : '$_origin/';

  @override
  String uriFor(String mediaId) {
    final mime = manifestFor(mediaId)?.mime ?? kMediaMime;
    return '$_origin/eir-media/$token/$mediaId.${mediaExtensionForMime(mime)}';
  }

  @override
  Future<void> start() async {
    _origin = locationOrigin;
    if (_origin.isEmpty || _origin == 'null') throw MediaException('source_offline', 'no origin');
    final script = JsScript.fromInterop(createScriptElement('script'.toJS));
    script.src = 'eir_media_bridge.js'.toJS;
    appendToBody(script as JSObject);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    String? state;
    while (DateTime.now().isBefore(deadline)) {
      state = eirGlobal.eirMediaState;
      if (state == 'controlled') break;
      if (state != null && state.startsWith('error:')) throw MediaException('source_offline', state);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    state = eirGlobal.eirMediaState;
    if (state != 'controlled') throw MediaException('source_offline', 'service worker not controlled');
    eirGlobal.__eirMediaFetch = _handleJs.toJS;
    final ok = (await eirMediaRegister(token.toJS).toDart).toDart;
    if (!ok) throw MediaException('source_offline', 'service worker registration failed');
  }

  JSPromise<EirMediaResponse> _handleJs(EirMediaQuery req) => _handle(req).toJS;

  Future<EirMediaResponse> _handle(EirMediaQuery req) async {
    final response = EirMediaResponse();
    final mediaId = req.mediaId ?? '';
    if (req.type != 'eir-media-query') {
      response.status = 400.toJS;
      return response;
    }
    final method = req.method;
    if (method == 'meta') {
      final manifest = manifestFor(mediaId);
      if (manifest == null) return response;
      response.status = 200.toJS;
      response.size = manifest.size.toJS;
      response.contentType = manifest.mime.toJS;
      return response;
    }
    if (method == 'range') {
      final length = req.length ?? 0;
      final start = req.start ?? -1;
      final requestId = req.requestId ?? '';
      if (length <= 0 || length > 65536 || start < 0) {
        response.status = 416.toJS;
        return response;
      }
      if (cancelledSet?.has(requestId.toJS) == true) {
        response.status = 499.toJS;
        response.cancelled = true.toJS;
        return response;
      }
      final manifest = manifestFor(mediaId);
      if (manifest == null) return response;
      final end = (start + length).clamp(0, manifest.size);
      try {
        final bytes = await readRangeBytes(mediaId, start, end);
        final jsU8 = Uint8List.fromList(bytes).toJS;
        response.status = (end > start ? 206 : 200).toJS;
        response.size = manifest.size.toJS;
        response.start = start.toJS;
        response.end = end.toJS;
        response.contentType = manifest.mime.toJS;
        response.buffer = JsTypedArray.fromInterop(jsU8 as JSObject).buffer;
      } on MediaException catch (e) {
        response.status = (e.code == 'invalid_range' ? 416 : 504).toJS;
      }
      return response;
    }
    response.status = 405.toJS;
    return response;
  }

  @override
  Future<void> stop() async {
    try {
      eirMediaRevoke(token.toJS);
    } catch (_) {}
  }
}

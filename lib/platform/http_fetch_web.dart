import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web browser HTTP GET text fetcher using package:web window.fetch
Future<String?> httpGetText(String url, {Duration timeout = const Duration(seconds: 8)}) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart.timeout(timeout);
    if (!response.ok) return null;
    final textPromise = await response.text().toDart.timeout(timeout);
    return textPromise.toDart;
  } catch (_) {
    return null;
  }
}

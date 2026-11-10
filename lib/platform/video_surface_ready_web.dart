import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> waitForVideoSurface(Duration timeout) async {
  final ready = Completer<void>();
  void check() {
    // Eir has one Player per document. Detect its real platform-view mount;
    // metadata can become available while the element is still detached.
    final videos = web.document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      final video = videos.item(i) as web.HTMLVideoElement;
      if (video.isConnected &&
          video.readyState >= web.HTMLMediaElement.HAVE_METADATA &&
          video.videoWidth > 0 &&
          video.videoHeight > 0) {
        if (!ready.isCompleted) ready.complete();
        return;
      }
    }
  }

  final observer = web.MutationObserver(
    ((JSArray<web.MutationRecord> _, web.MutationObserver __) => check()).toJS,
  );
  observer.observe(
    web.document,
    web.MutationObserverInit(childList: true, subtree: true),
  );
  final metadata = ((web.Event _) => check()).toJS;
  web.document.addEventListener('loadedmetadata', metadata, true.toJS);
  try {
    check();
    await ready.future.timeout(timeout);
  } finally {
    observer.disconnect();
    web.document.removeEventListener('loadedmetadata', metadata, true.toJS);
  }
}

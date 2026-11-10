(() => {
  if (window.eirMediaState) return;
  window.eirMediaState = 'registering';
  let activeToken = null;

  async function init() {
    if (!('serviceWorker' in navigator)) { window.eirMediaState = 'error:no-service-worker'; return; }
    const reg = await navigator.serviceWorker.register('eir_media_sw.js');
    await navigator.serviceWorker.ready;
    if (reg.waiting) reg.waiting.postMessage({ type: 'SKIP_WAITING' });
    const expected = new URL('eir_media_sw.js', document.baseURI).href;
    if (navigator.serviceWorker.controller?.scriptURL !== expected) {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          navigator.serviceWorker.removeEventListener('controllerchange', changed);
          reject(new Error('media-worker-control-timeout'));
        }, 4000);
        function changed() {
          if (navigator.serviceWorker.controller?.scriptURL !== expected) return;
          clearTimeout(timer);
          navigator.serviceWorker.removeEventListener('controllerchange', changed);
          resolve();
        }
        navigator.serviceWorker.addEventListener('controllerchange', changed);
        changed();
      });
    }
    window.eirMediaState = 'controlled';
  }
  init().catch((e) => { window.eirMediaState = 'error:' + (e && e.message ? e.message : 'sw-register'); });

  window.eirMediaRegister = async (token) => {
    if (!navigator.serviceWorker || !navigator.serviceWorker.controller) return false;
    const value = String(token);
    activeToken = value;
    const ch = new MessageChannel();
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        resolve(false);
      }, 3000);
      ch.port1.onmessage = (e) => {
        clearTimeout(timer);
        resolve(e.data && e.data.ok === true && e.data.token === value);
      };
      navigator.serviceWorker.controller.postMessage({ type: 'eir-media-register', token: value }, [ch.port2]);
    });
  };
  window.eirMediaUnregister = (token) => {
    if (activeToken !== String(token)) return false;
    const value = activeToken;
    activeToken = null;
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({ type: 'eir-media-unregister', token: value });
    }
    return true;
  };
  window.eirMediaRevoke = (token) => {
    if (!window.eirMediaUnregister(token)) return;
    window.__eirMediaFetch = null;
    window.__eirMediaCancelled = new Set();
  };
  window.__eirMediaCancelled = new Set();

  if (!navigator.serviceWorker) return;
  navigator.serviceWorker.addEventListener('message', (e) => {
    const source = e.source;
    const controller = navigator.serviceWorker.controller;
    if (!source || !controller || source.scriptURL !== controller.scriptURL) return;
    if (!e.data || e.data.type !== 'eir-media-query') return;
    const port = e.ports && e.ports[0];
    const fn = window.__eirMediaFetch;
    const request = e.data;
    if (!port || request.token !== activeToken || typeof fn !== 'function') {
      if (port) port.postMessage({ status: 404 });
      return;
    }
    if (request.method === 'cancel') {
      if (request.requestId && window.__eirMediaCancelled) window.__eirMediaCancelled.add(String(request.requestId));
      port.postMessage({ status: 204 });
      return;
    }
    Promise.resolve(fn(request)).then((r) => {
      if (r && r.cancelled) { port.postMessage({ status: 499 }); return; }
      if (!r) { port.postMessage({ status: 404 }); return; }
      const buffer = r.buffer || null;
      port.postMessage(r, buffer ? [buffer] : []);
    }).catch(() => { if (port) port.postMessage({ status: 504 }); });
  });
})();

self.addEventListener('install', () => { self.skipWaiting(); });
self.addEventListener('activate', (e) => { e.waitUntil(self.clients.claim()); });

const registrations = new Map();
const MAX_STREAM_CHUNK = 65536;

function reply(e, message) {
  if (e.ports && e.ports[0] && typeof e.ports[0].postMessage === 'function') {
    e.ports[0].postMessage(message);
    return;
  }
  if (e.source && typeof e.source.postMessage === 'function') e.source.postMessage(message);
}

self.addEventListener('message', (e) => {
  const d = e.data || {};
  const clientId = e.source && e.source.id;
  if (d.type === 'eir-media-register') {
    const token = typeof d.token === 'string' && d.token.length > 0 ? d.token : null;
    if (!clientId) {
      reply(e, { type: 'eir-media-registered', token: token || '', ok: false });
      return;
    }
    if (token) registrations.set(clientId, token);
    else registrations.delete(clientId);
    reply(e, { type: 'eir-media-registered', token: token || '', ok: Boolean(token) });
    return;
  }
  if (!clientId) return;
  if (d.type === 'eir-media-unregister' && registrations.get(clientId) === d.token) {
    registrations.delete(clientId);
  }
});

function parseMediaPath(url) {
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts.length !== 3 || parts[0] !== 'eir-media') return null;
  const segment = parts[2];
  const dot = segment.lastIndexOf('.');
  if (dot <= 0) return null;
  const mediaId = segment.slice(0, dot);
  const extension = segment.slice(dot + 1).toLowerCase();
  if (!/^[a-z0-9]{1,12}$/.test(extension)) return null;
  if (!/^[a-f0-9]{64}$/.test(mediaId) || !/^[a-f0-9]{64}$/.test(parts[1])) return null;
  return { token: parts[1], mediaId };
}

function parseRange(header, size) {
  if (header == null || header === '') return { start: 0, end: size, isPartial: false };
  if (!header.startsWith('bytes=')) return null;
  const spec = header.slice(6);
  if (spec.includes(',')) return null;
  const dash = spec.indexOf('-');
  if (dash < 0) return null;
  const a = spec.slice(0, dash);
  const b = spec.slice(dash + 1);
  if (a === '' && b === '') return null;
  if (a === '') {
    const suffix = Number(b);
    if (!Number.isInteger(suffix) || suffix <= 0) return null;
    return { start: Math.max(0, size - suffix), end: size, isPartial: true };
  }
  const start = Number(a);
  if (!Number.isInteger(start) || start < 0 || start >= size) return null;
  let end = b === '' ? size : Number(b) + 1;
  if (!Number.isInteger(end)) return null;
  end = Math.min(size, Math.max(0, end));
  if (end <= start) return null;
  return { start, end, isPartial: true };
}

function askPage(event, target, payload) {
  return new Promise((resolve, reject) => {
    const ch = new MessageChannel();
    const timer = setTimeout(() => reject(new Error('media response timeout')), 32000);
    ch.port1.onmessage = (ev) => { clearTimeout(timer); resolve(ev.data || null); };
    target.postMessage(Object.assign({ type: 'eir-media-query' }, payload), [ch.port2]);
  });
}

async function page(event, client, payload) {
  try {
    return await askPage(event, client, payload);
  } catch (_) {
    return null;
  }
}

function buildResponse(status, size, start, end, contentType, body) {
  const headers = new Headers();
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Content-Type', contentType || 'video/mp4');
  headers.set('Cache-Control', 'no-store');
  if (status === 200 || status === 206) {
    headers.set('Content-Length', String(end - start));
    if (status === 206) headers.set('Content-Range', `bytes ${start}-${end - 1}/${size}`);
  } else if (status === 416) {
    headers.set('Content-Range', `bytes */${size}`);
    headers.set('Content-Length', '0');
  }
  return new Response(body || null, { status, headers });
}

async function handle(event, info) {
  const client = event.clientId ? await self.clients.get(event.clientId) : null;
  if (!client || (registrations.has(client.id) && registrations.get(client.id) !== info.token)) {
    return buildResponse(404, 0, 0, 0, null, null);
  }
  if (event.request.method !== 'GET' && event.request.method !== 'HEAD') return buildResponse(405, 0, 0, 0, null, null);
  // A restarted worker loses its Map; the live page also verifies this token.
  const meta = await page(event, client, { token: info.token, mediaId: info.mediaId, method: 'meta' });
  if (!meta || meta.status !== 200 || !Number.isFinite(meta.size) || meta.size < 0) return buildResponse(404, 0, 0, 0, null, null);
  const size = meta.size;
  const contentType = meta.contentType || 'video/mp4';
  const method = event.request.method;
  const rangeHeader = event.request.headers.get('range');
  const parsed = parseRange(rangeHeader, size);
  if (!parsed) return buildResponse(416, size, 0, 0, contentType, null);
  const { start, end, isPartial } = parsed;
  const status = isPartial ? 206 : 200;
  if (method === 'HEAD') return buildResponse(status, size, start, end, contentType, null);
  let offset = start;
  let currentMediaRequestId = '';
  const body = new ReadableStream({
    async pull(controller) {
      if (offset >= end) {
        controller.close();
        return;
      }
      const len = Math.min(MAX_STREAM_CHUNK, end - offset);
      // The page's cancellation set survives worker restarts.
      const requestId = crypto.randomUUID();
      currentMediaRequestId = requestId;
      const chunk = await page(event, client, { token: info.token, mediaId: info.mediaId, method: 'range', start: offset, length: len, requestId });
      if (!chunk || (chunk.status !== 200 && chunk.status !== 206) || !chunk.buffer) {
        controller.error(new Error('media range failed'));
        return;
      }
      const u8 = new Uint8Array(chunk.buffer);
      if (u8.byteLength === 0 || offset + u8.byteLength > end) {
        controller.error(new Error('invalid media chunk'));
        return;
      }
      controller.enqueue(u8);
      offset += u8.byteLength;
      currentMediaRequestId = '';
    },
    cancel() {
      page(event, client, { token: info.token, mediaId: info.mediaId, method: 'cancel', requestId: currentMediaRequestId });
    },
  });
  return buildResponse(status, size, start, end, contentType, body);
}

self.addEventListener('fetch', (event) => {
  const info = parseMediaPath(new URL(event.request.url));
  if (!info) return;
  event.respondWith(handle(event, info));
});

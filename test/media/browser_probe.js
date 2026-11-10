// Backend-only browser capability probe for the ServiceWorker media bridge.
// Requires:
//   1. flutter build web --target test/media/browser_probe.dart --release
//   2. Serve ./build/web on http://127.0.0.1:<port>
//   3. Playwright + Chromium
//   PROBE_URL=http://127.0.0.1:8123/ \
//   CHROME_EXECUTABLE=/path/to/chrome \
//   PLAYWRIGHT_MODULE=/path/to/node_modules/playwright \
//   node test/media/browser_probe.js
const assert = require('assert');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/tmp/eir-browser-tools/node_modules/playwright');

const url = process.env.PROBE_URL || 'http://127.0.0.1:8123/';
const executablePath = process.env.CHROME_EXECUTABLE || '/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome';

function byteAt(i) { return (i * 37 + 11) & 255; }

function expectedBytes(start, len) {
  const out = new Uint8Array(len);
  for (let i = 0; i < len; i++) out[i] = byteAt(start + i);
  return out;
}

async function startProbe(page) {
  await page.goto(url, { waitUntil: 'load', timeout: 30000 });
  await page.waitForFunction(() => '__eirMediaProbe' in globalThis && typeof globalThis.__eirMediaProbe.start === 'function', null, { timeout: 30000 });
  const result = await page.evaluate(() => globalThis.__eirMediaProbe.start());
  return JSON.parse(result);
}

async function fetchRange(page, uri, range, { abortAfterBytes = null } = {}) {
  return page.evaluate(async ({ uri, range, abortAfterBytes }) => {
    const res = await fetch(uri, { headers: { Range: range } });
    const out = {
      status: res.status,
      contentRange: res.headers.get('content-range'),
      contentLength: res.headers.get('content-length'),
      acceptRanges: res.headers.get('accept-ranges'),
      cacheControl: res.headers.get('cache-control'),
      chunks: 0,
      maxChunk: 0,
      received: 0,
      aborted: false,
    };
    if (res.body == null) return out;
    const reader = res.body.getReader();
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        out.chunks += 1;
        out.maxChunk = Math.max(out.maxChunk, value.byteLength);
        out.received += value.byteLength;
        if (abortAfterBytes != null && out.received >= abortAfterBytes) {
          out.aborted = true;
          await reader.cancel();
          return out;
        }
      }
    } catch (e) {
      out.aborted = true;
      out.error = String(e);
    }
    return out;
  }, { uri, range, abortAfterBytes });
}

async function fetchSmall(page, uri, range) {
  return page.evaluate(async ({ uri, range }) => {
    const res = await fetch(uri, { headers: { Range: range } });
    const bytes = new Uint8Array(await res.arrayBuffer());
    return {
      status: res.status,
      contentRange: res.headers.get('content-range'),
      contentLength: res.headers.get('content-length'),
      acceptRanges: res.headers.get('accept-ranges'),
      bytes: Array.from(bytes),
    };
  }, { uri, range });
}

(async () => {
  const browser = await chromium.launch({ executablePath, headless: true });
  const contextA = await browser.newContext();
  const contextB = await browser.newContext();
  const contextC = await browser.newContext();
  const pageA = await contextA.newPage();
  const pageB = await contextB.newPage();
  const pageC = await contextC.newPage();
  try {
    const a = await startProbe(pageA);
    const b = await startProbe(pageB);
    assert.equal(typeof a.uri, 'string');
    assert.equal(typeof b.uri, 'string');
    assert.notEqual(a.uri, b.uri);
    assert.equal(a.size, b.size);

    const t1 = await fetchRange(pageA, a.uri, 'bytes=0-1023');
    assert.equal(t1.status, 206);
    assert.equal(t1.received, 1024);
    // The SW enqueues at most MAX_STREAM_CHUNK (65536) per pull; the fetch
    // reader's own chunking is NOT guaranteed to match enqueue boundaries,
    // so assert the upper bound rather than an exact read-chunk size.
    assert.ok(t1.maxChunk <= 65536);
    assert.match(t1.contentRange, /^bytes 0-1023\//);
    assert.equal(t1.acceptRanges, 'bytes');

    const t2 = await fetchRange(pageA, a.uri, 'bytes=1020-');
    assert.equal(t2.status, 206);
    assert.equal(t2.received, a.size - 1020);
    assert.ok(t2.maxChunk <= 65536);
    // The number of fetch read() chunks is not bound to the SW's enqueue
    // count (browser may coalesce/split), so only assert delivery happened.
    assert.ok(t2.chunks >= 1);

    const clamp = await fetchRange(pageA, a.uri, `bytes=${a.size - 10}-99999999`);
    assert.equal(clamp.status, 206);
    assert.equal(clamp.received, 10);
    assert.equal(clamp.contentRange, `bytes ${a.size - 10}-${a.size - 1}/${a.size}`);

    const suffix = await fetchRange(pageA, a.uri, 'bytes=-257');
    assert.equal(suffix.status, 206);
    assert.equal(suffix.received, 257);

    const bad1 = await fetchRange(pageA, a.uri, `bytes=${a.size}-${a.size + 99}`);
    assert.equal(bad1.status, 416);
    const bad2 = await fetchRange(pageA, a.uri, 'bytes=abc-def');
    assert.equal(bad2.status, 416);
    const bad3 = await fetchRange(pageA, a.uri, 'bytes=1-2,3-4');
    assert.equal(bad3.status, 416);

    const prefix = await fetchSmall(pageA, a.uri, 'bytes=0-31');
    assert.equal(prefix.status, 206);
    assert.deepEqual(Uint8Array.from(prefix.bytes), expectedBytes(0, 32));
    const tail = await fetchSmall(pageA, a.uri, 'bytes=-64');
    assert.equal(tail.status, 206);
    assert.deepEqual(Uint8Array.from(tail.bytes.slice(tail.bytes.length - 32)), expectedBytes(a.size - 32, 32));

    const cross = await fetchRange(pageB, a.uri, 'bytes=0-15');
    assert.equal(cross.status, 404);

    // Fresh page/service/cache for partial-pull cancellation proof.
    const c = await startProbe(pageC);
    const sentBefore = await pageC.evaluate(() => globalThis.__eirMediaProbe.sentBytes());
    const cancelTest = await fetchRange(pageC, c.uri, 'bytes=0-', { abortAfterBytes: 4096 });
    assert.equal(cancelTest.aborted, true);
    assert.ok(cancelTest.maxChunk <= 65536);
    const sentAfter = await pageC.evaluate(() => globalThis.__eirMediaProbe.sentBytes());
    assert.ok(sentAfter - sentBefore < 512 * 1024, 'partial transfer after abort');
    await pageC.evaluate(() => globalThis.__eirMediaProbe.dispose());

    const unrelated = await pageA.evaluate(async () => (await fetch('/unrelated-path.bin')).status);
    assert.equal(unrelated, 404);

    await pageA.evaluate(() => globalThis.__eirMediaProbe.dispose());
    const afterRevoke = await fetchRange(pageA, a.uri, 'bytes=0-15');
    assert.equal(afterRevoke.status, 404);

    console.log(JSON.stringify({ ok: true, size: a.size, boundedChunk: t2.maxChunk, abortDeltaBytes: sentAfter - sentBefore }));
  } finally {
    await contextA.close();
    await contextB.close();
    await contextC.close();
    await browser.close();
  }
})().catch((e) => {
  console.error('browser probe failed:', e);
  process.exit(1);
});

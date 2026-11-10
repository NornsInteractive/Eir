// Eir Web — Retry Connection E2E (non-dissolving signaling restart).
//
// Reproduces a real connection loss on the SAME signaling URL without disbanding
// the room: SIGKILLs the signaling server by its real PID (found via `ps`),
// confirms TCP is down, waits for the bounded auto-retry to exhaust, then:
//   1. asserts the real "Retry Connection" entry actually APPEARS (terminal
//      disconnected state) — FAIL if it never appears;
//   2. restarts the SAME URL and asserts the app does NOT silently auto-recover
//      (the retry entry must still be present) — auto-recovery is never accepted
//      as a substitute for the click;
//   3. clicks the real product retry button and asserts reconnection;
//   4. asserts room / identity / playlist preservation and real dual-end decode
//      plus shared control after the manual retry.
// No injected business state, no product test hooks, no URL change.
//
// Env overrides:
//   EIR_WEB_APP   app URL           (default http://127.0.0.1:8730/)
//   EIR_SIGNALING signaling ws URL  (default ws://127.0.0.1:8799)
//   EIR_SIGNALING_PORT  port        (default 8799)
//   EIR_REPO      repo root for `dart run server/signaling_server.dart` (default cwd)
//   EIR_CHROME    chromium executable
//   EIR_PLAYWRIGHT_PATH playwright module path
//
// Result: /tmp/eir-web-test/retry-result.json (+ screenshots). Exit code 2 if
// any hard assertion FAILs.
// NOTE: this script kills/restarts the loopback signaling server on the given
// port; run it only against your own test server. listenPid() filters by the
// exact test PORT in ps args; it never kills a different signaling port.
const { chromium } = require(process.env.EIR_PLAYWRIGHT_PATH || '/tmp/eir-browser-tools/node_modules/playwright');
const { execSync, spawn } = require('child_process');
const net = require('net');
const fs = require('fs');

const APP = process.env.EIR_WEB_APP || 'http://127.0.0.1:8730/';
const CHROME = process.env.EIR_CHROME || '/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome';
const SIGNALING = process.env.EIR_SIGNALING || 'ws://127.0.0.1:8799';
const PORT = Number(process.env.EIR_SIGNALING_PORT || 8799);
const REPO = process.env.EIR_REPO || process.cwd();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const out = { startedAt: new Date().toISOString(), timeline: [], steps: [] };
const rec = (n, s, d) => { out.steps.push({ name: n, status: s, detail: d || '' }); console.log(`[${s}] ${n}${d ? ' :: ' + d : ''}`); };

function listenPid(port) {
  const p = Number(port ?? PORT);
  if (!Number.isInteger(p) || p <= 0 || p > 65535) return null;
  try {
    const s = execSync("ps -eo pid,args | grep signaling_server.dart | grep -v grep", { shell: '/bin/bash' }).toString().trim();
    if (!s) return null;
    const re = new RegExp(`signaling_server\\.dart\\s+${p}(?:\\s|$)`);
    const line = s.split('\n').find((l) => re.test(l));
    if (!line) return null;
    return Number(line.trim().split(/\s+/)[0]);
  } catch (e) { return null; }
}
function pidArgs(pid) {
  try {
    return execSync(`ps -p ${pid} -o args=`, { shell: '/bin/bash' }).toString().trim();
  } catch (e) { return ''; }
}
function tcpOpen(port) {
  return new Promise((resolve) => {
    const s = net.connect(port, '127.0.0.1');
    s.setTimeout(1500);
    s.on('connect', () => { s.destroy(); resolve(true); });
    s.on('timeout', () => { s.destroy(); resolve(false); });
    s.on('error', () => resolve(false));
  });
}
function killSignaling() {
  const pid = listenPid(PORT);
  if (!pid) return null;
  const args = pidArgs(pid);
  const re = new RegExp(`signaling_server\\.dart\\s+${PORT}(?:\\s|$)`);
  if (!re.test(args)) return null;
  try { process.kill(pid, 'SIGKILL'); } catch (e) {}
  return pid;
}
function startSignaling() {
  const p = spawn('dart', ['run', 'server/signaling_server.dart', String(PORT), '127.0.0.1'], { cwd: REPO, detached: true, stdio: 'ignore' });
  p.unref();
  return p.pid;
}
async function waitTcp(open, timeoutMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const o = await tcpOpen(PORT);
    if (o === open) return true;
    await sleep(400);
  }
  return false;
}
async function newCtx(browser) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-US' });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: APP });
  await ctx.addInitScript((u) => { try { localStorage.setItem('flutter.eir_setting_signaling_url', JSON.stringify(u)); } catch (e) {} }, SIGNALING);
  return ctx;
}
async function activate(page) {
  await page.goto(APP, { waitUntil: 'load', timeout: 60000 });
  await page.waitForFunction(() => !!document.querySelector('flt-semantics-placeholder'), null, { timeout: 30000 }).catch(() => {});
  await page.evaluate(() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window })); });
  await page.waitForFunction(() => document.querySelectorAll('flt-semantics').length > 3, null, { timeout: 20000 }).catch(() => {});
}
async function state(page) {
  return page.evaluate(() => {
    const els = Array.from(document.querySelectorAll('flt-semantics'));
    const all = els.map((e) => (e.textContent || '').trim()).join('\n');
    const labels = els.map((e) => e.getAttribute('aria-label') || '').join('\n');
    // The real retry entry is a Semantics(button,label:'Retry Connection') whose
    // child Text is exactly that string; match the leaf so the root container
    // (which concatenates the whole tree) cannot produce a false positive.
    const retryBtn = /(^|\n)(Retry Connection|重试连接)(\n|$)/.test(all) || /(^|\n)(Retry Connection|重试连接)(\n|$)/.test(labels);
    return {
      connected: /P2P Connected|P2P 已直连/.test(all),
      reconnecting: /Reconnecting\.\.\.|正在重连/.test(all),
      discBanner: /Room connection lost and auto-reconnect ended|自动重连已(结束|停止)/.test(all),
      discLabel: /(^|\n)Disconnected(\n|$)|(^|\n)未连接(\n|$)/.test(all),
      retryBtn,
      errSig: /signaling_unavailable|信令|Signaling|Error \(/i.test(all),
    };
  });
}
async function firstInput(page) {
  return page.evaluate(() => { const ins = Array.from(document.querySelectorAll('input')).map((i) => { const r = i.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, vis: r.x >= 0 && r.x < 1280 && r.y >= 0 && r.y < 900 }; }).filter((o) => o.vis).sort((a, b) => b.w - a.w); return ins[0] || null; });
}
async function vstate(page) { return page.evaluate(() => { const v = document.querySelector('video'); return v ? { ct: +v.currentTime.toFixed(2), dur: v.duration, paused: v.paused, rs: v.readyState } : null; }); }
async function roomIds(page) {
  return page.evaluate(() => {
    const texts = Array.from(document.querySelectorAll('flt-semantics')).map((e) => (e.textContent || '').trim());
    return { room: texts.find((t) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(t)) || '', dev: texts.find((t) => /^[0-9a-f]{64}$/.test(t)) || '' };
  });
}
async function addUrlPlay(page) {
  await page.getByRole('button', { name: 'Add Media' }).first().click(); await sleep(1000);
  await page.evaluate(() => { const els = Array.from(document.querySelectorAll('flt-semantics')); const el = els.find((e) => (e.textContent || '').includes('Network Video URL')); if (el) el.click(); }); await sleep(300);
  const g = await page.evaluate(() => { const i = document.querySelectorAll('input')[0]; const r = i.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  await page.mouse.click(g.x + g.w / 2, g.y + g.h / 2); await sleep(250);
  await page.keyboard.type('http://127.0.0.1:8730/sample.mp4', { delay: 5 }); await sleep(250);
  await page.getByRole('button', { name: 'Confirm' }).first().click(); await sleep(2000);
  await page.getByRole('button', { name: /Switch to this item/i }).first().click(); await sleep(2500);
  await page.getByRole('button', { name: /Play \(Shared\)/i }).first().click(); await sleep(3000);
}

(async () => {
  if (!(await tcpOpen(PORT))) { startSignaling(); await waitTcp(true, 20000); }
  rec('server-up', (await tcpOpen(PORT)) ? 'PASS' : 'FAIL', `signaling up, pid=${listenPid(PORT)}`);

  const browser = await chromium.launch({ executablePath: CHROME, headless: false, args: ['--no-sandbox', '--disable-dev-shm-usage', '--autoplay-policy=no-user-gesture-required', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const ctxA = await newCtx(browser); const A = await ctxA.newPage(); A.setDefaultTimeout(12000);
  const ctxB = await newCtx(browser); const B = await ctxB.newPage(); B.setDefaultTimeout(12000);
  await activate(A);
  await A.getByText('Create Cinema Room', { exact: false }).waitFor({ timeout: 20000 });
  await A.getByRole('button', { name: /Create Cinema Room/i }).first().click();
  await A.getByText('P2P Connected', { exact: false }).waitFor({ timeout: 25000 }).catch(() => {});
  await A.getByRole('button', { name: 'Copy Invite' }).first().click(); await sleep(700);
  const invite = await A.evaluate(() => navigator.clipboard.readText()).catch(() => '');
  await activate(B);
  await B.getByText('Join Cinema', { exact: false }).waitFor({ timeout: 20000 });
  const bi = await firstInput(B); await B.mouse.click(bi.x + bi.w / 2, bi.y + bi.h / 2); await sleep(250);
  await B.keyboard.type(invite, { delay: 2 }); await sleep(300);
  await B.getByRole('button', { name: /Join Cinema/i }).first().click();
  await B.getByText('P2P Connected', { exact: false }).waitFor({ timeout: 25000 }).catch(() => {});
  rec('pre-connected', (await state(A)).connected && (await state(B)).connected ? 'PASS' : 'WARN', 'both connected before disruption');

  await addUrlPlay(A);
  // Real dual-end position deviation sample during normal buffered playback.
  // NOTE: local two-context sampling only; NOT a remote-150ms or frame-accuracy measurement.
  const samples = [];
  for (let i = 0; i < 6; i++) { const va = await vstate(A); const vb = await vstate(B); if (va && vb) samples.push({ a: va.ct, b: vb.ct, d: +(va.ct - vb.ct).toFixed(3) }); await sleep(500); }
  const deltas = samples.map((s) => Math.abs(s.d));
  out.deviationSample = { samples, maxAbsDelta: deltas.length ? Math.max(...deltas) : null, note: 'local two-context sampling; not remote-150ms nor frame-accuracy' };
  rec('position-deviation-sample', samples.length ? 'INFO' : 'WARN', `n=${samples.length} max|A-B|=${out.deviationSample.maxAbsDelta}s (local sampling only)`);
  const aPl = await A.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '');
  await A.getByRole('button', { name: 'Session Info' }).first().click(); await sleep(600);
  const idA = await roomIds(A);
  await B.getByRole('button', { name: 'Session Info' }).first().click(); await sleep(600);
  const idB = await roomIds(B);
  out.pre = { room: idA.room, devA: idA.dev, devB: idB.dev, playlist: aPl, aVid: await vstate(A), bVid: await vstate(B) };
  rec('pre-state', idA.room && aPl.includes('(1)') ? 'PASS' : 'WARN', `room=${idA.room.slice(0, 8)}… playlist="${aPl}" aVid=${JSON.stringify(out.pre.aVid)}`);

  // ---- REAL NON-DISSOLVING STOP (same URL, no disband) ----
  const killedPid = killSignaling();
  const down = await waitTcp(false, 8000);
  rec('signaling-killed', (killedPid && down) ? 'PASS' : 'FAIL', `killed pid=${killedPid}, tcp-down=${down}`);

  // Bounded reconnect: core performs 3 attempts (~1.1s/2.1s/4.2s + socket
  // timeouts) then MUST enter the terminal disconnected state and expose the
  // real retry entry. Poll up to 55s.
  let retrySeen = false, discSeen = false, reconnSeen = false, tRetry = null;
  const t0 = Date.now();
  while (Date.now() - t0 < 55000) {
    const sa = await state(A);
    const t = Math.round((Date.now() - t0) / 1000);
    out.timeline.push({ phase: 'outage', t, ...sa });
    console.log(`t=${t}s`, JSON.stringify(sa));
    if (sa.reconnecting) reconnSeen = true;
    if (sa.discBanner) discSeen = true;
    if (sa.retryBtn) { retrySeen = true; tRetry = t; break; }
    await sleep(1500);
  }
  rec('reconnect-observed', reconnSeen ? 'PASS' : 'WARN', `reconnecting banner seen=${reconnSeen}`);
  rec('retry-button-appears', retrySeen ? 'PASS' : 'FAIL', `real Retry Connection button present=${retrySeen} at ${tRetry}s (bounded exhaustion)`);
  rec('disconnected-banner', discSeen ? 'PASS' : 'FAIL', `terminal disconnected banner present=${discSeen}`);
  await A.screenshot({ path: '/tmp/eir-web-test/retry3-disconnected.png' }).catch(() => {});

  if (!retrySeen) {
    // Explicit FAIL. Auto-recovery on restart is NEVER accepted as a substitute
    // for a real click on the product retry entry.
    out.summary = { result: 'FAIL', note: 'Retry Connection button did not appear after bounded auto-retry exhaustion; click path unverified.' };
    fs.writeFileSync('/tmp/eir-web-test/retry-result.json', JSON.stringify(out, null, 2));
    await browser.close();
    console.log('\n=== retry-result.json written:', JSON.stringify(out.summary));
    process.exitCode = 2;
    return;
  }

  // Restart the SAME URL (no URL change, no room rebuild).
  startSignaling();
  const up = await waitTcp(true, 25000);
  rec('signaling-restarted', up ? 'PASS' : 'FAIL', `same URL ws://127.0.0.1:8799, tcp-up=${up} pid=${listenPid(PORT)}`);

  // CRITICAL anti-auto-recovery assertion: with the endpoint restored, the
  // terminal disconnected state must persist until the user clicks Retry.
  let autoRecovered = false;
  for (let i = 0; i < 12; i++) {
    const sa = await state(A);
    out.timeline.push({ phase: 'post-restart', t: i, ...sa });
    if (!sa.retryBtn && !sa.discBanner) { autoRecovered = true; break; }
    await sleep(1000);
  }
  rec('no-auto-recovery', autoRecovered ? 'FAIL' : 'PASS', `retry entry still present 12s after endpoint restored (no silent revival)=${!autoRecovered}`);

  // ACTUAL CLICK on the real product retry button.
  const btn = A.getByRole('button', { name: 'Retry Connection', exact: true }).first();
  const bc = await btn.count().catch(() => 0);
  if (bc) await btn.click({ timeout: 10000 }).catch(() => {});
  rec('retry-click', bc ? 'PASS' : 'FAIL', `clicked real Retry Connection button (count=${bc})`);

  let back = false;
  for (let i = 0; i < 30; i++) {
    const sa = await state(A);
    if (!sa.retryBtn && !sa.discBanner) { back = true; break; }
    await sleep(1000);
  }
  rec('reconnected-after-click', back ? 'PASS' : 'FAIL', 'retry button + disconnected banner cleared after the click');

  // B's signaling socket also dropped. If B exposes the real retry entry, click
  // it too (still a real click, never auto-recovery). Otherwise record INFO.
  const bBtn = B.getByRole('button', { name: 'Retry Connection', exact: true }).first();
  const bbc = await bBtn.count().catch(() => 0);
  if (bbc) {
    await bBtn.click({ timeout: 10000 }).catch(() => {});
    rec('retry-click-B', 'PASS', `clicked B real retry entry (count=${bbc})`);
    await sleep(3000);
  } else {
    rec('retry-click-B', 'INFO', 'B had no retry entry (surviving session/DC)');
  }

  // ---- preservation: same room, identity, playlist ----
  await A.getByRole('button', { name: 'Session Info' }).first().click(); await sleep(800);
  const idA2 = await roomIds(A);
  await A.getByRole('button', { name: 'Playlist' }).first().click(); await sleep(800);
  const aPl2 = await A.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '');
  rec('room-preserved', idA2.room === out.pre.room ? 'PASS' : 'FAIL', `${out.pre.room.slice(0, 8)}… -> ${idA2.room.slice(0, 8)}…`);
  rec('identity-preserved', idA2.dev === out.pre.devA ? 'PASS' : 'FAIL', `${out.pre.devA.slice(0, 12)}… -> ${idA2.dev.slice(0, 12)}…`);
  rec('playlist-preserved', aPl2 === out.pre.playlist ? 'PASS' : 'FAIL', `"${out.pre.playlist}" -> "${aPl2}"`);

  // ---- real dual-end decode + shared control after the manual retry ----
  // Seek to start: the 20s clip may have reached its end during the outage.
  const sr = await A.evaluate(() => { const els = Array.from(document.querySelectorAll('flt-semantics')).filter((e) => (e.getAttribute('aria-label') || '').startsWith('Playback Progress')); const e = els[els.length - 1]; if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  if (sr && sr.w > 0) { await A.mouse.click(sr.x + sr.w * 0.02, sr.y + sr.h / 2); await sleep(1200); }
  await A.getByRole('button', { name: /Play \(Shared\)/i }).first().click().catch(() => {});
  await sleep(1500);
  const a1 = await vstate(A), b1 = await vstate(B);
  await sleep(4000);
  const a2 = await vstate(A), b2 = await vstate(B);
  rec('post-recovery-decode-A', a1 && a2 && a2.ct > a1.ct ? 'PASS' : 'FAIL', `A ct ${a1 && a1.ct}->${a2 && a2.ct} rs=${a2 && a2.rs}`);
  rec('post-recovery-decode-B', b1 && b2 && b2.ct > b1.ct ? 'PASS' : 'FAIL', `B ct ${b1 && b1.ct}->${b2 && b2.ct} rs=${b2 && b2.rs}`);
  // Shared control: A pauses; both ends must actually pause.
  await A.getByRole('button', { name: /Pause \(Shared\)/i }).first().click().catch(() => {});
  await sleep(2000);
  const ap = await vstate(A), bp = await vstate(B);
  rec('post-recovery-control', ap && bp && ap.paused && bp.paused ? 'PASS' : 'FAIL', `A paused=${ap && ap.paused} B paused=${bp && bp.paused}`);

  await A.screenshot({ path: '/tmp/eir-web-test/retry3-recovered-A.png' }).catch(() => {});
  await B.screenshot({ path: '/tmp/eir-web-test/retry3-recovered-B.png' }).catch(() => {});

  const pass = out.steps.filter((s) => s.status === 'PASS').length;
  const fail = out.steps.filter((s) => s.status === 'FAIL').length;
  out.summary = { pass, fail, total: out.steps.length, result: fail === 0 ? 'PASS' : 'FAIL' };
  fs.writeFileSync('/tmp/eir-web-test/retry-result.json', JSON.stringify(out, null, 2));
  await browser.close();
  console.log('\n=== retry-result.json written:', JSON.stringify(out.summary));
  if (fail > 0) process.exitCode = 2;
})().catch((e) => { console.error('FATAL', e); fs.writeFileSync('/tmp/eir-web-test/retry-result.json', JSON.stringify(out, null, 2)); process.exit(1); });

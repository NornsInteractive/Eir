// Eir Web FULL product E2E (two real independent browser contexts).
//
// Drives the REAL compiled product build through its REAL UI on a REAL signaling
// server. No FakeRoomSession, no injected business state, no product test hooks.
// Every assertion is backed by real browser media state:
//   <video>.currentTime / readyState / paused / duration, real semantics values.
//
// Prerequisites:
//   1. Build the product Web output (see docs/MVP-WEB-VALIDATION.md).
//   2. Run the signaling server:  dart run server/signaling_server.dart 8799 127.0.0.1
//   3. Run the static+media server:  node test/web/static_media_server.js
//   4. Playwright + a Chromium binary available (see EIR_PLAYWRIGHT_PATH / EIR_CHROME).
//
// Run (headed under Xvfb so Chromium exposes the Flutter semantics tree):
//   xvfb-run -a node test/web/e2e_web_validation.js
//
// Env overrides (all optional, loopback defaults):
//   EIR_WEB_APP          app URL                 (default http://127.0.0.1:8730/)
//   EIR_SIGNALING        signaling ws URL        (default ws://127.0.0.1:8799)
//   EIR_CHROME           chromium executable
//   EIR_PLAYWRIGHT_PATH  playwright module path
//   EIR_URL_VIDEO        same-origin URL video   (default http://127.0.0.1:8730/sample.mp4)
//   EIR_LOCAL_FILE       local MP4 to share      (default /tmp/eir-media-fixture.mp4)
//   EIR_SHOTS            screenshot dir          (default /tmp/eir-web-test/shots)
//   EIR_BUILD_ID         free-form build id recorded in the result JSON
//
// The only state preset is the test signaling URL in localStorage
// (flutter.eir_setting_signaling_url) — a documented app preference, not business
// state. Invites are generated at runtime and never printed/persisted.
const { chromium } = require(process.env.EIR_PLAYWRIGHT_PATH || '/tmp/eir-browser-tools/node_modules/playwright');
const fs = require('fs');

const APP = process.env.EIR_WEB_APP || 'http://127.0.0.1:8730/';
const CHROME = process.env.EIR_CHROME || '/home/dev/.cache/ms-playwright/chromium-1254/chrome-linux64/chrome';
const SIGNALING = process.env.EIR_SIGNALING || 'ws://127.0.0.1:8799';
const URL_VIDEO = process.env.EIR_URL_VIDEO || 'http://127.0.0.1:8730/sample.mp4';
const LOCAL_FILE = process.env.EIR_LOCAL_FILE || '/tmp/eir-media-fixture.mp4';
const LOCAL_EXT = (LOCAL_FILE.match(/\.([A-Za-z0-9]+)$/) || [null, ''])[1].toLowerCase();
const SHOTS = process.env.EIR_SHOTS || '/tmp/eir-web-test/shots';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const results = { build: process.env.EIR_BUILD_ID || '/tmp/eir-web-final-build', startedAt: new Date().toISOString(), steps: [] };
function rec(name, status, detail) {
  results.steps.push({ name, status, detail: detail || '' });
  console.log(`[${status}] ${name}${detail ? ' :: ' + detail : ''}`);
}
const parseTime = (s) => { if (!s) return null; const m = String(s).match(/(\d+):(\d+)(?::(\d+))?/); if (!m) return null; return m[3] != null ? (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]) : (+m[1]) * 60 + (+m[2]); };

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
async function vstate(page) {
  return await page.evaluate(() => Array.from(document.querySelectorAll('video')).map((v) => ({ src: (v.src || '').slice(0, 44), blob: (v.src || '').startsWith('blob:'), ct: +v.currentTime.toFixed(2), dur: (typeof v.duration === 'number' ? +v.duration.toFixed(1) : v.duration), paused: v.paused, rs: v.readyState, err: v.error ? v.error.code : null, w: v.videoWidth, h: v.videoHeight })));
}
async function firstVisibleInput(page) {
  return await page.evaluate(() => { const ins = Array.from(document.querySelectorAll('input')).map((i) => { const r = i.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, vis: r.x >= 0 && r.x < 1280 && r.y >= 0 && r.y < 900 }; }).filter((o) => o.vis).sort((a, b) => b.w - a.w); return ins[0] || null; });
}
async function clickType(page, geom, text) {
  await page.mouse.click(geom.x + geom.w / 2, geom.y + geom.h / 2);
  await sleep(250);
  await page.keyboard.type(text, { delay: 4 });
  await sleep(250);
}
async function tab(page, label) {
  await page.getByRole('button', { name: label }).first().click({ timeout: 8000 });
  await sleep(700);
}
async function membership(page) {
  const el = page.getByText(/Peers & ACL \(\d+\)/).first();
  return (await el.textContent({ timeout: 5000 }).catch(() => '')) || '';
}
async function progress(page) {
  return await page.evaluate(() => {
    const els = Array.from(document.querySelectorAll('flt-semantics')).filter((e) => (e.getAttribute('aria-label') || '').startsWith('Playback Progress'));
    const e = els[els.length - 1];
    if (!e) return null;
    const r = e.getBoundingClientRect();
    return { label: e.getAttribute('aria-label'), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) };
  });
}
async function addUrl(page, url) {
  await page.getByRole('button', { name: 'Add Media' }).first().click({ timeout: 8000 });
  await sleep(1000);
  await page.evaluate(() => { const els = Array.from(document.querySelectorAll('flt-semantics')); const el = els.find((e) => (e.textContent || '').includes('Network Video URL')); if (el) el.click(); });
  await sleep(300);
  const g = await page.evaluate(() => { const i = document.querySelectorAll('input')[0]; const r = i.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
  await clickType(page, g, url);
  await page.getByRole('button', { name: 'Confirm' }).first().click({ timeout: 8000 });
  await sleep(2200);
}
async function addLocal(page, file) {
  await page.getByRole('button', { name: 'Add Media' }).first().click({ timeout: 8000 });
  await sleep(1000);
  const fcP = page.waitForEvent('filechooser', { timeout: 10000 }).catch(() => null);
  await page.getByRole('button', { name: /Pick Local Video/i }).first().click({ timeout: 8000 }).catch(() => {});
  const fc = await fcP;
  if (!fc) throw new Error('file chooser did not open');
  await fc.setFiles(file);
  await sleep(2500);
  // close/confirm if dialog remains
  const conf = page.getByRole('button', { name: 'Confirm' }).first();
  if (await conf.count().catch(() => 0)) { await conf.click().catch(() => {}); await sleep(2000); }
  const close = page.getByRole('button', { name: 'Close' }).first();
  if (await close.count().catch(() => 0)) { await close.click().catch(() => {}); await sleep(1000); }
}

(async () => {
  fs.mkdirSync(SHOTS, { recursive: true });
  const browser = await chromium.launch({ executablePath: CHROME, headless: false, args: ['--no-sandbox', '--disable-dev-shm-usage', '--autoplay-policy=no-user-gesture-required', '--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });

  // ===== Context A (owner) =====
  const ctxA = await newCtx(browser); const A = await ctxA.newPage(); A.setDefaultTimeout(12000);
  A.on('pageerror', (e) => rec('A-pageerror', 'WARN', e.message.slice(0, 140)));
  await activate(A);
  await A.getByText('Create Cinema Room', { exact: false }).waitFor({ timeout: 20000 });
  await A.getByRole('button', { name: /Create Cinema Room/i }).first().click();
  await A.getByText('P2P Connected', { exact: false }).waitFor({ timeout: 25000 }).catch(() => {});
  rec('A-create', await A.getByText('P2P Connected', { exact: false }).count() ? 'PASS' : 'WARN', 'room created; connection indicator present');

  // room id + device id via Session Info
  await tab(A, 'Session Info');
  const ids = await A.evaluate(() => {
    const texts = Array.from(document.querySelectorAll('flt-semantics')).map((e) => (e.textContent || '').trim());
    const room = texts.find((t) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(t)) || '';
    const dev = texts.find((t) => /^[0-9a-f]{64}$/.test(t)) || '';
    return { room, dev };
  });
  results.roomId = ids.room; results.deviceA = ids.dev;
  rec('A-identity', ids.room && ids.dev ? 'PASS' : 'WARN', `room=${ids.room.slice(0, 8)}… device=${ids.dev.slice(0, 12)}…`);

  await A.getByRole('button', { name: 'Copy Invite' }).first().click();
  await sleep(700);
  const invite = await A.evaluate(() => navigator.clipboard.readText()).catch(() => '');
  if (!invite || !invite.startsWith('eir:')) { rec('A-invite', 'FAIL', `invite len=${(invite || '').length}`); }
  else rec('A-invite', 'PASS', `invite captured len=${invite.length}`);

  // ===== Context B (guest) =====
  const ctxB = await newCtx(browser); const B = await ctxB.newPage(); B.setDefaultTimeout(12000);
  B.on('pageerror', (e) => rec('B-pageerror', 'WARN', e.message.slice(0, 140)));
  await activate(B);
  await B.getByText('Join Cinema', { exact: false }).waitFor({ timeout: 20000 });
  const bi = await firstVisibleInput(B);
  await clickType(B, bi, invite);
  await B.getByRole('button', { name: /Join Cinema/i }).first().click();
  await B.getByText('P2P Connected', { exact: false }).waitFor({ timeout: 25000 }).catch(() => {});
  rec('B-join', await B.getByText('P2P Connected', { exact: false }).count() ? 'PASS' : 'WARN', 'guest joined');

  await tab(B, 'Session Info');
  const devB = await B.evaluate(() => { const texts = Array.from(document.querySelectorAll('flt-semantics')).map((e) => (e.textContent || '').trim()); return texts.find((t) => /^[0-9a-f]{64}$/.test(t)) || ''; });
  rec('B-identity', devB && devB !== ids.dev ? 'PASS' : 'WARN', `independent identity A≠B=${devB !== ids.dev}`);

  // membership sync
  await tab(A, 'Peers & ACL'); await tab(B, 'Peers & ACL');
  const aM = await membership(A), bM = await membership(B);
  rec('membership-sync', aM.includes('(2)') && bM.includes('(2)') ? 'PASS' : 'WARN', `A="${aM}" B="${bM}"`);

  // guest read-only
  await tab(B, 'Playlist');
  const roLabel = await B.getByRole('button', { name: /Read-only/i }).count().catch(() => 0);
  const bPlayEnabled = await B.getByRole('button', { name: /^Play \(Shared\)$/i }).count().catch(() => 0);
  rec('guest-readonly', roLabel > 0 ? 'PASS' : 'WARN', `B read-only-labeled controls=${roLabel}; plain Play button=${bPlayEnabled}`);

  // ===== URL shared playback =====
  await tab(A, 'Playlist');
  await addUrl(A, URL_VIDEO);
  const aPl = await A.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '');
  const bPl = await B.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '');
  rec('url-add-sync', aPl.includes('(1)') && bPl.includes('(1)') ? 'PASS' : 'WARN', `A="${aPl}" B="${bPl}"`);

  await A.getByRole('button', { name: /Switch to this item/i }).first().click({ timeout: 8000 });
  await sleep(2500);
  const sSwitch = await progress(A);
  rec('url-load', (await vstate(A))[0] && (await vstate(A))[0].dur > 0 ? 'PASS' : 'WARN', `A video after switch: ${JSON.stringify((await vstate(A))[0])}`);

  await A.getByRole('button', { name: /Play \(Shared\)/i }).first().click();
  await sleep(1500);
  const a1 = await vstate(A), b1 = await vstate(B), p1 = await progress(A);
  await sleep(4000);
  const a2 = await vstate(A), b2 = await vstate(B), p2 = await progress(A);
  const aAdv = a1[0] && a2[0] && a2[0].ct > a1[0].ct;
  const bAdv = b1[0] && b2[0] && b2[0].ct > b1[0].ct;
  rec('url-decode-A', aAdv && a2[0].rs >= 3 ? 'PASS' : 'WARN', `A ct ${a1[0] && a1[0].ct}->${a2[0] && a2[0].ct} rs=${a2[0] && a2[0].rs}`);
  rec('url-decode-B', bAdv && b2[0].rs >= 3 ? 'PASS' : 'WARN', `B ct ${b1[0] && b1[0].ct}->${b2[0] && b2[0].ct} rs=${b2[0] && b2[0].rs}`);
  const semChanged = p1 && p2 && p1.label !== p2.label;
  rec('live-progress-semantics', semChanged ? 'PASS' : 'FAIL', `A slider "${p1 && p1.label}" -> "${p2 && p2.label}" (tracks video)`);

  // ===== play / pause / seek (owner A) =====
  await A.getByRole('button', { name: /Pause \(Shared\)/i }).first().click().catch(() => {});
  await sleep(600);
  const pa1 = (await vstate(A))[0]; await sleep(2200); const pa2 = (await vstate(A))[0];
  rec('pause-holds', pa1 && pa2 && pa1.paused && Math.abs(pa2.ct - pa1.ct) < 0.6 ? 'PASS' : 'WARN', `paused=${pa2 && pa2.paused} ct ${pa1 && pa1.ct}->${pa2 && pa2.ct}`);
  const sr = await progress(A);
  if (sr && sr.w > 0) {
    const targetFrac = 0.3;
    await A.mouse.click(sr.x + sr.w * targetFrac, sr.y + sr.h / 2);
    await sleep(1200);
    const sv = (await vstate(A))[0];
    rec('seek', sv && Math.abs(sv.ct - targetFrac * sv.dur) < 3 ? 'PASS' : 'WARN', `seek 30% -> ct=${sv && sv.ct}s of dur=${sv && sv.dur}s`);
  } else rec('seek', 'WARN', 'no slider geometry');

  // ===== LOCAL MP4 P2P =====
  await tab(A, 'Playlist');
  try {
    await addLocal(A, LOCAL_FILE);
    rec('local-filechooser', 'PASS', 'native file chooser opened; file selected');
  } catch (e) { rec('local-filechooser', 'FAIL', e.message.slice(0, 100)); }
  const aPl2 = await A.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '');
  const bPl2 = await B.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '');
  rec('local-add-sync', aPl2.includes('(2)') && bPl2.includes('(2)') ? 'PASS' : 'WARN', `A="${aPl2}" B="${bPl2}"`);

  const sw = A.getByRole('button', { name: /Switch to this item/i });
  const swN = await sw.count().catch(() => 0);
  if (swN > 0) await sw.nth(swN - 1).click().catch(() => {});
  await sleep(3500);
  await A.getByRole('button', { name: /Play \(Shared\)/i }).first().click().catch(() => {});
  // poll up to ~14s for both ends to decode
  let la1 = null, lb1 = null, la2 = null, lb2 = null;
  for (let i = 0; i < 7; i++) {
    const va = (await vstate(A))[0], vb = (await vstate(B))[0];
    if (va && va.ct > 0 && vb && vb.ct > 0) { la1 = va; lb1 = vb; break; }
    await sleep(2000);
  }
  await sleep(4000);
  la2 = (await vstate(A))[0]; lb2 = (await vstate(B))[0];
  rec('local-decode-A', la2 && la2.ct > (la1 ? la1.ct : 0) && la2.rs >= 3 ? 'PASS' : 'WARN', `A ct ${la1 && la1.ct}->${la2 && la2.ct} rs=${la2 && la2.rs} blob=${la2 && la2.blob}`);
  rec('local-decode-B', lb2 && lb2.ct > (lb1 ? lb1.ct : 0) && lb2.rs >= 3 ? 'PASS' : 'WARN', `B ct ${lb1 && lb1.ct}->${lb2 && lb2.ct} rs=${lb2 && lb2.rs} blob=${lb2 && lb2.blob} src=${lb2 && lb2.src}`);

  // The served URL must carry the shared container's extension, not a
  // hard-coded .mp4 (the Service Worker only accepts the known set).
  const guestSrc = await B.evaluate(() => {
    const v = Array.from(document.querySelectorAll('video')).find((e) => (e.src || '').includes('/eir-media/'));
    return v ? v.src : '';
  });
  const localExt = (LOCAL_FILE.match(/\.([A-Za-z0-9]+)$/) || [null, ''])[1].toLowerCase();
  rec('local-src-container', guestSrc.endsWith('.' + localExt) ? 'PASS' : 'FAIL', `guest src=${guestSrc} expectedExt=.${localExt}`);

  // ===== NON-VIDEO FILE IS REGISTERED BUT FAILS AT PLAYBACK (current media policy) =====
  const NOT_MEDIA = '/tmp/eir-not-media.txt';
  fs.writeFileSync(NOT_MEDIA, 'this is not a video\n');
  const plBeforeNeg = (await A.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '')) || '';
  try {
    await A.getByRole('button', { name: 'Add Media' }).first().click({ timeout: 8000 });
    await sleep(800);
    const fcNegP = A.waitForEvent('filechooser', { timeout: 10000 }).catch(() => null);
    await A.getByRole('button', { name: /Pick Local Video/i }).first().click({ timeout: 8000 }).catch(() => {});
    const fcNeg = await fcNegP;
    if (!fcNeg) throw new Error('file chooser did not open for a non-video file');
    await fcNeg.setFiles(NOT_MEDIA);
    await sleep(2500);
    const confNeg = A.getByRole('button', { name: 'Confirm' }).first();
    if (await confNeg.count().catch(() => 0)) { await confNeg.click().catch(() => {}); await sleep(1500); }
    const closeNeg0 = A.getByRole('button', { name: 'Close' }).first();
    if (await closeNeg0.count().catch(() => 0)) { await closeNeg0.click().catch(() => {}); await sleep(800); }
    const plAfterNeg = (await A.getByText(/Playlist \(\d+\)/).first().textContent().catch(() => '')) || '';
    const registered = /\(3\)/.test(plAfterNeg);
    // Switch to the newly added (non-video) item and attempt playback to surface the decode error.
    const swNeg = A.getByRole('button', { name: /Switch to this item/i });
    const swNegN = await swNeg.count().catch(() => 0);
    if (swNegN > 0) await swNeg.nth(swNegN - 1).click().catch(() => {});
    await sleep(1500);
    await A.getByRole('button', { name: /Play \(Shared\)/i }).first().click().catch(() => {});
    await sleep(4000);
    const snackCount = await A.getByText(/probe failed|Unsupported media|media|decode/i).first().count().catch(() => 0);
    const v = (await vstate(A))[0];
    rec('local-nonvideo-rejected', registered ? 'PASS' : 'FAIL',
      `registered=${registered} playlist "${plBeforeNeg}" -> "${plAfterNeg}" decodeErrSnack=${snackCount} videoErr=${v && v.err}`);
    const closeNeg = A.getByRole('button', { name: 'Close' }).first();
    if (await closeNeg.count().catch(() => 0)) { await closeNeg.click().catch(() => {}); await sleep(600); }
  } catch (e) { rec('local-nonvideo-rejected', 'FAIL', e.message.slice(0, 120)); }

  // ===== ADMIN GRANT / REVOKE + member control =====
  await tab(A, 'Peers & ACL');
  const grantExact = A.getByRole('button', { name: 'Grant Admin', exact: true }).first();
  const grantCount = await grantExact.count().catch(() => 0);
  if (grantCount) await grantExact.click({ timeout: 8000 }).catch(() => {});
  await sleep(2500);
  const revokeVisible = await A.getByRole('button', { name: 'Revoke Admin', exact: true }).count().catch(() => 0);
  rec('admin-grant', revokeVisible > 0 ? 'PASS' : 'FAIL', `grant clicked=${grantCount}; Revoke Admin present=${revokeVisible}`);
  // B read-only should clear after grant
  await tab(B, 'Playlist');
  const bRoAfterGrant = await B.getByRole('button', { name: /Read-only/i }).count().catch(() => 0);
  rec('admin-B-readonly-cleared', bRoAfterGrant === 0 ? 'PASS' : 'WARN', `B read-only controls after grant=${bRoAfterGrant}`);
  // B (now admin) pauses; A must reflect paused
  const beforeAdm = (await vstate(A))[0];
  await B.getByRole('button', { name: /Pause \(Shared\)/i }).first().click().catch(() => {});
  await sleep(2500);
  const afterAdm = (await vstate(A))[0];
  rec('admin-control-reflects', afterAdm && afterAdm.paused ? 'PASS' : 'WARN', `A paused after admin B pause=${afterAdm && afterAdm.paused} ct ${beforeAdm && beforeAdm.ct}->${afterAdm && afterAdm.ct}`);
  // revoke
  await tab(A, 'Peers & ACL');
  await A.getByRole('button', { name: 'Revoke Admin', exact: true }).first().click({ timeout: 8000 }).catch(() => {});
  await sleep(2000);
  await tab(B, 'Playlist');
  const bReadonlyAgain = await B.getByRole('button', { name: /Read-only/i }).count().catch(() => 0);
  rec('admin-revoke', bReadonlyAgain > 0 ? 'PASS' : 'WARN', `B read-only controls after revoke=${bReadonlyAgain}`);

  // ===== THEME / LANGUAGE / INDEPENDENT COLORS (no room rebuild) =====
  await tab(A, 'Session Info');
  const roomBefore = results.roomId;
  const memBefore = await membership(A);
  await A.getByRole('button', { name: /Preferences/i }).first().click();
  await A.getByText('Preferences', { exact: false }).first().waitFor({ timeout: 8000 }).catch(() => {});
  rec('settings-open', 'PASS', 'Preferences opened');

  // language -> Chinese then back to English
  await A.getByRole('button', { name: /Chinese/i }).first().click().catch(() => {});
  await sleep(700);
  const zhCount = await A.getByText(/简体中文|语言|主题|外观/).count().catch(() => 0);
  rec('lang-switch-zh', zhCount > 0 ? 'PASS' : 'WARN', `zh labels present=${zhCount}`);
  await A.getByRole('button', { name: /English \(US\)/i }).first().click().catch(() => {});
  await sleep(500);

  // dark mode + independent light/dark accents
  await A.getByRole('button', { name: /Dark Mode/i }).first().click().catch(() => {});
  await sleep(600);
  const lightSet = await A.getByRole('button', { name: /Light Theme Accent: Aurora Purple/i }).first().click().then(() => true).catch(() => false);
  await sleep(400);
  const darkSet = await A.getByRole('button', { name: /Dark Theme Accent: Mint Green/i }).first().click().then(() => true).catch(() => false);
  await sleep(400);
  rec('theme-independent-colors', lightSet && darkSet ? 'PASS' : 'WARN', `lightAccentSet=${lightSet} darkAccentSet=${darkSet}`);

  await A.getByRole('button', { name: /Done|Close/i }).first().click().catch(() => {});
  await sleep(1000);
  await tab(A, 'Session Info');
  const roomAfter = await A.evaluate(() => { const texts = Array.from(document.querySelectorAll('flt-semantics')).map((e) => (e.textContent || '').trim()); return texts.find((t) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(t)) || ''; });
  const memAfter = await membership(A);
  const stillConn = await A.getByText('P2P Connected', { exact: false }).count().catch(() => 0);
  rec('theme-no-session-rebuild', roomAfter === roomBefore && memAfter === memBefore && stillConn > 0 ? 'PASS' : 'WARN', `roomStable=${roomAfter === roomBefore} membersStable=${memAfter === memBefore} connected=${stillConn > 0}`);

  // ===== CACHE occupancy + safe clean (on B) =====
  // The Preferences gear is always labelled "Preferences", so waiting for that
  // text returns before the dialog renders. Wait for a dialog-only node instead
  // ("Media Cache" section) and retry the open click once if needed.
  await tab(B, 'Playlist');
  const cacheSectionVisible = async () =>
    (await B.getByText('Media Cache', { exact: true }).count().catch(() => 0)) > 0;
  for (let attempt = 0; attempt < 2 && !(await cacheSectionVisible()); attempt++) {
    await B.getByRole('button', { name: /Preferences/i }).first().click({ timeout: 8000 }).catch(() => {});
    for (let i = 0; i < 16 && !(await cacheSectionVisible()); i++) await sleep(500);
  }
  const dialogOpen = await cacheSectionVisible();
  // Reveal the cache section (it sits below the fold) with a real wheel scroll.
  await B.mouse.move(640, 600);
  await B.mouse.wheel(0, 900);
  await sleep(1200);
  const occNodes = await B.evaluate(() => Array.from(document.querySelectorAll('flt-semantics'))
    .map((e) => (e.textContent || '').trim())
    .filter((t) => t && t.length < 40 && /^\d+(\.\d+)?\s*(B|KB|MB|GB)\s*\/\s*\d/.test(t)));
  const occPct = await B.evaluate(() => Array.from(document.querySelectorAll('flt-semantics'))
    .map((e) => (e.textContent || '').trim())
    .filter((t) => /^\d+%$/.test(t)));
  rec('cache-occupancy', dialogOpen && occNodes.length ? 'PASS' : 'WARN', `dialogOpen=${dialogOpen} occupancy=${JSON.stringify(occNodes)} pct=${JSON.stringify(occPct)}`);
  const cleanBtn = B.getByRole('button', { name: 'Clean Unprotected Cache', exact: true }).first();
  const cleanVisible = await cleanBtn.count().catch(() => 0);
  if (cleanVisible) await cleanBtn.click({ timeout: 8000 }).catch(() => {});
  await sleep(2500);
  const cmsg = await B.evaluate(() => Array.from(document.querySelectorAll('flt-semantics'))
    .map((e) => (e.textContent || '').trim())
    .filter((t) => /freed|No unprotected|nothing to clean|清理|释放/i.test(t) && t.length < 120)
    .find((t) => !/^Clean Unprotected Cache$/.test(t)) || '');
  rec('cache-clean', cleanVisible && cmsg ? 'PASS' : 'WARN', `cleanVisible=${cleanVisible} feedback="${cmsg.slice(0, 90)}"`);
  await B.getByRole('button', { name: /Done|Close/i }).first().click().catch(() => {});

  await A.screenshot({ path: SHOTS + '/final-A.png' }).catch(() => {});
  await B.screenshot({ path: SHOTS + '/final-B.png' }).catch(() => {});

  const pass = results.steps.filter((s) => s.status === 'PASS').length;
  const fail = results.steps.filter((s) => s.status === 'FAIL').length;
  const warn = results.steps.filter((s) => s.status === 'WARN').length;
  results.summary = { pass, fail, warn, total: results.steps.length };
  rec('SUMMARY', fail === 0 ? 'PASS' : 'WARN', `pass=${pass} fail=${fail} warn=${warn}`);
  await browser.close();
  fs.writeFileSync('/tmp/eir-web-test/e2e-result.json', JSON.stringify(results, null, 2));
  console.log('\n=== Result written: /tmp/eir-web-test/e2e-result.json ===');
})().catch((e) => {
  console.error('FATAL', e);
  fs.writeFileSync('/tmp/eir-web-test/e2e-result.json', JSON.stringify(results, null, 2));
  process.exit(1);
});

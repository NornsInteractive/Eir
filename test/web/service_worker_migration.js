// Run against an isolated Eir Web build using EIR_WEB_URL.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.EIR_PLAYWRIGHT_PATH || 'playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.goto(process.env.EIR_WEB_URL || 'http://127.0.0.1:8951/');
    await page.evaluate(async () => {
      await navigator.serviceWorker.register('flutter_service_worker.js?v=migration-test');
      await navigator.serviceWorker.ready;
    });
    await page.reload();
    const before = await page.evaluate(() => navigator.serviceWorker.controller?.scriptURL);
    assert.match(before, /flutter_service_worker\.js/);
    await page.addScriptTag({ url: '/eir_media_bridge.js' });
    await page.waitForFunction(() => window.eirMediaState === 'controlled', null, { timeout: 12000 });
    const after = await page.evaluate(() => navigator.serviceWorker.controller?.scriptURL);
    assert.match(after, /\/eir_media_sw\.js$/);
    console.log('Legacy worker replaced by the Eir media worker.');
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

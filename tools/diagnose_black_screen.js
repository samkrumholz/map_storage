const puppeteer = require('puppeteer');

(async () => {
  const url = process.argv[2] || 'https://samkrumholz.github.io/map_storage/vacancy.html';
  const browser = await puppeteer.launch({ headless: 'new' });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 900 });

  const consoleMsgs = [];
  const failedRequests = [];
  const pageErrors = [];

  page.on('console', msg => consoleMsgs.push(`[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', err => pageErrors.push(String(err)));
  page.on('requestfailed', req => failedRequests.push(`${req.url()} -- ${req.failure()?.errorText}`));
  page.on('response', res => {
    if (res.status() >= 400) failedRequests.push(`${res.url()} -- HTTP ${res.status()}`);
  });

  console.log('Navigating to', url);
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 }).catch(e => console.log('goto error:', e.message));

  await new Promise(r => setTimeout(r, 4000));

  console.log('\n=== CONSOLE MESSAGES ===');
  consoleMsgs.forEach(m => console.log(m));

  console.log('\n=== PAGE ERRORS (uncaught exceptions) ===');
  pageErrors.forEach(m => console.log(m));

  console.log('\n=== FAILED / ERROR HTTP REQUESTS ===');
  failedRequests.forEach(m => console.log(m));

  const canvasInfo = await page.evaluate(() => {
    const c = document.querySelector('#map canvas');
    if (!c) return { found: false };
    const ctx = c.getContext('webgl2') || c.getContext('webgl');
    return {
      found: true,
      width: c.width, height: c.height,
      cssWidth: c.clientWidth, cssHeight: c.clientHeight,
      hasWebGL: !!ctx
    };
  });
  console.log('\n=== CANVAS INFO ===');
  console.log(JSON.stringify(canvasInfo, null, 2));

  await page.screenshot({ path: 'tools/screenshot_debug.png' });
  console.log('\nSaved screenshot to tools/screenshot_debug.png');

  await browser.close();
})();

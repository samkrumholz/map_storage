const { chromium } = require('playwright');
(async () => {
  const url = process.argv[2] || 'http://localhost:8935/index.html';
  const browser = await chromium.launch({
    executablePath: 'C:\\Users\\krumh\\.cache\\puppeteer\\chrome\\win64-150.0.7871.24\\chrome-win64\\chrome.exe'
  });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', err => errors.push('pageerror: ' + err.message));
  page.on('requestfailed', req => errors.push('requestfailed: ' + req.url() + ' ' + req.failure()?.errorText));
  page.on('response', res => {
    try {
      if (res.status() >= 400) {
        const msg = 'HTTP ' + res.status() + ' ' + res.url();
        errors.push(msg);
        console.log('[response>=400]', msg);
      }
    } catch (e) { console.log('[response listener error]', e.message); }
  });

  await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(3000);
  await page.screenshot({ path: 'tools/screenshot_before_toggle.png' });

  await page.click('#btn-percentile');
  await page.waitForTimeout(3000);
  await page.screenshot({ path: 'tools/screenshot_after_toggle.png' });

  const legendTitle = await page.$eval('#legend-title', el => el.textContent);
  console.log('legend title after toggle:', legendTitle);

  const metroLineVisible = await page.evaluate(() => {
    try {
      return map.getLayoutProperty('metro-line', 'visibility');
    } catch (e) {
      return 'ERROR: ' + e.message;
    }
  });
  console.log('metro-line visibility:', metroLineVisible);

  const fillPaint = await page.evaluate(() => {
    try {
      return JSON.stringify(map.getPaintProperty('fill-2020', 'fill-color')).slice(0, 300);
    } catch (e) {
      return 'ERROR: ' + e.message;
    }
  });
  console.log('fill-2020 paint (truncated):', fillPaint);

  const currentYearVal = await page.evaluate(() => {
    try { return currentYear; } catch (e) { return 'ERROR: ' + e.message; }
  });
  console.log('currentYear:', currentYearVal);

  await page.evaluate(() => map.jumpTo({ center: [-87.6298, 41.8781], zoom: 10 }));
  await page.waitForTimeout(2000);
  await page.mouse.move(640, 450);
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'tools/screenshot_chicago_percentile.png' });
  const tooltipHtml = await page.evaluate(() => {
    const el = document.getElementById('tooltip');
    return el ? el.innerHTML : 'NO #tooltip ELEMENT';
  });
  console.log('tooltip html:', tooltipHtml);

  console.log('--- console/page errors ---');
  errors.forEach(e => console.log(e));
  console.log('--- done, errors count:', errors.length);

  await browser.close();
})();

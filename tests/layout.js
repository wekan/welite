const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ javaScriptEnabled: false, userAgent: 'Welite-test' });
    await context.route('**/*', async route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      await route.continue({ headers });
    });
    const page = await context.newPage(), base = process.argv[2], session = process.argv[3];
    await page.goto(`${base}/layout?sessionId=${session}`);
    assert.equal(await page.evaluate(()=>document.doctype.publicId),'-//W3C//DTD HTML 4.01 Transitional//EN');
    assert.equal(await page.evaluate(()=>document.compatMode),'CSS1Compat');
    const span = page.locator('td[data-grid-row="0"][data-grid-col="0"]');
    assert.equal(await span.getAttribute('rowspan'), '2');
    assert.equal(await span.getAttribute('colspan'), '2');
    assert.equal(await page.locator('[name=requiredText]').getAttribute('required'), 'required');
    assert(await page.evaluate(() => {
      const a = document.querySelector('td[data-grid-col="0"]'), b = document.querySelector('td[data-grid-col="2"]');
      return a.getBoundingClientRect().left > b.getBoundingClientRect().left;
    }));
    await page.goto(base+process.argv[4]);
    const first = page.locator('td').filter({hasText:'[label] span first'}).filter({has:page.locator('input[value="Sort down"]')}).last();
    await first.locator('input[value="Sort down"]').first().click();
    await page.goto(`${base}/layout?sessionId=${session}`);
    assert((await span.textContent()).indexOf('span second') < (await span.textContent()).indexOf('span first'));
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium spanning cells, required metadata, physical RTL and no-JS cell sorting');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });

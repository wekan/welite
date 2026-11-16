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
    const page = await context.newPage();
    await page.goto(`${process.argv[2]}/board?id=protected&sessionId=${process.argv[3]}`);
    assert.equal(await page.locator('td[data-list=todo]').getByText('Card <test>').count(), 1);
    await page.locator('input[name=sel_card][value=card]').check();
    await page.locator('input[type=submit][name=dir][value=right]').click();
    assert.equal(await page.locator('td[data-list=doing]').getByText('Card <test>').count(), 1);
    assert.equal(await page.locator('td[data-list=todo]').getByText('Card <test>').count(), 0);
    assert.equal((await context.cookies()).length, 0);
    console.log('PASS: Chromium select and move card with JavaScript and cookies disabled');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });

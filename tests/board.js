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
    await page.locator('input[type=submit][name=move_right]').click();
    await page.getByRole('link', { name: 'View right', exact: true }).click();
    assert.equal(await page.getByText('X 2 Y 1', { exact: false }).count(), 1);
    assert.equal(await page.locator('td[data-list=doing]').getByText('Card <test>').count(), 1);
    assert.equal(await page.locator('td[data-list=todo]').getByText('Card <test>').count(), 0);
    const minimap = page.locator('table[summary="Board minimap"]');
    assert.equal(await minimap.locator('td[bgcolor="#ffff66"]').count(), 1);
    assert.equal(await minimap.locator('td').nth(0).textContent(), '-');
    assert.equal(await minimap.locator('td').nth(1).textContent(), '*');
    await minimap.locator('a').first().click();
    assert.equal(await page.locator('td[data-list=todo]').count(), 1);
    assert.equal(await page.locator('td[data-list=doing]').count(), 0);
    for (const width of [320, 768, 1920]) {
      await page.setViewportSize({ width, height: 800 });
      assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth));
    }
    await page.locator('a[href*="view=all"]').click();
    assert.equal(await page.locator('td[data-list=todo]').count(), 1);
    assert.equal(await page.locator('td[data-list=doing]').count(), 1);
    assert.equal((await context.cookies()).length, 0);
    console.log('PASS: Chromium card movement, minimap and viewport navigation with JavaScript and cookies disabled');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });

// Run through tests/admin.py with WELITE_UI=1. Playwright is a host test tool.
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
    const base = process.argv[2], session = process.argv[3];
    await page.goto(`${base}/designer?sessionId=${session}`);
    await page.locator('input[name=url]').fill('/browser');
    await page.locator('input[name=title]').fill('Browser page');
    await page.locator('input[name=cols]').fill('2');
    await page.locator('input[type=submit][value=save]').click();
    let row = page.locator('tr').filter({ hasText: 'Browser page' });
    await row.locator('a').filter({ hasText: 'Edit' }).click();
    await page.locator('input[name=title]').fill('Browser changed');
    await page.locator('input[type=submit][value=save]').click();
    row = page.locator('tr').filter({ hasText: 'Browser changed' });
    await row.locator('a').filter({ hasText: 'Edit' }).click();
    await page.locator('input[name=label]').fill('Browser widget');
    await page.locator('input[type=submit][value="Add widget"]').click();
    assert.equal(await page.getByText('[label] Browser widget', { exact: false }).count(), 1);
    await page.getByRole('link', { name: 'Edit widget' }).click();
    await page.locator('input[name=label]').fill('Browser widget changed');
    await page.locator('input[type=submit][value="Save widget"]').click();
    await page.locator('input[type=submit][value=">"]').click();
    await page.locator('input[type=submit][value=Del]').click();
    assert.equal(await page.getByRole('link', { name: 'Edit widget' }).count(), 0);
    await page.goto(`${base}/designer?sessionId=${session}`);
    row = page.locator('tr').filter({ hasText: 'Browser changed' });
    await row.locator('input[type=submit][value=disable]').click();
    row = page.locator('tr').filter({ hasText: 'Browser changed' });
    assert.equal(await row.locator('td').nth(2).textContent(), '0');
    await row.locator('input[type=submit][value=enable]').click();
    row = page.locator('tr').filter({ hasText: 'Browser changed' });
    assert.equal(await row.locator('td').nth(2).textContent(), '1');
    await row.locator('input[type=submit][value=Delete]').click();
    assert.equal(await page.locator('tr').filter({ hasText: 'Browser changed' }).count(), 0);
    assert.equal((await context.cookies()).length, 0);
    console.log('PASS: Chromium page/widget forms with JavaScript and cookies disabled');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });

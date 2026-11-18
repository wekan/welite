const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');

(async () => {
  const [url] = process.argv.slice(2);
  const token = readFileSync(0, 'utf8').trim();
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ javaScriptEnabled: false, userAgent: 'shared-http-test' });
    await context.route('**/*', route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      return route.continue({ headers });
    });
    const page = await context.newPage();
    assert.equal((await page.goto(url)).status(), 200);
    const field = page.locator('.minicard-custom-field').filter({ hasText: 'Browser choice:' });
    assert.equal(await field.textContent(), 'Browser choice: Original choice');
    const endpoint = new URL('/api/boards/b/custom-fields/browser-mini-field/dropdown-items/browser-mini-option', url);
    const response = await context.request.put(endpoint.href, {
      headers: { Authorization: 'Bearer ' + token },
      data: { name: 'Updated <choice>' },
    });
    assert.equal(response.status(), 200);
    assert.equal((await page.reload()).status(), 200);
    assert.equal(await field.textContent(), 'Browser choice: Updated <choice>');
    assert.deepEqual(await context.cookies(), []);
    console.log('PASS: native Chromium minicard displays the renamed Mongo-backed dropdown option');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

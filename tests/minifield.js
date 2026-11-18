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
    const definition = new URL('/api/boards/b/custom-fields/browser-mini-field', url);
    const auth = { Authorization: 'Bearer ' + token };
    const renamed = await context.request.put(definition.href, {
      headers: auth, data: { name: 'Renamed <field>' },
    });
    assert.equal(renamed.status(), 200);
    const rejected = await context.request.put(definition.href, {
      headers: auth, data: { name: 'Rejected field', settings: 'invalid' },
    });
    assert.equal(rejected.status(), 500);
    assert.equal((await page.reload()).status(), 200);
    const current = page.locator('.minicard-custom-field').filter({ hasText: 'Renamed <field>:' });
    assert.equal(await current.textContent(), 'Renamed <field>: Updated <choice>');
    assert.equal(await field.count(), 0);
    assert.equal(await page.getByText('Rejected field', { exact: false }).count(), 0);
    const removed = await context.request.delete(definition.href, { headers: auth });
    assert.equal(removed.status(), 200);
    assert.equal((await page.reload()).status(), 200);
    assert.equal(await current.count(), 0);
    assert.equal(await page.getByText('Updated <choice>', { exact: false }).count(), 0);
    assert.deepEqual(await context.cookies(), []);
    console.log('PASS: native Chromium minicard reflects Mongo-backed custom-field rename and deletion');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

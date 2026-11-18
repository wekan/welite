// Optional shared HTTP browser regression, enabled by WELITE_UI=1.
const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ javaScriptEnabled: false, userAgent: 'shared-http-test' });
    await context.route('**/*', route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      return route.continue({ headers });
    });
    const page = await context.newPage();
    await page.goto(process.argv[2]);
    const form = operation => page.locator('form').filter({
      has: page.locator(`input[name="operation"][value="${operation}"]`),
    });
    const submit = async operation => {
      const [response] = await Promise.all([
        page.waitForResponse(item => item.request().method() === 'POST'),
        form(operation).locator('input[type=submit]').click(),
      ]);
      assert.equal(response.status(), 303);
      assert.equal(await response.headerValue('set-cookie'), null);
      await page.waitForLoadState('domcontentloaded');
    };
    await form('create').locator('input[name=url]').fill('https://1.1.1.1/chromium');
    await submit('create');
    await form('save').locator('input[name=title]').fill('Chromium webhook');
    await form('save').locator('input[name=enabled]').uncheck();
    await submit('save');
    assert.equal(await form('save').locator('input[name=title]').inputValue(), 'Chromium webhook');
    assert.equal(await form('save').locator('input[name=enabled]').isChecked(), false);
    await submit('delete');
    assert.equal(await form('save').count(), 0);
    console.log('PASS: Chromium webhook management with JavaScript and cookies disabled');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});

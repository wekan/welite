const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');

(async () => {
  const [url, size] = process.argv.slice(2);
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
    const form = page.locator('form[action^="/board/attachment/upload?"]');
    const bytes = size ? Buffer.alloc(Number(size)) : Buffer.from([0, 10, 255, 21]);
    if (size) for (let index = 0; index < bytes.length; index++) bytes[index] = index % 256;
    const name = 'Native upload å.bin';
    await form.locator('input[type=file]').setInputFiles({
      name, mimeType: 'application/octet-stream', buffer: bytes,
    });
    const [posted] = await Promise.all([
      page.waitForResponse(response => response.request().method() === 'POST'),
      form.locator('input[type=submit]').click(),
    ]);
    assert.equal(posted.status(), 303);
    assert.equal(new URL(page.url()).searchParams.get('card'), new URL(url).searchParams.get('card'));
    const link = page.getByRole('link', { name, exact: true });
    const [download] = await Promise.all([page.waitForEvent('download'), link.click()]);
    assert.deepEqual(readFileSync(await download.path()), bytes);
    assert.deepEqual(await context.cookies(), []);
    console.log('PASS: Chromium uploads and downloads the native multipart attachment without JavaScript or cookies');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

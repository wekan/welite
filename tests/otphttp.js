const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context = await browser.newContext({javaScriptEnabled:false});
    await context.route('**/*', async route => {
      const headers = {...route.request().headers()};
      delete headers.cookie;
      await route.continue({headers});
    });
    const page = await context.newPage();
    await page.goto(process.argv[2]+'/sign-in');
    await page.locator('input[name=username]').fill('factor');
    await page.locator('input[name=password]').fill('test-password');
    await page.locator('input[name=code]').fill(process.argv[3]);
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => url.searchParams.has('sessionId'));
    assert.match(await page.locator('body').innerText(),/Signed in as factor/);
    const url = new URL(page.url());
    assert.deepEqual([...url.searchParams.keys()],['sessionId']);
    assert.equal((await context.cookies()).length,0);
    await page.reload();
    assert.match(await page.locator('body').innerText(),/Signed in as factor/);
    console.log('PASS: OTP sign-in and reload in Chromium with JavaScript disabled and Cookie headers removed');
    await context.close();
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });

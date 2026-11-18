const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');

(async () => {
  const [base, memberSession, adminSession, target] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ javaScriptEnabled: false, userAgent: 'Welite-test' });
    await context.route('**/*', route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      return route.continue({ headers });
    });
    const page = await context.newPage();
    assert.equal((await page.goto(base + '/board?id=ordinary&sessionId=' + memberSession)).status(), 200);
    const card = page.getByText('Retained ownership card', { exact: true });
    assert.ok(await card.isVisible());
    const response = await context.request.put(base + '/api/users/' + target, {
      headers: { Authorization: 'Bearer ' + adminSession },
      data: { action: 'takeOwnership' },
    });
    assert.equal(response.status(), 200);
    assert.deepEqual(await response.json(), [
      { _id: 'owned-early', title: 'Earlier' },
      { _id: 'owned-late', title: 'Later' },
    ]);
    assert.equal((await page.reload()).status(), 200);
    assert.ok(await card.isVisible());
    assert.deepEqual(await context.cookies(), []);
    console.log('PASS: Chromium still shows the ordinary member card after REST ownership transfer');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

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
    const headers = { Authorization: 'Bearer ' + token };
    for (const [kind, label] of [['org', 'Organization'], ['team', 'Team']]) {
      const flag = kind + 'SyncMembersFromAuth';
      const checkbox = page.locator('tr[data-group-id="group"] input[data-feature="' + flag + '"]');
      const endpoint = id => new URL('/api/admin/' + kind + 's/' + id + '/features', url).href;
      assert.equal(await checkbox.isChecked(), false);
      const missing = await context.request.put(endpoint('missing'), { headers, data: { [flag]: true } });
      assert.equal(missing.status(), 404);
      assert.deepEqual(await missing.json(), { error: label + ' not found' });
      assert.equal((await page.reload()).status(), 200);
      assert.equal(await checkbox.isChecked(), false);
      for (const enabled of [true, false]) {
        const response = await context.request.put(endpoint('group'), { headers, data: { [flag]: enabled } });
        assert.equal(response.status(), 200);
        assert.equal((await page.reload()).status(), 200);
        assert.equal(await checkbox.isChecked(), enabled);
      }
    }
    assert.deepEqual(await context.cookies(), []);
    console.log('PASS: native People reflects organization and team REST changes in Chromium');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

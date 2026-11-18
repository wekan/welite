const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

(async () => {
  const boardUrl = new URL(process.argv[2]);
  const token = readFileSync(0, 'utf8').trim();
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({
      javaScriptEnabled: false,
      userAgent: 'shared-http-test',
    });
    await context.route('**/*', route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      return route.continue({ headers });
    });
    const page = await context.newPage();
    const headers = { Authorization: 'Bearer ' + token };
    const endpoint = list => boardUrl.origin + '/api/boards/b/lists/' + list + '/cards/brow-card';
    const checklist = boardUrl.origin + '/api/boards/b/cards/brow-card/checklists';
    const card = page.getByText('Keep my browser checklist', { exact: true });

    const initial = await page.goto(boardUrl.href);
    assert.equal(initial.status(), 200);
    assert.equal(await initial.headerValue('set-cookie'), null);
    assert.equal(await card.count(), 1);

    for (const [operation, archived] of [['archive', true], ['unarchive', false]]) {
      const path = endpoint('l') + '/' + operation;
      assert.equal((await context.request.post(path)).status(), 401);
      const response = await context.request.post(path, { headers });
      assert.equal(response.status(), 200);
      const saved = await response.json();
      assert.equal(saved._id, 'brow-card');
      assert.equal(saved.archived, archived);
      await page.reload();
      assert.equal(await card.count(), archived ? 0 : 1);
      const repeated = await context.request.post(path, { headers });
      assert.equal(repeated.status(), 404);
      assert.deepEqual(await repeated.json(), { error: 'Card not found' });
    }
    console.log('PASS: Chromium reflects REST archive and restore with JavaScript and cookies disabled');

    const wrong = await context.request.delete(endpoint('brow-list'), { headers });
    assert.equal(wrong.status(), 404);
    assert.deepEqual(await wrong.json(), { error: 'Card not found' });
    const preserved = await context.request.get(checklist, { headers });
    assert.equal(preserved.status(), 200);
    assert((await preserved.json()).some(entry => entry._id === 'brow-check'));
    await page.reload();
    assert.equal(await card.count(), 1);

    assert.equal((await context.request.delete(endpoint('l'), { headers })).status(), 200);
    await page.reload();
    assert.equal(await card.count(), 0);
    assert.equal((await context.request.delete(endpoint('l'), { headers })).status(), 404);
    console.log('PASS: Chromium wrong-list REST deletion preserves the card and checklist with JavaScript and cookies disabled');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

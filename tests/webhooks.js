// Optional shared HTTP browser regression, enabled by WELITE_UI=1.
const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

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

    const url = new URL(process.argv[2]);
    const headers = { Authorization: 'Bearer ' + readFileSync(0, 'utf8').trim() };
    const boardId = url.searchParams.get('id');
    const endpoint = (board, id = '') =>
      url.origin + '/api/boards/' + encodeURIComponent(board) + '/integrations' +
      (id ? '/' + encodeURIComponent(id) : '');
    const create = async destination => {
      const response = await context.request.post(endpoint(boardId), {
        headers, data: { url: destination },
      });
      assert.equal(response.status(), 200);
      return (await response.json())._id;
    };
    const otherBoard = await context.request.post(url.origin + '/api/boards', {
      headers, data: { title: 'Webhook scope test', permission: 'private' },
    });
    assert.equal(otherBoard.status(), 200);
    const otherId = (await otherBoard.json())._id;
    const target = await create('https://1.1.1.1/target');
    const sibling = await create('https://1.1.1.1/sibling');
    const editor = id => form('save').filter({
      has: page.locator(`input[name="integrationId"][value="${id}"]`),
    });
    const read = async id => {
      const response = await context.request.get(endpoint(boardId, id), { headers });
      assert.equal(response.status(), 200);
      return response.json();
    };
    try {
      const before = await read(target);
      const siblingBefore = await read(sibling);
      await page.reload();
      assert.equal(await editor(target).count(), 1);
      assert.equal((await context.request.delete(endpoint(otherId, target), { headers })).status(), 404);
      assert.equal((await context.request.put(endpoint(otherId, target), {
        headers, data: { title: 'Wrong board', enabled: true },
      })).status(), 404);
      assert.equal((await context.request.put(endpoint(boardId, target), {
        headers, data: { title: 'Rejected edit', url: 'invalid-url' },
      })).status(), 400);
      assert.deepEqual(await read(target), before);
      await page.reload();
      assert.equal(await editor(target).locator('input[name=title]').inputValue(), before.title || '');

      assert.equal((await context.request.put(endpoint(boardId, target), {
        headers, data: { title: 'REST edit', enabled: false },
      })).status(), 200);
      await page.reload();
      assert.equal(await editor(target).locator('input[name=title]').inputValue(), 'REST edit');
      assert.equal(await editor(target).locator('input[name=enabled]').isChecked(), false);

      assert.equal((await context.request.delete(endpoint(boardId, target), { headers })).status(), 200);
      await page.reload();
      assert.equal(await editor(target).count(), 0);
      assert.equal(await editor(sibling).count(), 1);
      assert.deepEqual(await read(sibling), siblingBefore);
      console.log('PASS: Chromium reload shows accepted REST webhook changes and preserves rejected changes');
    } finally {
      await context.request.delete(endpoint(boardId, target), { headers });
      await context.request.delete(endpoint(boardId, sibling), { headers });
      await context.request.delete(url.origin + '/api/boards/' + encodeURIComponent(otherId), { headers });
    }
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});

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
    const card = new URL(url);
    card.pathname = '/board/card';
    card.searchParams.set('card', 'brow-sort');
    assert.equal((await page.goto(card.href)).status(), 200);
    const form = page.locator('form[action^="/board/card/dropdown?"]');
    const select = form.locator('select');
    assert.equal(await select.inputValue(), 'browser-mini-option');
    assert.equal(await select.locator('option:checked').textContent(), 'Updated <choice>');
    const removeOption = new URL(endpoint.href);
    removeOption.pathname = removeOption.pathname.replace(/[^/]+$/, 'browser-mini-remove');
    const remove = await context.request.delete(removeOption.href, {
      headers: { Authorization: 'Bearer ' + token },
    });
    assert.equal(remove.status(), 200);
    assert.equal((await page.reload()).status(), 200);
    assert.equal(await select.locator('option[value="browser-mini-remove"]').count(), 0);
    assert.equal(await select.inputValue(), 'browser-mini-option');
    const removedSelection = await context.request.delete(endpoint.href, {
      headers: { Authorization: 'Bearer ' + token },
    });
    assert.equal(removedSelection.status(), 200);
    assert.equal((await page.reload()).status(), 200);
    assert.equal(await select.inputValue(), '');
    assert.equal(await select.locator('option[value="browser-mini-option"]').count(), 0);
    const stored = await context.request.get(new URL('/api/boards/b/lists/l/cards/brow-sort', url).href, {
      headers: { Authorization: 'Bearer ' + token },
    });
    assert.equal(stored.status(), 200);
    assert.deepEqual((await stored.json()).customFields, [
      { _id: 'browser-mini-field', value: 'browser-mini-option' },
    ]);
    await select.selectOption('browser-mini-alternate');
    const [saved] = await Promise.all([
      page.waitForResponse(response => response.request().method() === 'POST'),
      form.locator('input[type=submit]').click(),
    ]);
    assert.equal(saved.status(), 303);
    assert.equal(await select.inputValue(), 'browser-mini-alternate');
    assert.equal((await page.goto(url)).status(), 200);
    assert.equal(await field.textContent(), 'Browser choice: Alternate choice');
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
    assert.equal(await current.textContent(), 'Renamed <field>: Alternate choice');
    assert.equal(await field.count(), 0);
    assert.equal(await page.getByText('Rejected field', { exact: false }).count(), 0);
    const removed = await context.request.delete(definition.href, { headers: auth });
    assert.equal(removed.status(), 200);
    assert.equal((await page.reload()).status(), 200);
    assert.equal(await current.count(), 0);
    assert.equal(await page.getByText('Alternate choice', { exact: false }).count(), 0);
    assert.deepEqual(await context.cookies(), []);
    console.log('PASS: native Chromium minicard reflects Mongo-backed custom-field rename and deletion');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

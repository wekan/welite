// Optional shared HTTP browser download regression.
const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');

(async () => {
  const [boardUrl, cardId, attachmentId, expectedFile] = process.argv.slice(2);
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ javaScriptEnabled: false, userAgent: 'shared-http-test' });
    await context.route('**/*', route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      return route.continue({ headers });
    });
    const page = await context.newPage();
    assert.equal((await page.goto(boardUrl)).status(), 200);
    const links = page.locator('a[href^="/board/export?"]');
    assert.equal(await links.count(), 2);
    for (const withoutFiles of [false, true]) {
      const index = (await links.evaluateAll(items => items.map(item => item.href))).findIndex(href =>
        (new URL(href).searchParams.get('attachments') === 'false') === withoutFiles);
      assert.ok(index >= 0);
      const [download] = await Promise.all([page.waitForEvent('download'), links.nth(index).click()]);
      assert.equal(await download.failure(), null);
      assert.equal(download.suggestedFilename(), 'board.json');
      const chunks = [];
      for await (const chunk of await download.createReadStream()) chunks.push(chunk);
      const exported = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      assert.ok(exported.cards.some(card => card._id === cardId));
      assert.ok(Array.isArray(exported.users));
      const attachment = exported.attachments.find(row => row._id === attachmentId);
      assert.ok(attachment);
      if (withoutFiles) assert.equal(Object.hasOwn(attachment, 'file'), false);
      else assert.equal(attachment.file, expectedFile);
    }
    console.log('PASS: Chromium downloads both board export modes with JavaScript and cookies disabled');
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});

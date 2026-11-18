const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
const { mkdtemp, mkdir, writeFile, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { createServer } = require('node:http');
const { once } = require('node:events');

async function verifyCookieBlocking(page, context) {
  const server = createServer((request, response) => {
    response.setHeader('Set-Cookie', 'welite_probe=1; Path=/');
    response.setHeader('Content-Type', 'text/html');
    const cookieState = request.headers.cookie ? 'cookie received' : 'no cookie';
    response.end('<p id="probe">' + cookieState + '</p>' +
      '<script>document.getElementById("probe").textContent = "JavaScript ran";</script>');
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const url = 'http://127.0.0.1:' + server.address().port;
    await page.goto(url);
    await page.reload();
    assert.equal(await page.locator('#probe').textContent(), 'no cookie',
      'Chromium must omit first-party cookies and leave JavaScript disabled');
    assert.equal((await context.cookies()).length, 0, 'Chromium must reject first-party cookies');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

(async () => {
  const profile = await mkdtemp(join(tmpdir(), 'wlboard-'));
  let context;
  try {
    const defaults = join(profile, 'Default');
    await mkdir(defaults);
    await writeFile(join(defaults, 'Preferences'), JSON.stringify({
      profile: { default_content_setting_values: { cookies: 2 } },
    }));
    context = await chromium.launchPersistentContext(profile, {
      channel: 'chromium', headless: true, args: ['--no-sandbox'], javaScriptEnabled: false, userAgent: 'Welite-test',
    });
    const page = await context.newPage();
    await verifyCookieBlocking(page, context);
    await page.goto(`${process.argv[2]}/board?id=protected&sessionId=${process.argv[3]}`);
    const exportLinks = page.locator('a[href^="/board/export?"]');
    assert.equal(await exportLinks.count(), 2);
    for (const link of await exportLinks.all()) {
      const [download] = await Promise.all([page.waitForEvent('download'), link.click()]);
      assert.equal(await download.failure(), null);
      const chunks = [];
      for await (const chunk of await download.createReadStream()) chunks.push(chunk);
      const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      assert.equal(payload._format, 'wekan-board-1.0.0');
      assert(payload.cards.some(card => card._id === 'card'));
    }
    console.log('PASS: Chromium downloads both board JSON modes with JavaScript and first-party cookies disabled');
    assert.equal(await page.locator('td[data-list=todo]').getByText('Card <test>').count(), 1);
    await page.locator('input[name=sel_card][value=card]').check();
    await page.locator('input[type=submit][name=move_right]').click();
    await page.locator('a[data-view-dir=right]').click();
    assert.equal(await page.getByText('X 2 Y 1', { exact: false }).count(), 1);
    assert.equal(await page.locator('td[data-list=doing]').getByText('Card <test>').count(), 1);
    assert.equal(await page.locator('td[data-list=todo]').getByText('Card <test>').count(), 0);
    const minimap = page.locator('table[data-board-map]');
    const activeCell = minimap.locator('td[bgcolor="#ffff66"]');
    assert.equal(await activeCell.count(), 1);
    assert.equal(await activeCell.evaluate(cell => getComputedStyle(cell).backgroundColor), 'rgb(255, 255, 102)');
    assert.equal(await minimap.locator('td').nth(0).textContent(), '-');
    assert.equal(await minimap.locator('td').nth(1).textContent(), '*');
    await minimap.locator('a').first().click();
    assert.equal(await page.locator('td[data-list=todo]').count(), 1);
    assert.equal(await page.locator('td[data-list=doing]').count(), 0);
    for (const width of [320, 768, 1920]) {
      await page.setViewportSize({ width, height: 800 });
      assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth));
    }
    await page.locator('a[href*="view=all"]').click();
    assert.equal(await page.locator('td[data-list=todo]').count(), 1);
    assert.equal(await page.locator('td[data-list=doing]').count(), 1);
    const lists = `${process.argv[2]}/api/boards/protected/lists`;
    const deleted = await context.request.delete(`${lists}/doing`, {
      headers: { Authorization: `Bearer ${process.argv[3]}`, 'User-Agent': 'Welite-test' },
    });
    assert.equal(deleted.status(), 200, await deleted.text());
    await page.reload();
    assert.equal(await page.locator('td[data-list=doing]').count(), 0);
    const restore = page.locator('form[action="/board/restore-list"]')
      .filter({ has: page.locator('input[name=listId][value=doing]') });
    await restore.locator('input[type=submit]').click();
    await page.locator('a[href*="view=all"]').click();
    assert.equal(await page.locator('td[data-list=doing]').getByText('Card <test>').count(), 1);
    assert.equal(await restore.count(), 0);
    console.log('PASS: Chromium restores a deleted list and its cards with JavaScript and cookies disabled');
    assert.equal((await context.cookies()).length, 0);
    console.log('PASS: Chromium card movement, minimap and viewport navigation with JavaScript and cookies disabled');
  } finally {
    try { await context?.close(); }
    finally { await rm(profile, { recursive: true, force: true }); }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

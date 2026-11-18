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

async function withCookieFreeChromium(test, options = {}) {
  const profile = await mkdtemp(join(tmpdir(), 'wlchrom-'));
  let context;
  try {
    const defaults = join(profile, 'Default');
    await mkdir(defaults);
    await writeFile(join(defaults, 'Preferences'), JSON.stringify({
      profile: { default_content_setting_values: { cookies: 2 } },
    }));
    context = await chromium.launchPersistentContext(profile, {
      ...options, channel: 'chromium', headless: true, args: ['--no-sandbox'],
      javaScriptEnabled: false,
    });
    const page = await context.newPage();
    await verifyCookieBlocking(page, context);
    return await test(page, context);
  } finally {
    try { await context?.close(); }
    finally { await rm(profile, { recursive: true, force: true }); }
  }
}

module.exports = { withCookieFreeChromium };

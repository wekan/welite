const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const words = tag => JSON.parse(fs.readFileSync(path.join(root, 'i18n/data', tag+'.jsn'), 'utf8'));
(async () => {
  const browser = await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context = await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test',
      extraHTTPHeaders:{'Accept-Language':'fi'}});
    await context.route('**/*',async route=>{
      const headers={...route.request().headers()};delete headers.cookie;
      await route.continue({headers});
    });
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    const base = process.argv[2];
    for (const [tag, session, role] of [['ar',process.argv[3],'admin'],['fi',process.argv[4],'member'],['he','','guest']]) {
      const local=words(tag);const query=new URLSearchParams({lang:tag});
      if (session) query.set('sessionId',session);
      const response=await page.goto(base+'/?'+query);
      assert.equal(response.status(),200);
      assert.equal(await page.locator('h2').innerText(),local.boards);
      assert.equal(await page.locator('html').getAttribute('lang'),tag);
      assert.equal((await page.locator('html').getAttribute('dir'))||'ltr',tag==='fi'?'ltr':'rtl');
      assert.equal(await page.getByRole('link',{name:local['log-in'],exact:true}).count(),1);
      assert.equal(await page.getByRole('link',{name:local.register,exact:true}).count(),1);
      assert.equal(await page.locator('a[href*="id=homelang"]').count(),role==='guest'?0:1);
      if (role!=='guest') assert.equal(await page.locator('a[href*="id=homelang"]').innerText(),'Home <safe>');
      if (role==='admin') {
        assert.equal(await page.locator('b').innerText(),local.admin);
        assert.equal(await page.locator('a[href^="/admin?"]').innerText(),local['admin-panel']);
      } else assert.equal(await page.locator('a[href^="/admin?"]').count(),0);
      if (role==='member') assert((await page.locator('body').innerText()).includes(local.username+': member'));
      await page.getByRole('link',{name:local['log-in'],exact:true}).click();
      assert.equal(new URL(page.url()).searchParams.get('lang'),tag);
      assert.equal(new URL(page.url()).searchParams.has('sessionId'),false);
      assert.equal(await page.locator('h1').innerText(),local['log-in']);
    }
    // Header-only anonymous view follows this request, not the previous Hebrew query.
    await page.goto(base+'/');
    assert.equal(await page.locator('h2').innerText(),words('fi').boards);
    assert.equal((await page.locator('html').getAttribute('dir'))||'ltr','ltr');
    assert.equal(await page.locator('a[href*="id=homelang"]').count(),0);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium native home captions, private-board/role isolation and translated auth navigation without JavaScript/cookies');
    await context.close();
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exit(1);});

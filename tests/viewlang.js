const { chromium }=require(process.env.WELITE_PLAYWRIGHT||'playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');
const words=tag=>JSON.parse(fs.readFileSync(path.join(__dirname,'../i18n/data',tag+'.jsn'),'utf8'));
(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test',extraHTTPHeaders:{'Accept-Language':'fi'}});
    await context.route('**/*',async route=>{
      const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});
    });
    const page=await context.newPage();page.setDefaultTimeout(15000);
    for(const [tag,session,explicit] of [['fi','',false],['ar',process.argv[3],false],['he',process.argv[4],false],['fi',process.argv[3],true]]) {
      const query=new URLSearchParams();if(session)query.set('sessionId',session);if(explicit)query.set('lang',tag);
      const response=await page.goto(process.argv[2]+'/viewlang?'+query);
      assert.equal(response.status(),200);assert.equal(response.headers()['content-language'],tag);
      assert.equal(await page.locator('h2').innerText(),words(tag).boards);
      assert.equal(await page.locator('html').getAttribute('lang'),tag);
      const boards=page.locator('a[href*="/board?id=viewlang"]');
      assert.equal(await boards.count(),session?1:0);
      const link=new URL(await page.getByRole('link',{name:'State link',exact:true}).getAttribute('href'),process.argv[2]);
      assert.equal(link.searchParams.get('lang'),tag);assert.equal(link.hash,'#spot');
      assert.equal(link.searchParams.get('sessionId'),session||null);
      if(session) {
        const form=page.locator('form[action="/viewlang/action"]');
        assert.equal(await form.locator('input[name=lang]').inputValue(),tag);
        assert.equal(await form.locator('input[name=sessionId]').inputValue(),session);
        assert.equal(await form.locator('input[name=auth_action]').inputValue(),'widget:viewbutton');
        await boards.click();
        assert.equal(new URL(page.url()).searchParams.get('lang'),tag);
        assert.equal(await page.locator('h1').innerText(),'View <private>');
      }
    }
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium published view captions, links and signed hidden locale match header/profile/query without JavaScript/cookies');
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

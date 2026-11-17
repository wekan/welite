const { chromium }=require(process.env.WELITE_PLAYWRIGHT||'playwright');
const assert=require('node:assert/strict');
(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test'});
    await context.route('**/*',async route=>{const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});});
    const page=await context.newPage(),base=process.argv[2],session=process.argv[3];
    for(const [direction,language,rtl] of [['rtl','fi',true],['ltr','ar',false]]) {
      await page.goto(`${base}/wb-${direction}?sessionId=${session}&lang=${language}`);
      const todo=page.locator('td[data-list="todo"]'),doing=page.locator('td[data-list="doing"]');
      assert.equal((await todo.boundingBox()).x>(await doing.boundingBox()).x,rtl);
      const card=page.locator('input[name=sel_card][value=card]');
      const start=await card.evaluate(node=>node.closest('td[data-list]').getAttribute('data-list'));
      const right=(start==='todo')!==rtl;
      let step=0;
      for(const move of [right?'right':'left',right?'left':'right']) {
        await card.check();await page.locator(`input[name=dir][value=${move}]`).click();
        if(step++===0)assert.notEqual(await card.evaluate(node=>node.closest('td[data-list]').getAttribute('data-list')),start);
        assert.equal(new URL(page.url()).pathname,`/wb-${direction}`);
        assert.equal(new URL(page.url()).searchParams.get('lang'),language);
      }
      assert.equal(await card.evaluate(node=>node.closest('td[data-list]').getAttribute('data-list')),start);
    }
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium published fixed RTL/LTR board widgets, physical columns/moves and origin redirects without JavaScript/cookies');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

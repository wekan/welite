const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test'});
    await context.route('**/*',async route=>{
      const headers={...route.request().headers()};delete headers.cookie;
      await route.continue({headers});
    });
    const page=await context.newPage();const base=process.argv[2];
    const locale=()=>assert.equal(new URL(page.url()).searchParams.get('lang'),'ar');
    await page.goto(base+'/?sessionId='+process.argv[3]+'&lang=ar');
    await page.locator('a[href^="/board?id=protected"]').click();locale();
    assert.equal(await page.locator('html').getAttribute('dir'),'rtl');
    assert.equal(await page.locator('input[name=lang]').inputValue(),'ar');
    await page.locator('input[name=action][value=clear]').click();locale();
    assert.equal(await page.locator('input[name=lang]').inputValue(),'ar');
    await page.getByRole('link',{name:'All boards',exact:true}).click();locale();
    await page.getByRole('link',{name:'Admin Panel',exact:true}).click();locale();
    await page.getByRole('link',{name:'Designer',exact:true}).first().click();locale();
    const id=new URL(process.argv[4],base).searchParams.get('id');
    await page.locator('a[href*="/designer/page?id='+id+'"]').click();locale();
    await page.locator('form[action="/designer/page/save"] input[type=submit]').click();locale();
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium locale survives board/clear/home/admin/Designer/save navigation without JavaScript/cookies');
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

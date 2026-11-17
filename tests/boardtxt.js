const {chromium}=require(process.env.WELITE_PLAYWRIGHT||'playwright');
const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const words=tag=>JSON.parse(fs.readFileSync(path.join(__dirname,'../i18n/data',tag+'.jsn'),'utf8'));
(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test',extraHTTPHeaders:{'Accept-Language':'fi'}});
    await context.route('**/*',async route=>{
      const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});
    });
    const page=await context.newPage();page.setDefaultTimeout(15000);const base=process.argv[2];
    for(const tag of ['fi','ar','he']) {
      const local=words(tag);
      await page.goto(base+'/board?id=boardtxt&lang='+tag);
      assert.equal(await page.title(),local.board);
      assert.equal(await page.locator('h1').innerText(),'Board <user>');
      assert.equal(await page.locator('table[data-board-map]').getAttribute('summary'),local.board+' / '+local.view);
      assert((await page.locator('body').innerText()).includes(local['color-yellow']+': '+local.current+'; *: '+local.cards+'; -: '+local['no-items-message']));
      const direction=tag==='fi'?'right':'left';
      const view=page.locator('a[data-view-dir='+direction+']');
      assert.equal(await view.innerText(),local.view+' '+(direction==='right'?'>':'<'));
      assert.equal(await view.getAttribute('dir'),'ltr');
      await view.click();assert.equal(new URL(page.url()).searchParams.get('x'),'2');

      assert.equal(await page.getByRole('link',{name:local['all-boards'],exact:true}).count(),1);
      await page.getByRole('link',{name:local['view-all'],exact:true}).click();
      assert.equal(new URL(page.url()).searchParams.get('view'),'all');
      assert.equal(new URL(page.url()).searchParams.get('lang'),tag);
      assert((await page.locator('body').innerText()).includes(local['no-items-message']));
      assert.equal(await page.locator('input[name^=move_]').count(),0);
      await page.getByRole('link',{name:local['all-boards'],exact:true}).click();
      assert.equal(await page.locator('h2').innerText(),local.boards);
      await page.goto(base+'/board?id=boardnone&lang='+tag);
      assert((await page.locator('body').innerText()).includes(local['no-items-message']));
      const response=await page.goto(base+'/board?id=missing-txt&lang='+tag);
      assert.equal(response.status(),404);assert.equal(await page.title(),local.board);
      assert((await page.locator('body').innerText()).includes(local['board-not-found']));
      assert(!(await page.locator('body').innerText()).includes('Board <user>'));
    }
    await page.goto(base+'/board?id=boardtxt');
    assert.equal(await page.title(),words('fi').board);
    assert.equal(await page.getByRole('link',{name:words('fi')['view-all'],exact:true}).count(),1);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium native board titles/overview links, empty states, private not-found text and header-only language without JavaScript/cookies');
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

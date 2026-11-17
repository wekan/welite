const {chromium}=require(process.env.WELITE_PLAYWRIGHT||'playwright');
const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const words=tag=>JSON.parse(fs.readFileSync(path.join(__dirname,'../i18n/data',tag+'.jsn'),'utf8'));
(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test',extraHTTPHeaders:{'Accept-Language':'fi'}});
    await context.route('**/*',async route=>{const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});});
    const page=await context.newPage();page.setDefaultTimeout(15000);
    for(const tag of ['fi','ar','he']) {
      const local=words(tag);
      await page.goto(process.argv[2]+'/board?id=editlang&view=all&sessionId='+process.argv[3]+'&lang='+tag);
      for(const kind of ['card','list','swimlane'])
        await page.locator('input[name=sel_'+kind+']').check();
      await page.getByRole('button',{name:local.edit,exact:true}).click();
      assert.equal(await page.title(),local.edit+' / '+local['multi-selection']);
      assert.equal(await page.locator('h1').innerText(),local.edit+' / '+local['multi-selection']);
      assert.equal(await page.getByLabel(local.title,{exact:true}).count(),3);
      assert.equal(await page.getByLabel(local['allboards.workspace-color'],{exact:true}).count(),3);
      assert.equal(await page.getByLabel(local.description,{exact:true}).inputValue(),'Description <user> & 漢字');
      assert.equal(await page.locator('input[name^=title_card_]').inputValue(),'Card <user> & 漢字');
      assert.equal(await page.locator('input[name=action_save]').inputValue(),local.save);
      await page.getByRole('button',{name:local.save,exact:true}).click();
      assert.equal(new URL(page.url()).searchParams.get('id'),'editlang');
      assert.equal(new URL(page.url()).searchParams.get('lang'),tag);
      assert.equal(await page.getByText('Card <user> & 漢字',{exact:true}).count(),1);
    }
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium native selection edit labels/save, scoped fields, UTF-8 user content and locale round trips without JavaScript/cookies');
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

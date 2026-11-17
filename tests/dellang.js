const {chromium}=require(process.env.WELITE_PLAYWRIGHT||'playwright');
const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
(async()=>{
  const tag=process.argv[4];const local=JSON.parse(fs.readFileSync(path.join(__dirname,'../i18n/data',tag+'.jsn'),'utf8'));
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test',extraHTTPHeaders:{'Accept-Language':'fi'}});
    await context.route('**/*',async route=>{const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});});
    const page=await context.newPage();page.setDefaultTimeout(15000);const base=process.argv[2];
    await page.goto(base+'/board?id=dlboard&view=all&sessionId='+process.argv[3]+'&lang='+tag);
    const preview=async()=>{
      await page.locator('input[name=sel_list][value=dllist]').check();
      await page.getByRole('button',{name:local['r-delete-selected'],exact:true}).click();
      assert.equal(await page.title(),local.confirm+' / '+local['r-delete-selected']);
      assert.equal(await page.locator('h1[data-delete-confirm]').innerText(),local.confirm+' / '+local['r-delete-selected']);
      assert.equal(await page.locator('h2').innerText(),local.details);
      for(const [kind,count] of [['cards','2'],['lists','1'],['swimlanes','0'],['card_dependencies','2'],['card_comments','2'],['attachments','1']])
        assert.equal(await page.locator('dd[data-delete-count='+kind+']').innerText(),count);
      for(const kind of ['boards','board_labels','custom_fields','custom_field_boards','custom_field_dropdown_items'])
        assert.equal(await page.locator('dt[data-delete-kind='+kind+']').count(),0);
      assert.equal(await page.getByRole('button',{name:local.confirm,exact:true}).count(),1);
    };
    await preview();
    await page.getByRole('link',{name:local.cancel,exact:true}).click();
    assert.equal(new URL(page.url()).searchParams.get('lang'),tag);
    assert.equal(await page.locator('input[name=sel_card][value=dlcard]').count(),1);
    assert.equal(await page.locator('input[name=sel_card][value=dlchild]').count(),1);
    await preview();
    const stale=await page.locator('form[action="/board/move"]').evaluate(form=>Object.fromEntries([...form.querySelectorAll('input[type=hidden]')].map(input=>[input.name,input.value])));
    await page.getByRole('button',{name:local.confirm,exact:true}).click();
    assert.equal(new URL(page.url()).searchParams.get('lang'),tag);
    assert.equal(await page.locator('input[name=sel_list][value=dllist]').count(),0);
    assert.equal(await page.locator('input[name=sel_card][value=dlcard]').count(),0);
    assert.equal(await page.locator('input[name=sel_card][value=dlchild]').count(),0);
    assert.equal(await page.locator('input[name=sel_card][value=dlkeep]').count(),1);
    const bound=await context.request.get(base+'/board?id=dlboard&view=all&sessionId='+process.argv[3]+'&lang='+tag);
    assert.equal(bound.status(),200);assert((await bound.text()).includes('name="action_delete"'));
    // Retarget replay to an intact owned card so missing selected IDs cannot mask a reused proof.
    delete stale.sel_list;stale.sel_card='dlkeep';stale['action_confirm-delete']=local.confirm;
    const replay=await context.request.post(base+'/board/move',{form:stale});
    assert.equal(replay.status(),403);assert.equal(replay.headers()['content-language'],tag);
    await page.reload();assert.equal(await page.locator('input[name=sel_card][value=dlkeep]').count(),1);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium '+tag+' native delete details/cancel/confirm, scoped counts, preserved sibling and proof replay refusal without JavaScript/cookies');
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

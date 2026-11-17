const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test',acceptDownloads:true});
    await context.route('**/*',async route=>{
      const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});
    });
    const base=process.argv[2], session=process.argv[3], page=await context.newPage();
    const created=await context.request.post(`${base}/api/boards/actions/lists/apreserve/cards?token=${session}`,{form:{title:'Browser action card',description:'Original',swimlaneId:'aother'}});
    assert.equal(created.status(),200);
    const id=(await created.json())._id;
    await page.goto(`${base}/board?id=actions&view=all&sessionId=${session}`);
    const select=()=>page.locator(`input[name=sel_card][value="${id}"]`);
    await select().check();
    await page.locator('input[name=action_edit]').click();
    await page.locator(`input[name="title_card_${id}"]`).fill('Browser edited card');
    await page.locator(`textarea[name="description_card_${id}"]`).fill('Changed in no-JS form');
    await page.locator('input[name=action_save]').click();
    assert.equal(await page.getByText('Browser edited card',{exact:true}).count(),1);
    await select().check();
    const [download]=await Promise.all([page.waitForEvent('download'),page.locator('input[name=action_export]').click()]);
    const chunks=[];for await(const chunk of await download.createReadStream())chunks.push(chunk);
    const graph=JSON.parse(Buffer.concat(chunks).toString());
    assert.equal(download.suggestedFilename(),'select.jsn');
    assert.equal(graph.data.cards[0].description,'Changed in no-JS form');
    // Read-only export keeps the still-visible form usable for the next action.
    await select().check();
    await page.locator('input[name=action_clear]').click();
    assert.equal(await select().isChecked(),false);
    await select().check();
    await page.locator('input[name=action_clone]').click();
    assert.equal(await page.getByText('Browser edited card Copy',{exact:true}).count(),1);
    const rows=await context.request.get(`${base}/api/boards/actions/lists/apreserve/cards?token=${session}`);
    const cloned=(await rows.json()).find(card=>card.title==='Browser edited card Copy');
    assert(cloned && cloned._id!==id);
    await page.locator(`input[name=sel_card][value="${cloned._id}"]`).check();
    await page.locator('input[name=action_delete]').click();
    await page.locator('input[name="action_confirm-delete"]').click();
    assert.equal(await page.locator(`input[name=sel_card][value="${cloned._id}"]`).count(),0);
    await select().check();
    await page.locator('input[name=action_delete]').click();
    assert.equal(await page.locator('h1[data-delete-confirm]').count(),1);
    await page.locator('input[name="action_confirm-delete"]').click();
    assert.equal(await select().count(),0);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium selected Edit/Save/Export/Clear/Clone/confirmed Delete with JavaScript and cookies disabled');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

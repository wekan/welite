const {chromium}=require(process.env.WELITE_PLAYWRIGHT||'playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
 try {
  const context=await browser.newContext({javaScriptEnabled:false,userAgent:'Welite-test'});
  await context.route('**/*',async route=>{const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers});});
  const page=await context.newPage(),base=process.argv[2],session=process.argv[3];
  for(const [language,rtl] of [['ar',true],['fi',false]]) {
   await page.goto(`${base}/tabrtl?sessionId=${session}&lang=${language}&tp_tabrtl=2`);
   const first=page.getByRole('columnheader',{name:'First column',exact:true});
   const second=page.getByRole('columnheader',{name:'Second column',exact:true});
   assert.equal((await first.boundingBox()).x>(await second.boundingBox()).x,rtl);
   const table=first.locator('xpath=ancestor::table[1]');
   const editable=table.locator('td').filter({has:page.locator('a[href*="field=username"]')});
   const plain=table.locator('td').filter({hasNot:page.locator('a')});
   assert.equal((await editable.boundingBox()).x>(await plain.boundingBox()).x,rtl);
   // Simulate a browser that ignores table dir: structural order must stand alone.
   await page.evaluate(()=>{const style=document.createElement('style');style.textContent='table { direction:ltr !important; }';document.head.appendChild(style);});
   assert.equal((await first.boundingBox()).x>(await second.boundingBox()).x,rtl);
   const previous=page.getByRole('link',{name:rtl?'Prev >':'< Prev',exact:true});
   const next=page.getByRole('link',{name:rtl?'< Next':'Next >',exact:true});
   assert.equal((await previous.boundingBox()).x>(await next.boundingBox()).x,rtl);
   assert.equal(await previous.evaluate(node=>getComputedStyle(node).direction),'ltr');
   const search=page.locator('form[method="GET"]');
   assert.equal((await search.boundingBox()).x>(await previous.boundingBox()).x,rtl);
   await next.click();assert.equal(new URL(page.url()).searchParams.get('tp_tabrtl'),'3');
   await previous.click();assert.equal(new URL(page.url()).searchParams.get('tp_tabrtl'),'2');
   await page.getByRole('checkbox',{name:'Second column'}).uncheck();
   await page.getByRole('button',{name:'Apply',exact:true}).click();
   assert.equal(await page.getByRole('columnheader').count(),1);
   assert.equal(new URL(page.url()).searchParams.get('lang'),language);
   await page.locator('input[name=tq_tabrtl]').fill('Table fixture');
   await page.getByRole('button',{name:'Apply',exact:true}).click();
   await next.click();
   const params=new URL(page.url()).searchParams;
   assert.equal(params.get('tq_tabrtl'),'Table fixture');
   assert.deepEqual(params.getAll('tc_tabrtl'),['username']);
   assert.equal(params.get('lang'),language);
   assert.equal(await page.getByRole('columnheader').count(),1);
  }
  assert.equal((await context.cookies()).length,0);
  console.log('PASS: Chromium data-table RTL/LTR headers and cells, ignored-dir structural order and column selection without JavaScript/cookies');
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

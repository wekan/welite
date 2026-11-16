const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({ javaScriptEnabled: false, userAgent: 'Welite-test', acceptDownloads: true });
    await context.route('**/*', async route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      await route.continue({ headers });
    });
    const page = await context.newPage(), home = `${process.argv[2]}/designer?sessionId=${process.argv[3]}`;
    const document = {welite_page:1,page:{url:'/uiimport',title:'Browser imported page',cols:1,doctype:'html4',dir:'auto',minRole:'admin'},widgets:[{type:'label',label:'From browser',options_json:'{}'}]};
    await page.goto(home);
    let form = page.locator('form[action="/designer/page/import"]');
    await form.locator('input[type=file]').setInputFiles({name:'page.wlp',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(document))});
    await form.locator('input[value="Import page"]').click();
    let row = page.locator('tr').filter({hasText:'Browser imported page'});
    assert.equal(await row.count(),1);
    let [download] = await Promise.all([page.waitForEvent('download'),row.getByRole('link',{name:'Export',exact:true}).click()]);
    const read = async file => {
      const chunks=[];
      for await (const chunk of await file.createReadStream()) chunks.push(chunk);
      return Buffer.concat(chunks);
    };
    assert.equal(download.suggestedFilename(),'page.wlp');
    assert.equal(JSON.parse((await read(download)).toString()).page.title,'Browser imported page');
    // Malformed replacement cannot destroy the page the browser just created.
    document.widgets[0].options_json='[]';
    form=page.locator('form[action="/designer/page/import"]');
    await form.locator('input[type=file]').setInputFiles({name:'bad.wlp',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(document))});
    await form.locator('input[value="Import page"]').click();
    assert.equal(await page.getByText('Invalid page or import failed; existing pages are unchanged',{exact:true}).count(),1);
    await page.goto(home);
    assert.equal(await page.locator('tr').filter({hasText:'Browser imported page'}).count(),1);
    [download]=await Promise.all([page.waitForEvent('download'),page.getByRole('link',{name:'Export all pages',exact:true}).click()]);
    assert.equal(download.suggestedFilename(),'pages.zip');
    const zip=await read(download);
    form=page.locator('form[action="/designer/import"]');
    await form.locator('input[type=file]').setInputFiles({name:'pages.zip',mimeType:'application/zip',buffer:zip});
    await form.locator('input[value="Import ZIP"]').click();
    assert.equal(await page.locator('tr').filter({hasText:'Browser imported page'}).count(),1);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium page/ZIP upload and download, invalid replacement preservation, with JavaScript and cookies disabled');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });

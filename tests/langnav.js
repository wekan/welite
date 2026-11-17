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
    const all=new URL(page.url());all.searchParams.set('view','all');await page.goto(all.href);
    const todo=await page.locator('td[data-list="todo"]').boundingBox();
    const doing=await page.locator('td[data-list="doing"]').boundingBox();
    assert(todo.x>doing.x,'RTL logical first list must appear on the right');
    const map=page.locator('table[summary="Board minimap"]');
    const first=await map.locator('a[href*="&x=1&"]').boundingBox();
    const second=await map.locator('a[href*="&x=2&"]').boundingBox();
    assert(first.x>second.x,'RTL minimap must match physical board columns');
    await page.getByRole('link',{name:'View left',exact:true}).click();locale();
    assert.equal(new URL(page.url()).searchParams.get('x'),'2');
    assert.equal(await page.locator('td[data-list="doing"]').count(),1);
    assert.equal(await page.locator('td[data-list="todo"]').count(),0);
    await page.getByRole('link',{name:'View right',exact:true}).click();locale();
    assert.equal(new URL(page.url()).searchParams.get('x'),'1');
    assert.equal(await page.locator('td[data-list="todo"]').count(),1);
    await page.goto(all.href);
    const keypad=page.locator('form[action="/board/move"]');
    const left=await keypad.locator('input[name=dir][value=left]').boundingBox();
    const down=await keypad.locator('input[name=dir][value=down]').boundingBox();
    const right=await keypad.locator('input[name=dir][value=right]').boundingBox();
    const up=await keypad.locator('input[name=dir][value=up]').boundingBox();
    assert(left.x<down.x && down.x<right.x,'RTL keypad must retain physical left/down/right positions');
    assert(up.y<down.y,'up stays above down');
    await page.locator('input[name=sel_card][value=card]').check();
    await page.locator('input[name=dir][value=right]').click();locale();
    assert.equal(await page.locator('td[data-list="todo"] input[name=sel_card][value=card]').count(),1);
    await page.locator('input[name=sel_card][value=card]').check();
    await page.locator('input[name=dir][value=left]').click();locale();
    assert.equal(await page.locator('td[data-list="doing"] input[name=sel_card][value=card]').count(),1);
    await page.locator('input[name=sel_list][value=todo]').check();
    await page.locator('input[name=dir][value=left]').click();locale();
    assert((await page.locator('td[data-list="todo"]').boundingBox()).x <
      (await page.locator('td[data-list="doing"]').boundingBox()).x,'selected list moves physically left');
    await page.locator('input[name=sel_list][value=todo]').check();
    await page.locator('input[name=dir][value=right]').click();locale();
    assert((await page.locator('td[data-list="todo"]').boundingBox()).x >
      (await page.locator('td[data-list="doing"]').boundingBox()).x,'selected list moves physically right');
    await page.locator('input[name=action][value=clear]').click();locale();
    assert.equal(await page.locator('input[name=lang]').inputValue(),'ar');
    await page.getByRole('link',{name:'All boards',exact:true}).click();locale();
    await page.locator('a[href^="/admin?"]').click();locale();
    await page.getByRole('link',{name:'Designer',exact:true}).first().click();locale();
    const id=new URL(process.argv[4],base).searchParams.get('id');
    await page.locator('a[href*="/designer/page?id='+id+'"]').click();locale();
    await page.locator('form[action="/designer/page/save"] input[type=submit]').click();locale();
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium locale survives board/clear/home/admin/Designer/save navigation without JavaScript/cookies');
    await context.close();
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});

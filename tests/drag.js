const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({ headless:true,args:['--no-sandbox'] });
  try {
    const context = await browser.newContext({userAgent:'Welite-test',hasTouch:true});
    await context.route('**/*', async route => { const headers={...route.request().headers()};delete headers.cookie;await route.continue({headers}); });
    const page=await context.newPage();
    page.on('response',async response=>{if(response.status()>=400) console.error('HTTP diagnostic',new URL(response.url()).pathname,response.status(),(await response.text()).slice(0,150));});
    const errors=[];page.on('pageerror',error=>errors.push(error.message));
    await page.goto(`${process.argv[2]}/board?id=drag&view=all&sessionId=${process.argv[3]}`);
    await page.waitForFunction(()=>window.interact && document.querySelector('[role=status]'),null,{timeout:10000});
    await page.evaluate(()=>{window.dragEvents=[];interact.on('dragstart dragend drop',event=>window.dragEvents.push({type:event.type,target:event.target.outerHTML.slice(0,200)}));});
    await page.locator('input[name=sel_card][value=dcard1]').check();
    await page.locator('input[name=sel_card][value=dcard2]').check();
    const card=page.locator('[data-id=dcard1]');
    const target=page.locator('td[data-list=dlist1]');
    const start=await card.boundingBox(),end=await target.boundingBox();
    const navigation=page.waitForNavigation({timeout:10000}).catch(async error=>{console.error('Drag diagnostic:',await page.locator('[role=status]').allTextContents(),errors,await page.evaluate(()=>window.dragEvents));throw error;});
    await page.mouse.move(start.x+start.width*0.7,start.y+start.height/2);
    await page.mouse.down();
    await page.mouse.move(end.x+end.width/2,end.y+end.height/2,{steps:20});
    await page.mouse.up();
    await navigation;
    assert.equal(await target.locator('[data-id]').count(),2);
    assert.equal(await page.locator('td[data-list=dlist2] [data-id]').count(),0);
    await page.waitForFunction(()=>window.interact && document.querySelector('[role=status]'));
    const client=await context.newCDPSession(page);
    const starts=[];
    for (const id of ['dcard1','dcard2']) {
      const box=await page.locator('[data-id='+id+']').boundingBox();
      starts.push({x:box.x+box.width*0.7,y:box.y+box.height/2});
    }
    const destination=await page.locator('td[data-list=dlist2]').boundingBox();
    function fingers(fraction) { return starts.map((point,id)=>({id,x:point.x+(destination.x+destination.width*0.7-point.x)*fraction,y:point.y+(destination.y+destination.height/2+(id?2:-2)-point.y)*fraction,radiusX:2,radiusY:2,force:1})); }
    await client.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:fingers(0)});
    for (let step=1;step<=20;step++) await client.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:fingers(step/20)});
    const reload=page.waitForNavigation({timeout:10000});
    await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[fingers(1)[1]]});
    await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
    await reload;
    assert.equal(await page.locator('td[data-list=dlist2] [data-id]').count(),2);
    assert.deepEqual(errors,[]);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: Chromium pointer selection drag and simultaneous two-finger moves cross lanes through the shared endpoint without cookies');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

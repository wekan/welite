const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const { createHmac } = require('node:crypto');
const assert = require('node:assert/strict');
function otp(secret,counter) {
  const alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits=0,value=0; const bytes=[];
  for (const letter of secret) {
    value=(value<<5)|alphabet.indexOf(letter); bits+=5;
    if (bits>=8) { bits-=8; bytes.push((value>>>bits)&255); }
  }
  const block=Buffer.alloc(8);block.writeBigUInt64BE(BigInt(counter));
  const digest=createHmac('sha1',Buffer.from(bytes)).update(block).digest();
  return String((digest.readUInt32BE(digest[19]&15)&0x7fffffff)%1000000).padStart(6,'0');
}
(async () => {
  const browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  try {
    const context=await browser.newContext({javaScriptEnabled:false});
    await context.route('**/*',async route=>{
      const headers={...route.request().headers()};delete headers.cookie;
      await route.continue({headers});
    });
    const page=await context.newPage(); const base=process.argv[2];
    await page.goto(base+'/sign-in');
    await page.getByRole('link',{name:'Set up one-time codes'}).click();
    await page.locator('input[name=username]').fill('browser-enroll');
    await page.locator('input[name=password]').fill('test-password');
    await page.getByRole('button',{name:'Start setup'}).click();
    const secret=await page.locator('#otp-secret').innerText();assert.match(secret,/^[A-Z2-7]{32}$/);
    const counter=Math.floor(Date.now()/30000);
    assert.equal(new URL(page.url()).search,'');
    await page.locator('input[name=code]').fill(otp(secret,counter));
    await page.getByRole('button',{name:'Confirm',exact:true}).click();
    assert.match(await page.locator('body').innerText(),/One-time codes enabled/);
    assert.equal(new URL(page.url()).search,'');
    await page.getByRole('link',{name:'sign in',exact:true}).click();
    await page.locator('input[name=username]').fill('browser-enroll');
    await page.locator('input[name=password]').fill('test-password');
    await page.locator('input[name=code]').fill(otp(secret,counter+1));
    await page.getByRole('button',{name:/^(Sign in|Log In)$/,exact:true}).click();
    await page.waitForURL(url=>url.searchParams.has('sessionId'));
    assert.match(await page.locator('body').innerText(),/Signed in as browser-enroll/);
    assert.deepEqual([...new URL(page.url()).searchParams.keys()],['sessionId']);
    assert.equal((await context.cookies()).length,0);
    console.log('PASS: required enrollment, confirmation and sign-in in Chromium with JavaScript disabled and no Cookie headers');
    await context.close();
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exit(1);});

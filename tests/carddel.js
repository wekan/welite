const { chromium } = require(process.env.WELITE_PLAYWRIGHT || 'playwright');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

(async () => {
  const boardUrl = new URL(process.argv[2]);
  boardUrl.searchParams.set('lang', 'en');
  const token = readFileSync(0, 'utf8').trim();
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const context = await browser.newContext({
      javaScriptEnabled: false,
      userAgent: 'shared-http-test',
    });
    await context.route('**/*', route => {
      const headers = { ...route.request().headers() };
      delete headers.cookie;
      return route.continue({ headers });
    });
    const page = await context.newPage();
    const headers = { Authorization: 'Bearer ' + token };
    const endpoint = list => boardUrl.origin + '/api/boards/b/lists/' + list + '/cards/brow-card';
    const checklist = boardUrl.origin + '/api/boards/b/cards/brow-card/checklists';
    const card = page.getByText('Keep my browser checklist', { exact: true });

    const initial = await page.goto(boardUrl.href);
    assert.equal(initial.status(), 200);
    assert.equal(await initial.headerValue('set-cookie'), null);
    assert.equal(await card.count(), 1);

    const firstTitle = 'First card for browser sorting';
    const secondTitle = 'Keep my browser checklist';
    const order = async (first, second) => {
      const text = await page.locator('body').innerText();
      assert(text.includes(first) && text.includes(second));
      assert(text.indexOf(first) < text.indexOf(second));
    };
    await order(firstTitle, secondTitle);
    const sortResponse = await context.request.put(endpoint('l'), { headers, data: { sort: 0 } });
    assert.equal(sortResponse.status(), 200);
    const sorted = await context.request.get(endpoint('l'), { headers });
    assert.equal(sorted.status(), 200);
    assert.equal((await sorted.json()).sort, 0);
    await page.reload();
    await order(secondTitle, firstTitle);
    console.log('PASS: Chromium reflects a zero REST card sort with JavaScript and cookies disabled');

    for (const [operation, archived] of [['archive', true], ['unarchive', false]]) {
      const path = endpoint('l') + '/' + operation;
      assert.equal((await context.request.post(path)).status(), 401);
      const response = await context.request.post(path, { headers });
      assert.equal(response.status(), 200);
      const saved = await response.json();
      assert.equal(saved._id, 'brow-card');
      assert.equal(saved.archived, archived);
      await page.reload();
      assert.equal(await card.count(), archived ? 0 : 1);
      const repeated = await context.request.post(path, { headers });
      assert.equal(repeated.status(), 404);
      assert.deepEqual(await repeated.json(), { error: 'Card not found' });
    }
    console.log('PASS: Chromium reflects REST archive and restore with JavaScript and cookies disabled');

    const [details] = await Promise.all([
      page.waitForNavigation(),
      page.getByRole('link', { name: secondTitle, exact: true }).click(),
    ]);
    assert.equal(details.status(), 200);
    assert.equal(await details.headerValue('set-cookie'), null);
    const spent = page.getByRole('heading', { name: 'Spent time (hours)', exact: true });
    const overtime = page.getByRole('heading', { name: 'Overtime (hours)', exact: true });
    assert.equal(await spent.count(), 1, await page.locator('body').innerText());
    for (const [isOverTime, content] of [
      [true, { data: { isOverTime: true } }],
      [false, { form: { isOverTime: 'false' } }],
    ]) {
      const edited = await context.request.put(endpoint('l'), { headers, ...content });
      assert.equal(edited.status(), 200);
      const read = await context.request.get(endpoint('l'), { headers });
      assert.equal((await read.json()).isOvertime, isOverTime);
      await page.reload();
      assert.equal(await overtime.count(), isOverTime ? 1 : 0);
      assert.equal(await spent.count(), isOverTime ? 0 : 1);
      assert.equal(await page.getByText('2.0', { exact: true }).count() +
        await page.getByText('2', { exact: true }).count(), 1);
    }
    console.log('PASS: Chromium reflects JSON and form overtime edits without JavaScript or cookies');
    for (const [field, caption] of [['members', 'Members'], ['assignees', 'Assignees']]) {
      const list = page.getByRole('heading', { name: caption, exact: true });
      const assignment = endpoint('l') + '/' + field + '/u';
      assert.equal(await list.count(), 0);
      assert.equal((await context.request.post(assignment, { headers })).status(), 200);
      await page.reload();
      assert.equal(await list.count(), 1);
      assert.equal(await page.locator('li').filter({ hasText: /^user$/ }).count(), 1);
      const removed = await context.request.delete(assignment, { headers });
      assert.equal(removed.status(), 200);
      assert.deepEqual((await removed.json())[field], []);
      await page.reload();
      assert.equal(await list.count(), 0);
    }
    console.log('PASS: Chromium reflects REST member and assignee changes without JavaScript or cookies');
    const cardsApi = boardUrl.origin + '/api/boards/b/lists/l/cards';
    const childTitle = 'REST-created browser subtask';
    const add = await context.request.post(cardsApi, {
      headers, data: { title: childTitle, parentId: 'brow-card', swimlaneId: 's' },
    });
    assert.equal(add.status(), 200);
    const { _id: childId } = await add.json();
    const childApi = cardsApi + '/' + encodeURIComponent(childId);
    const parentUrl = page.url();
    try {
      const saved = await context.request.get(childApi, { headers });
      assert.equal((await saved.json()).parentId, 'brow-card');
      await page.reload();
      const child = page.getByRole('link', { name: childTitle, exact: true });
      assert.equal(await child.count(), 1);
      await child.click();
      assert.equal(await page.getByRole('heading', { name: childTitle, exact: true }).count(), 1);
      await page.goto(parentUrl);
      assert.equal(await child.count(), 1);
      assert.equal((await context.request.post(childApi + '/archive', { headers })).status(), 200);
      await page.reload();
      assert.equal(await child.count(), 0);
    } finally {
      assert.equal((await context.request.delete(childApi, { headers })).status(), 200);
    }
    console.log('PASS: Chromium shows REST-created subtasks and hides archived subtasks without JavaScript or cookies');
    const attachment = Buffer.from([0, 1, 10, 255]);
    const metadata = new URLSearchParams({ boardId: 'b', listId: 'l', swimlaneId: 's',
      cardId: 'brow-card', fileName: 'browser-attachment.bin' });
    const upload = await context.request.post(boardUrl.origin + '/api/attachment/upload?' + metadata, {
      headers: { ...headers, 'Content-Type': 'application/octet-stream' }, data: attachment,
    });
    assert.equal(upload.status(), 200);
    const { attachmentId } = await upload.json();
    const file = page.getByRole('link', { name: 'browser-attachment.bin', exact: true });
    try {
      await page.reload();
      const href = new URL(await file.getAttribute('href'), page.url());
      const anonymousFile = new URL(href);
      anonymousFile.searchParams.delete('sessionId');
      assert.equal((await context.request.get(anonymousFile.href)).status(), 404);
      const wrongCard = new URL(href);
      wrongCard.searchParams.set('card', 'brow-sort');
      assert.equal((await context.request.get(wrongCard.href)).status(), 404);
      const [download] = await Promise.all([page.waitForEvent('download'), file.click()]);
      assert.equal(download.suggestedFilename(), 'browser-attachment.bin');
      assert.deepEqual(readFileSync(await download.path()), attachment);
    } finally {
      const remove = await context.request.delete(boardUrl.origin + '/api/attachment/delete/' +
        encodeURIComponent(attachmentId), { headers });
      assert.equal(remove.status(), 200);
    }
    await page.reload();
    assert.equal(await file.count(), 0);
    console.log('PASS: Chromium downloads an attachment through the HTML card without JavaScript or cookies');
    const englishDetails = page.url();
    const arabicDetails = new URL(englishDetails);
    arabicDetails.searchParams.set('lang', 'ar');
    assert.equal((await page.goto(arabicDetails.href)).status(), 200);
    assert.equal(await page.locator('html').getAttribute('dir'), 'rtl');
    assert.equal(await page.getByRole('link', { name: 'لوحة', exact: true }).count(), 1);
    assert.equal(await page.getByRole('heading', { name: 'الوقت المستغرق (بالساعات)', exact: true }).count(), 1);
    await page.goto(englishDetails);
    console.log('PASS: Chromium renders the Arabic board link and spent-time heading');

    const checklistTitle = page.getByRole('heading', { name: 'Steps', exact: true });
    const checklistItem = page.getByText('Retained REST item', { exact: true });
    assert.equal(await checklistTitle.count(), 1);
    assert.equal(await checklistItem.count(), 1);
    assert.equal((await context.request.get(checklist + '/missing-checklist', { headers })).status(), 404);
    await page.reload();
    assert.equal(await checklistTitle.count(), 1);
    assert.equal(await checklistItem.count(), 1);
    const anonymous = new URL(page.url());
    anonymous.searchParams.delete('sessionId');
    const foreign = new URL(page.url());
    foreign.searchParams.set('id', 'missing-board');
    assert.equal((await page.goto(foreign.href)).status(), 404);
    assert.equal(await checklistTitle.count(), 0);
    assert.equal((await page.goto(anonymous.href)).status(), 404);
    assert.equal(await checklistItem.count(), 0);
    await page.goto(boardUrl.href);
    console.log('PASS: Chromium opens card checklists and items without JavaScript or cookies');

    const wrong = await context.request.delete(endpoint('brow-list'), { headers });
    assert.equal(wrong.status(), 404);
    assert.deepEqual(await wrong.json(), { error: 'Card not found' });
    const preserved = await context.request.get(checklist, { headers });
    assert.equal(preserved.status(), 200);
    assert((await preserved.json()).some(entry => entry._id === 'brow-check'));
    await page.reload();
    assert.equal(await card.count(), 1);

    assert.equal((await context.request.delete(endpoint('l'), { headers })).status(), 200);
    await page.reload();
    assert.equal(await card.count(), 0);
    assert.equal((await context.request.delete(endpoint('l'), { headers })).status(), 404);
    console.log('PASS: Chromium wrong-list REST deletion preserves the card and checklist with JavaScript and cookies disabled');
    metadata.set('cardId', 'brow-sort');
    metadata.set('fileName', 'selection-attachment.bin');
    const selectionUpload = await context.request.post(boardUrl.origin + '/api/attachment/upload?' + metadata, {
      headers: { ...headers, 'Content-Type': 'application/octet-stream' }, data: attachment,
    });
    assert.equal(selectionUpload.status(), 200);
    const { attachmentId: selectedFile } = await selectionUpload.json();
    await page.locator('input[name=sel_card][value=brow-sort]').check();
    await page.locator('input[name=action_delete]').click();
    assert.equal(await page.locator('[data-delete-confirm]').count(), 1);
    await page.locator('input[name=action_confirm-delete]').click();
    assert.equal(await page.getByText(firstTitle, { exact: true }).count(), 0);
    const listing = await context.request.get(boardUrl.origin + '/api/attachment/list/b', { headers });
    assert.equal(listing.status(), 200);
    assert(!(await listing.json()).attachments.some(entry => entry.attachmentId === selectedFile));
    const retained = await context.request.get(boardUrl.origin + '/api/attachment/download/' +
      encodeURIComponent(selectedFile) + '?raw=1', { headers });
    assert.equal(retained.status(), 200);
    assert.deepEqual(await retained.body(), attachment);
    console.log('PASS: Chromium selection deletion hides the card and retains its shared attachment bytes');

  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});

// @ts-check
// WeKan's Playwright configuration, for WeLite's HTML5 view: Weddy's copy of
// WeKan's tests (WEDDY_WEKAN_TESTS, Weddy's tests/wekan - WeKan's specs with
// Weddy's overlay, which signs in with the meteor_login_token cookie as
// WeLite's HTML5 view does), over the WeKan specs that specs.txt names.
// WELITE_WEKAN_SPECS=all runs every WeKan spec instead, to see how far it is,
// and WELITE_WEKAN_SPECS=<file> reads a different list in the same format.
// A title normally matches a fragment. Prefix it with "= " to match the full title.
const fs = require('fs');
const path = require('path');
const W = process.env.WEDDY_WEKAN_TESTS;
if (!W) throw new Error('WEDDY_WEKAN_TESTS: Weddy\'s tests/wekan directory');
const base = require(path.join(W, 'tests/playwright/playwright.config.js'));

const choice = process.env.WELITE_WEKAN_SPECS || '';
const listFile = choice && choice !== 'all' ? path.resolve(choice) : path.join(__dirname, 'specs.txt');
const lines = fs.readFileSync(listFile, 'utf8').split('\n')
  .map(l => l.trim()).filter(l => l && !l.startsWith('#'))
  .map(line => {
    const separator = line.indexOf(': ');
    if (separator < 0) return { file: line };
    const title = line.slice(separator + 2);
    const exact = title.startsWith('= ');
    return { file: line.slice(0, separator), title: (exact ? title.slice(2) : title).split(' › ').join(' '), exact };
  });
const all = choice === 'all';
const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const listed = all ? ['tests/playwright/specs/**/*.e2e.js'] : [...new Set(lines.map(l => l.file.startsWith('weddy-specs/') ? l.file : `tests/playwright/specs/${l.file}`))];
const grep = all ? undefined : new RegExp(lines.map(l => escape(l.file) + (l.title ? (l.exact ? ' ' + escape(l.title) + '$' : '.*' + escape(l.title)) : '')).join('|'));

module.exports = {
  ...base,
  globalSetup: path.join(W, 'tests/playwright/global-setup.js'),
  testDir: W,
  testMatch: listed,
  ...(grep ? { grep } : {}),
  // One server, one database: the specs run one at a time.
  workers: 1,
  outputDir: process.env.WELITE_TEST_RESULTS || path.join(process.env.TMPDIR || '/tmp', 'welite-wkui-results'),
  reporter: [['list']],
};

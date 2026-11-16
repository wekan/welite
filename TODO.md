# WeLite — FreePascal code + design

NOTE: This WeKan-Lite version has retro-look. Modern-look original WeKan is at
https://wekan.fi and https://github.com/wekan/wekan .

Uses DOS filenames 8 characters, with extension 3 characters, like FILENAME.TXT

FreePascal-specific design docs and reference code for WeKan-Lite, **distilled from the two
working prototypes in this tree** and aligned to the portable contract:

- [`.tools/w/wami/wekan.pas`](https://github.com/wekan/wami/blob/main/wekan.pas) — single-file WeKan web prototype (routing + retro HTML surface).
- [`.tools/w/omi/public/server.pas`](https://github.com/wekan/omi/blob/main/public/server.pas) — mature server (no-cookie/no-JS auth, SQLite-via-CLI, i18n).
- `docs/contract.md`, `schema.sql`, `docs/goals.md`, `docs/webstack.md`,
  `docs/schema.md` — the portable contract these target.

## Testing

- Testing with Playwright Chromium, cookies disabled, javascript disabled.
  Running tests like at wekan repo build.sh

## Design

- HTML4 needs to be usable at all screen sizes, like FreeDOS Dillo running at VirtualBox,
  AmigaOS 3.x and 4.x, MorphOS, smartphones, tablets, 55" touch screen, etc.
- Moving swimlanes, lists, cards etc is with checkbox selection and arrow buttons,
  like at .tools/w/tcl-tk-kanban/screenshot-go-fyne.png and
  .tools/w/tcl-tk-kanban/kanban.go where is also SQLite examples what happens when moving
  swimlanes, lists, etc.
- If there is javascript drag drop available, make possible drag drop and multidrag like at .tools/w/weddy/
- Directory structure is same like at .tools/w/weddy , so at multitenancy each domain has it's
  own directory where is files/db/wekan.db , files/attachme/ , files/avatars/ etc according to
  8.3 DOS limit structure, with longer domain names, settings etc at sqlite databases.
- Database structure at WeLite is same like at WeKan FerretDB SQLite .tools/w/FerretDB/ ,
  WeLite is drop-in replacement, but using SQL queries directly, not Javascript queries.
- Moving to other areas of kanban board is done with minimap (like game minimap),
  that is at right top corner of screen, there color highlighted is current position in map.
  Clicking other position at minimap changes that position content to be visible below
  arrows navigation and minimap. There is also visible position coordinates of minimap,
  at left side of minimap, like "X 4 Y 2".
  At minimap is shown is there some data at other positions of map, or is it empty.
- Order of swimlanes, lists, cards etc is similar like at wekan/clients/components/ .jade and .css
  files, with same colors, but with below HTML4 calendar type code that is visible at all browsers
- HTML4 needs to be like this calendar example at wami/wekan.pas,
  so that colors are seen correctly at browsers like Dillo, Amiga IBrowse and Netsurf:

```
procedure calendarEndpoint(aRequest: TRequest; aResponse: TResponse);
begin
  // This calendar has been tested to be visible at: Amiga IBrowse, FreeDOS Dillo, Linux Dillo/Netsurf/Chrome
  //
  // For accessibility, use only one table. Not nested table. Avoid merged or split cells.
  // Consider Alternative Views: For calendars, offer a "list view" or other simplified
  // representations that are inherently more linear and accessible for assistive technology users.
  //

  // background-color: #d1e7dd; Light green to highlight today

  aResponse.Content := '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">' + LineEnding +
                      '<html lang="en">' + LineEnding +
                      '<head>' + LineEnding +
                      '  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">' + LineEnding +
                      '  <title>July 2025 Calendar</title>' + LineEnding +
                      '  <style type="text/css">' + LineEnding +
                      '    table      { width: 100%; border-collapse: collapse; margin-bottom: 20px; }' + LineEnding +
                      '    th, td     { border: 1px solid #ccc; padding: 8px; text-align: center; }' + LineEnding +
                      '    th         { background-color: #f2f2f2; }' + LineEnding +
                      '    .empty-day { background-color: #eee; color: #999; }' + LineEnding +
                      '    .today     { background-color: #d1e7dd; font-weight: bold; border: 2px solid #007bff; }' + LineEnding +
                      '    caption    { font-size: 1.5em; margin-bottom: 10px; font-weight: bold; text-align: left; }' + LineEnding +
                      '  </style>' + LineEnding +
                      '</head>' + LineEnding +
                      '<body bgcolor="#FFFFFF">' + LineEnding +
                      '<p><a href="../">All Pages</a></p>' + LineEnding +
                      '<h1><font face="arial">July 2025</font></h1>' + LineEnding +
                      '<table summary="This table displays the calendar. Days of the week are column headers, and dates are listed under them." width="100%" border-collapse="collapse" margin-bottom="20" border="1" cellpadding="5" cellspacing="0" id="calendartable">' + LineEnding +
                      '  <caption><font size="4" face="arial">July 2025</font></caption>' + LineEnding +
                      '  <thead>' + LineEnding +
                      '    <tr>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Monday</font></th>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Tuesday</font></th>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Wednesday</font></th>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Thursday</font></th>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Friday</font></th>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Saturday</font></th>' + LineEnding +
                      '      <th scope="col" border="1" padding="8" align="center" bgcolor="#f2f2f2"><font size="4" face="arial">Sunday</font></th>' + LineEnding +
                      '    </tr>' + LineEnding +
                      '  </thead>' + LineEnding +
                      '  <tbody>' + LineEnding +
                      '    <tr>' + LineEnding +
                      '      <td class="empty-day" border="1" padding="8" align="center" color="#999999" bgcolor="#eeeeee"><font size="4" face="arial"></font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">1</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">2</font></td>' + LineEnding +
                      '      <td class="today" border="3" padding="8" align="center" bgcolor="#d1e7dd" border="2"><b><font size="4" face="arial">3</font></b></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">4</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">5</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">6</font></td>' + LineEnding +
                      '    </tr>' + LineEnding +
                      '    <tr>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">7</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">8</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">9</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">10</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">11</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">12</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">13</font></td>' + LineEnding +
                      '    </tr>' + LineEnding +
                      '    <tr>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">14</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">15</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">16</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">17</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">18</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">19</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">20</font></td>' + LineEnding +
                      '    </tr>' + LineEnding +
                      '    <tr>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">21</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">22</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">23</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">24</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">25</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">26</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">27</font></td>' + LineEnding +
                      '    </tr>' + LineEnding +
                      '    <tr>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">28</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">29</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">30</font></td>' + LineEnding +
                      '      <td border="1" padding="8" align="center"><font size="4" face="arial">31</font></td>' + LineEnding +
                      '      <td class="empty-day" border="1" padding="8" align="center" color="#999999" bgcolor="#eeeeee"><font size="4" face="arial"></font></td>' + LineEnding +
                      '      <td class="empty-day" border="1" padding="8" align="center" color="#999999" bgcolor="#eeeeee"><font size="4" face="arial"></font></td>' + LineEnding +
                      '      <td class="empty-day" border="1" padding="8" align="center" color="#999999" bgcolor="#eeeeee"><font size="4" face="arial"></font></td>' + LineEnding +
                      '    </tr>' + LineEnding +
                      '  </tbody>' + LineEnding +
                      '</table>' + LineEnding +
                      '<p><a href=".">Back to Home</a></p>' + LineEnding +
                      '</body></html>';
  aResponse.Code := 200;
  aResponse.ContentType := 'text/html';
  aResponse.ContentLength := Length(aResponse.Content);
  aResponse.SendContent;
end;
```

## Read first
- **`docs/arch.md`** — how the prototypes map onto WeKan-Lite: request lifecycle
  (tenant → auth → endpoint), retro-HTML tiers, unit layout, what's still missing.
- **`docs/sqlite.md`** — the one real fork: linked SQLite (default) vs the
  `sqlite3` CLI via `TProcess` (bootstrap/fallback). Both live behind `wldb.pas`.
- **`docs/designer.md`** — the no-JS/no-cookie page builder: data-driven pages, form-driven
  layout editing, custom URLs, LTR/RTL mirroring (one definition), import/export
  (`.wlp` / `.zip`). Schema in `designer.sql`, engine in `wldesign.pas`.
- **`docs/theming.md`** — colors for any element (WeKan palette or hex), choosable color-picker
  components, imported-palette mapping (Trello/Kanboard), and Red Strings as SVG/VML/ASCII
  per browser. Code: `wlcolors.pas`, `wlvector.pas`.
- **`docs/enhance.md`** — the layering rule: no-JS form baseline always works;
  JS+touch features (MultiDrag — drag many cards at once on a big touch screen) auto-activate
  on top, driving the same endpoints. Code: `wlenhanc.pas`.
- **`docs/move.md`** — the default no-JS move UI: select swimlanes/lists/cards, move all
  with one `▲◀▼▶` keypad (combined, like `kanban.go`). Code: `wlmove.pas`.
- **`docs/static.md`** — serving `public/` (robots.txt, css, js, …) and the `i18n/`
  translations tree (`i18n/langs.jsn` + `i18n/data/`) from disk or embedded in the binary.
  Code: `wlstatic.pas`; tools `releases/genasset.py`, `releases/convlang.py`.
- **`docs/api.md`** — REST API subset (Bearer auth) so WeKan's `api.py` works unchanged.
  Code: `wlapi.pas`.
- **`docs/cross.md`** — cross-compiling for every target via `build.sh` option 4 (fpcupdeluxe):
  the build chain, the `-dWLDB_CLI` rule, and the verified per-target support matrix.

## Reference units (v0.1 skeletons)
| File | Implements | Notes |
|------|-----------|-------|
| `wlhttp.lpr` | program entry: routes + `fphttpapp` | wires all units below |
| `wltenant.pas` | **multitenancy** — `Host:` → `data/domains/<domain>/db/data.db` (G8) | the new core; prototypes are single-tenant |
| `wlregist.pas` | domain registry over `data/admin/db/data.db` (G8) | host→tenant map the Global Admin edits |
| `wlauth.pas` | **no-cookie/no-JS auth** — sessions + action-tokens (G4) | from omi; persists to `schema.sql` `login_tokens` |
| `wldb.pas` | SQLite behind one interface; CLI **or** linked backend | `{$DEFINE WLDB_CLI}` selects CLI |
| `wlhtml.pas` | retro-safe HTML 3.2 helpers + pretty printer + dir wrapper | from omi `HtmlEncode`/`PrettyHtml32` |
| `wlbrowse.pas` | User-Agent → browser id (tune output per client) | from wami `WebBrowserName` |
| `wldesign.pas` | **Designer** — data-driven pages, render, LTR/RTL, import/export | new; `docs/designer.md` + `designer.sql` |
| `wlcolors.pas` | WeKan color palette + color-picker components + import-color mapping | `docs/theming.md` |
| `wlvector.pas` | Red Strings / connectors as SVG / VML / ASCII per browser | `docs/theming.md` |
| `wlenhanc.pas` | progressive enhancement — MultiDrag/touch hooks + script include | `docs/enhance.md` |
| `wlmove.pas` | combined no-JS arrows move component + `/board/move` apply | `docs/move.md` |
| `wlstatic.pas` | serve `public/` + `i18n/` (robots.txt, css, js, translations) embedded-or-from-disk | `docs/static.md` |
| `wlapi.pas` | REST API subset (Bearer auth) so WeKan's `api.py` works | `docs/api.md` |

The reference units, `wlhttp.lpr`, and the `*.sql` schemas live in `src/`. Build helpers:
`releases/genasset.py` (embed `public/` + `i18n/` into the binary), `releases/convlang.py`
(regenerate `i18n/langs.jsn` from WeKan's `imports/i18n/languages.js`).

> These are *skeletons* — faithful to the prototypes' style (`{$mode objfpc}{$H+}`,
> `{$CODEPAGE UTF8}`, `TRequest`/`TResponse`, `HTTPRouter.RegisterRoute`) and meant as the
> starting point. The unit set is now self-contained (no dangling `uses`), but it is not yet
> a finished server: passwords are still placeholder — real hashing into
> `users.services_json` is required before use — and the linked-SQLite path in `wldb.pas`
> needs the FPC `sqlite3` binding + vendored amalgamation present to compile (the
> `-dWLDB_CLI` path only needs a `sqlite3` binary).

## Build
```bash
fpc -O3 -Xs -o welite src/wlhttp.lpr            # release, linked SQLite (single binary)
fpc -dWLDB_CLI -o welite src/wlhttp.lpr         # bootstrap: external sqlite3 CLI
fpc -Pm68k -Tamiga -o welite src/wlhttp.lpr     # classic Amiga 68k
```
Run plaintext HTTP; terminate TLS at a proxy or load AmiSSL/OpenSSL dynamically
(`docs/webstack.md` Decision 5). Default port 5500, override with `PORT`.

## Implementation checklist

Complete these steps sequentially, with regression tests and a local commit for each.
The design above remains the acceptance criteria; a checked item means verified code,
not merely a design document. Platform/browser claims require testing on those targets.

- [x] Audit the current implementation and record the remaining work (2026-11-16).
- [x] Move lists up/down across swimlanes, preserving their cards and board boundaries.
- [x] Enforce tenant-local administrator permissions on every Designer endpoint.
- [x] Separate reserved-host Global Admin domain management from tenant administrators.
- [x] Finish Designer page listing, creation, editing, disabling and deletion.
- [x] Finish Designer widget add/edit/delete, options and bounded layout controls.
- [x] Honor widget row/column spans and required inputs in published pages; add cell sort arrows.
- [x] Make Designer imports validate atomically against the same page/widget rules.
- [x] Report CLI SQLite failures and preserve UTF-8 text, delimiters, quotes and line endings.
- [x] Render authorized board/list/swimlane/card data with the shared selection form.
- [x] Implement selected-item Edit/Save, confirmed Delete, Clear and Export actions.
- [x] Implement deep selected-item Clone with remapped child IDs and attachment copies.
- [x] Add shared board read/write checks, validate move selections and safe return URLs.
- [x] Validate API child routes against their board/parent chain and block unrestricted assignment roles.
- [x] Validate API body label/member/assignee/author IDs before atomic writes.
- [x] Enforce disabled-account denial/revocation, session identity/credential binding, idle expiry and atomic action counters.
- [x] Use cryptographic token hashes/MACs, durable API credential/tenant binding and trusted-proxy client-IP handling.
- [x] Remove weak entropy fallback; verify native Linux and portable one-use SQLite stocks (both backends).
  Windows APIs and retro hardware remain part of the cross-platform verification below.
- [x] Add the board minimap, coordinates and occupied/current-position indicators.
- [x] Add optional card drag/drop, checked-card groups and simultaneous pointers through the shared move endpoint.
- [x] Align tenant/file/temp paths with DOS 8.3 and Weddy files/db layout; verify strict SQLite sidecars, framework upload scratch and offline legacy migration.
- [ ] Implement and verify FerretDB SQLite interoperability from the actual storage format.
  Typed SJSON and TEXT/JSONB SQL-write kernels now pass against FerretDB source.
  Large CLI adapter scripts now use private short scratch files without argument-size limits.
  Eleven root collection views now pass live two-way Mongo-wire tests on both backends,
  including fresh collection creation, legacy TEXT/restart and preservation of typed unknown fields.
  Typed embedded-array editing now passes live object/scalar relation tests on both backends.
  Thirteen writable child views now pass live tests, including nested paths and safe reinstall.
  Declared root foreign keys and nested delete cascades now pass missing-reference/rollback tests.
  Private token tables now pass actual issuance/validation and SQL/Mongo deletion cleanup tests.
  SQL username uniqueness and ambiguous-login denial now pass concurrent-writer/Mongo-duplicate tests.
  Portable Meteor bcrypt verification/generation now passes an independent oracle, live account and HTTP tests.
  Registration, local bootstrap and CLI seeding now create shared-format Meteor bcrypt objects.
  Portable BLAKE2b and Argon2 H' now pass hashlib/Go helper oracles in normal/checked builds.
  Argon2d/i/id memory processing now passes RFC/Go vectors with explicit kernel resource limits.
  Argon2 v19 PHC parsing, configurable verification budgets and live/HTTP logins now pass on both backends.
  Legacy v16/versionless Argon2 now passes official C-reference, live database and HTTP tests.
  Optional private Argon2 secret files and secret-bound token issuance/revocation now pass C/HTTP/live tests.
  Password-only routes now enforce active-factor, required-factor and deployment LDAP policy with durable revocation.
  Portable TOTP now passes RFC/Python vectors, Meteor-window and replay-boundary tests in checked/normal builds.
  Durable OTP replay claims now pass concurrent/rollback/restart tests and shared-adapter cleanup.
  Password/OTP proofs and atomic factor-bound web/API token issuance now pass concurrency, rollback and live shared-account tests.
  Durable pre-authentication account/peer/tenant reservations now pass concurrency, rollback, bounded cleanup and shared-store tests.
  HTTP form/JSON OTP login and shared durable attempt limits now pass both-backend HTTP and no-JS/no-cookie Chromium tests.
  Limited enrollment proofs, private pending setup and atomic activation now pass concurrency, rollback and shared BSON tests.
  HTTP enrollment/confirmation, required-factor registration and shared attempt limits now pass both-backend HTTP and no-JS/no-cookie Chromium tests.
  Shared auth now binds to the users collection UUID/table, rejects stale proofs/tokens and verifies atomic recreation/legacy-upgrade cleanup.
  Owned physical model unique keys now protect direct Mongo and SQL username writes, with mixed-writer and ownership/repair tests.
  Meteor SHA256/base64 digests and typed resume-array append/remove/clear now pass TEXT/JSONB, concurrency and live BSON tests.
  Typed resume validity and Date/numeric expiry pruning now pass boundary, ambiguity, range and live BSON tests.
  Account disabling and MFA enrollment now atomically clear shared/local credentials and pending setup, with source/rollback/isolation tests.
  Targeted shared/local bearer revocation now handles observed validation failure and local expiry without revoking sibling sessions.
  Co-issued shared API bearers now commit with local/OTP state and require unambiguous current Meteor membership/expiry, with rollback and lifetime tests.
  Stored MFA/LDAP/password-login overrides now resolve before deployment defaults, with snapshot-bound proofs, registration and live precedence/revocation tests.
  Fractional day/Date expiry arithmetic now passes 89 Node.js oracle vectors in normal/checked builds; resume validation reuses the Date kernel.
  Fractional shared lifetimes now preserve exact milliseconds through snapshot-guarded password/OTP issuance and validation, with live Node.js/SQL boundary tests.
  Typed legacy raw-to-hashed resume conversion now passes concurrency, ambiguity, rollback and live BSON preservation tests without renewing timestamps.
  Durable owned bearer-digest history now follows private token inserts/updates/deletes, backfills upgrades and survives source/account revocation; ignored writes roll back.
  Existing shared hashed/legacy bearer adoption now guards source/account/settings/history snapshots and atomically preserves original expiry, metadata and conversion; live concurrency/rollback/revocation tests cover it.
  Shared expiry now has an owned durable ten-minute due checkpoint and atomic typed sweep, with live rollback, concurrency, Date/numeric/fractional cutoff and source tests.
  Registered shared stores now sweep during HTTP idle time through a separate-connection worker, with retry/failure, isolation and shutdown tests; tenant open and HTTP lifecycle hooks are wired.
  Root-based worker discovery now covers existing local/admin/enabled-domain stores before first access and refreshes registry changes, with independent shared-backup and HTTP regression tests.
  Source-bound local/shared digest links now accompany issuance/adoption, backfill older identity without guessing hashes, enrich on validated access and retain targeted revocation after local deletion.
  Shared-store sweeps now atomically retire linked hash/raw records, remove expired private credentials/orphan metadata and retain identity/history, with rollback, sibling/BSON and idle-worker tests. Legacy unknown hashes use shared expiry plus observed raw revocation without guessing.
  Shared maintenance now also removes expired private pending enrollment at equality, with rollback, unexpired retention, replay preservation and idle-worker tests.
  Normalized legacy stores now have guarded, atomic token/optional-metadata/pending expiry and idle-worker dispatch, with schema, clock, rollback, concurrency and replay-preservation tests on both backends.
  Remaining: broader resume-policy parity; Mongo-managed sparse/multikey account indexes, registry-cache coordination and session integration, typed custom-value and legacy
  relation conversion, existing-account/file compatibility,
  application activation, shared-file/8.3 policy and two-way HTTP workflows (docs/ferret.md).
- [ ] Complete language selection, translation rendering and RTL behavior.
- [ ] Verify responsive HTML4 colors and no-JS/no-cookie browser workflows.
- [x] Verify fresh native linked/CLI SQLite installs with HTTP and no-JS/no-cookie Chromium workflows.
- [ ] Verify embedded assets and supported cross-platform builds.
- [ ] Reconcile README/design status against completed code and document platform limits.

Already implemented before this checklist: PBKDF2 password hashing in `wlpasswd.pas`,
web/API password verification, registration, loopback tenant provisioning, REST API
subset and the initial Global Admin panel. These need regression coverage as their
related workflows are completed; they are not missing skeletons.

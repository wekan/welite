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

- The upstream REST suite and browser checks with JavaScript and cookies
  disabled are recorded in [CHANGES.md](CHANGES.md). Platform-specific
  browser acceptance remains in the implementation checklist.

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
  - [ ] Verify Windows runtime DNS validation and support other target resolvers for integration destination writes.


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

## Build

See the [standalone build and startup instructions](README.md#run-with-standalone-sqlite)
and [cross-build records](docs/cross.md). The checklist below tracks the
remaining platform and workflow verification.

## Implementation checklist

Complete these steps sequentially, with regression tests and a local commit for each.
The design above remains the acceptance criteria. Move verified items to [CHANGES.md](CHANGES.md).
Platform and browser claims require testing on those targets.

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
  Existing shared stores now activate explicitly through HTTP with WELITE_SHARED=1, canonical-file refusal guards and real Mongo/HTTP/restart/revocation tests on both backends. Admin registry remains native.
  Unix SIGTERM/SIGINT now request shutdown outside handlers; tracked sockets wake incomplete requests, HTTP threads drain before tenant handles close, and maintenance joins before signal restoration. Both backends pass idle/busy/repeated-signal/restart tests; other platform controls remain unverified.
  Existing shared custom-value UPDATE now follows stored BSON types for numbers, booleans, dates and string arrays while preserving literal text, unknown siblings and metadata. Live both-backend tests cover exact BSON, invalid-value refusal and multi-row rollback. New shared SQL inserts now use the live custom-field definition for all supported field types, including explicit BSON Date hints, missing-definition refusal and multi-row rollback. Both backends pass real Mongo/SQL tests for these insertions. The custom-value API now parses JSON scalar/string-array input and atomically updates or inserts, preserving existing embedded BSON metadata; failed storage writes roll back with an error. Native/shared HTTP tests on both backends cover repeated/empty writes, form/JSON input, typed shared values, scoped rejection, quoted response IDs and failures after mutation. Shared card GET now returns typed custom-value JSON from validated source BSON metadata, including full-range UTC Date strings, null/missing distinction and unchanged text. Normal/checked Node Date oracle tests and both-backend shared/native HTTP checks cover full-range dates, unchanged source BSON, metadata omission, controlled corrupt-source errors and native TEXT compatibility. API route identifiers now decode once before scope/authentication checks, with atomic UTF-8/percent validation, literal-plus preservation and query-isolated request state. Normal/checked tests cover every route key and native/shared HTTP checks cover Unicode/reserved IDs, malformed input and unchanged foreign-parent guards. First edits of assigned null/missing custom values now follow the live definition, matching WeKan null initialization; Date hints target existing rows and preserve source metadata. Live SQL tests cover every supported type, first-edit invalid-value refusal, legacy no-definition fallback, current-definition changes and multi-row rollback; shared HTTP tests start typed fields as null and verify both backends. Explicit type changes, normalized typed migration/validation and selection clone/export remain open.
  Custom-field definition POST now atomically writes the definition, board link and authenticated creation activity, with supported-type/name/option validation, canonical/legacy flags and correct definition-list name/type metadata. Native/shared HTTP tests cover all supported types and rollback after failure at every write stage. Broader automatic-card policies remain to reconcile with maintained source.
  Existing shared currency/template SQL columns now map to canonical nested settings paths, with live both-backend tests for two-way edits, missing-object creation, unknown BSON/dropdown preservation, incompatible-parent rollback and old-view upgrade. Legacy root properties remain intact. Full settings API mapping/validation and legacy-root normalization policy remain open alongside the definition lifecycle and migration work above.
  Unmapped settings now have a protected settings_json remainder beside the canonical currency/template columns and dropdown table. Shared scoped remainder writes preserve mapped fields and unchanged typed BSON; native fresh schemas and additive/concurrent upgrades retain existing data and reject invalid/conflicting/foreign stores. Both-backend unit/live SQL/HTTP checks cover JSON ownership, rollback, old-view upgrade and broader clone/import compatibility. Full settings API mapping/validation and legacy-root normalization remain open.
  Definition creation now maps scalar/remainder settings from JSON/form input and validates known strings, Jira IDs/enums, recursive JSON and UTF-16 length limits. Definition GET returns supported native metadata/reconstructed settings or typed shared source JSON. Normal/checked and both-backend native/shared HTTP tests cover round trips and rollback. Definition edit/delete lifecycle, full adminOnly/readOnly field-policy parity and automatic-card policies remain open.
  Native dropdown-array presence now has a constrained bit and additive concurrent-safe tenant-open upgrade; definition reads preserve omitted versus empty arrays and ordered legacy items. Normal/checked linked/CLI tests cover upgrades, final-item deletion and invalid/shared/foreign refusal, alongside existing settings/policy upgrade regressions. API dropdown creation now validates exact string item shapes and case-sensitive identities, preserves omitted/empty/ordered arrays, and atomically writes native presence/items or shared canonical BSON arrays alongside definition/board/activity. Shared bindings and typed unambiguous parent checks guard creation. Parser/kernel and native/shared HTTP tests cover JSON/form, exact item shape/order, invalid input, rollback after the second item write and checked shared binding/duplicate-parent injection refusal. Automatic-card behavior and broader lifecycle parity remain open.
  Native custom-field readOnly/adminOnly flags now have constrained boolean storage,
  additive/concurrent upgrades and definition metadata reads. Shared SQL projects
  and writes them as BSON booleans without changing unrelated source data; old
  adapters acquire the columns on reinstall. Storage regression tests cover true
  flags, defaults, invalid column/value refusal and preserved legacy relations.
  API card responses now mask unreadable custom values while retaining field IDs,
  positions and missing values; absent/wrong-board definitions are unreadable even
  to admins. Custom-value POST requires active board administration for protected
  fields and rechecks the user, board, definition, association, card and shared
  source bindings before and after mutation in one transaction. Shared checks
  validate typed source metadata and reject nonboolean grants. Both-backend native/
  shared HTTP tests cover all card responses, role/site-admin boundaries, malformed
  data and triggered authority changes with complete rollback. Normal/checked
  batching/error tests and live shared multi-batch/corrupt-metadata tests pass.
  Definition creation now accepts/validates canonical/form/lowercase permission
  flags and persists actual native/shared booleans. Board writers may create
  read-only fields; admin-only creation requires active board administration,
  including when the caller is a site admin. Transaction guards recheck authority,
  the resulting definition, exact board association and shared bindings after the
  activity, rolling back triggered revocation/repointing/malformed flag changes.
  HTTP and normal/checked regressions verify these gates and stored values.
  Selection exports now check whole-board field visibility before graph collection
  and before delivery. A narrow selection cannot bypass private values or an
  unassigned admin-only definition elsewhere; site-admin status alone does not
  bypass the gate. Nonnull orphan/wrong-board values deny even board admins,
  while null/missing orphans and readable read-only values retain export behavior.
  Captured nonnull rows are also checked, including values cleared after collection.
  Native/shared HTML HTTP and checked/normal tests cover board scope, role gates,
  null/read-only semantics and source/query refusal. Selection export payloads now
  receive recursive checks for activity old/new/customFieldValue data, nested
  customFields arrays, integrity hashes, encoded JSON columns and typed source
  seeds where supplied. Historical visibility resolves the field and board without
  requiring a live card. Readable payloads and original BSON remain unchanged;
  unreadable/malformed data denies the export. Normal/checked tests cover 156
  payload cases per backend, and HTML tests cover history, extras and hash gates.
  Selection clones now inspect copied rows/payloads and require board-admin
  permission for nonnull hidden/read-only values, without blocking assigned nulls
  or unrelated uncopied history. Collected payload, actor/board and source-card
  guards execute before writes and again before commit; destination-card guards
  inspect actual nonnull values, including trigger-injected protected values.
  Native/shared HTML tests on both backends verify role/flag revocation, source
  preservation and transaction rollback; native attachment cleanup remains covered.
  Normal/checked helper tests exercise correlated guards and collected SQL checks.
  Shared clones now capture typed seeds for root records in the same SQL read
  snapshot as projected columns, validating/pinning owned descriptor, version and
  collection bindings through commit. Managed arrays are excluded and rebuilt by
  existing relation remapping. Unknown root BSON subtrees retain stored types,
  bits and order, including Date/Long/Binary/ObjectId/Timestamp/Regex and special
  doubles. Plain JSON inspection accepts unsigned timestamps without BSON-width
  inference and preserves literal metadata-like source keys. Typed seed identifiers
  retain their schema identity, and API/clone checks reject nonstring card-field
  identifier lookalikes. Selection collection
  fails closed on source/query/ownership errors. Checked/normal tests and live
  shared BSON comparisons cover these paths and binding-change rollback.
  Shared selection exports now audit complete typed root source captured beside
  projected columns, including boards, selected definitions and activities.
  Nonstring BSON field/board identifiers cannot inherit authority from SQL string
  renderings, while literal Regex markers and metadata-like keys retain their
  identity. Private audit data never enters downloads; root bindings are rechecked
  before delivery. Live both-backend tests verify identity gates, unchanged output
  shape/source BSON and missing-ownership refusal.
  Shared card clones now capture complete typed sources privately and audit
  relation extras before file preparation. A final guarded typed copy preserves
  members/assignees/labels/custom values/dependencies with their BSON schemas,
  metadata, order and missing/null/empty states. Stored custom values do not get
  coerced through today's definition. Selected dependency targets are remapped;
  external targets and opaque nested data stay intact. Canonical key/binding and
  duplicate checks plus source/destination guards surround the copy. Normal/checked
  and live both-backend tests cover these paths, hidden relation metadata and
  complete rollback after malformed keys or protected trigger writes.
  Shared root clones now use explicit partial patches through existing root views,
  changing only intended IDs/titles/timestamps/order/counters and canonical string
  references. Untouched mapped fields preserve BSON type/bits, nulls and absence,
  including missing required source fields and nested parent state. Normal inserts
  retain their defaults and reference/unique checks still apply. Clone identities
  and envelopes are validated; shared descendant traversal excludes nonstring
  parent lookalikes and ID-query failures deny collection. Normal/checked tests,
  real TEXT/JSONB SQL tests and live all-seven-root clones on both backends cover
  nested settings, source preservation, remapping and attachment bytes.
  Shared declared root references now check BSON string identity on both the
  reference and matching parent ID; plain ObjectId/Regex renderings cannot grant
  a relationship. Explicit reference writes repair same-text legacy metadata to
  strings, while null/missing references stay optional. Cascades retain nonstring
  lookalikes and validate actual owner/child types. Complete physical mapping and
  deferred custom-trigger restoration preserve delete order on reinstall.
  Normal/checked mixed TEXT/JSONB SQL tests and live both-backend Mongo/SQL tests
  verify identity, explicit repairs, unchanged unsupported data and atomic cascades.
  Root selection scopes now validate canonical board/explicit root identities and
  exact case, rejecting mixed invalid edit/save roots before rendering or mutation.
  Owned cached predicates check BSON string board/lane/list/card/checklist links,
  nested attachments and history with independent OR branches. Optional board IDs
  on card/checklist-owned rows remain optional. Descriptor/mapping/version/settings
  and view SQL are pinned into query and clone/export guards; ambiguous identities
  and projection mismatches cannot borrow authority. Normal/checked linked/CLI
  tests verify indexed probes and stale metadata; live tests cover lookalikes,
  mixed admission, case-distinct IDs, preserved source BSON and attachment bytes.
  Clone/export relation scopes now check canonical owned parents and embedded
  string keys for labels, members/assignees, custom values/dependencies and field
  board/dropdown links. Duplicate/mixed-type shadows deny collection; missing/null
  dependency types keep their declared defaults. Descriptor shape, parent mapping,
  model/version/settings and view SQL are pinned into private guards even for
  empty sets; card relation queries also recheck canonical board ownership.
  Numeric SQL root ID/link projections cannot inherit BSON string authority.
  Normal/checked linked/CLI tests cover 282 TEXT/JSONB relation cases, indexed
  probes and 44 root cases; live tests verify source/clone BSON, defaults,
  duplicate refusal, relation epoch rollback and ordinary root-edit compatibility.
  Clone/export graph collection now runs in one pinned read-only transaction,
  including resolution, descriptors, projected rows and typed source/audit data.
  Cached-handle gates prevent another request from sharing that snapshot; the CLI
  uses a private persistent reader with bounded CSV frames and one secure nonce
  per snapshot, preserving plain SQLite and portable entropy-stock support.
  Normal/checked tests verify concurrent WAL data/schema writes, readonly/control
  guards, thread gating, failure/reuse and cleanup. A live writer between board/
  card reads proves export/clone use one version while retaining the live update.
  Reads end before file preparation, current permission checks and clone writes.
  Next: remaining legacy relation forms, noncopy relation surfaces, file-byte
  stability and authorization/later mutation lifecycle consistency, metadata-aware
  identifiers for other payloads, import permissions, generic HTML
  data/query surfaces and other value-bearing paths. Automatic-card behavior
  and full field-policy parity remain open.
  Board export value authorization now uses one correlated statement with a
  reused owned policy; both card and field identities remain checked. Normal/
  checked linked/CLI tests cover later-card orphans, nulls and other-board
  isolation; a process-count regression proves 130 values add no per-value CLI
  subprocesses. Complete shared card-source validation now also uses one batch
  with owned-table rechecks and exact per-card source cardinality; full typed
  documents are checked even for absent/null values. Normal/checked TEXT/JSONB
  linked/CLI tests cover corrupt/missing/duplicate sources, malformed rows and
  native fallback; 70 additional cards add no per-card CLI subprocesses.
  Before embedded-relation checks, expanded CLI scope exports measured about
  2.5–2.9 seconds locally after batching (earlier about 13 seconds); linked was
  about 0.07–0.08 seconds. Large embedded-array matching still needs profiling.
  Board definition validation is now batched on both backends, with complete
  shared BSON/cardinality/ownership checks and reused native settings validation.
  Administration is checked once if any definition requires it. Stored Date/NaN
  flags cannot become harmless JSON null; malformed native flags also deny.
  Normal/checked TEXT/JSONB/native regressions and process counts verify that
  adding 130 definitions adds no per-definition CLI database subprocesses.
  Card/definition validators now consume one row at a time in the same SQL
  statement, without buffering the whole source batch. Both backends validate
  over 128 MiB of card sources/native settings under a 96 MiB Linux address-space
  cap; late corruption still denies. Normal/checked linked/CLI tests cover CSV
  chunk/UTF-8 boundaries, partial/failed queries, handler errors, pipe pressure
  and scratch cleanup; process counts remain independent of card/definition count.
  Remaining resource work includes SQLite work sets and collected selection/export
  graphs; collection now has a read snapshot, while later lifecycle consistency
  remains open. The heavy
  fixture retains its targeted 30-second timeout; ordinary timeouts keep defaults.
  Remaining: resume-policy parity, Mongo-managed sparse and nested multikey account
  index parity, existing-account migration, typed custom values and legacy
  relations, file-store compatibility, portable 8.3 verification, and full
  Meteor application workflows. See [the remaining interoperability work](docs/ferret.md#verified-workflows-and-remaining-interoperability-work).
- [ ] Complete language selection, translation rendering and RTL behavior.
  Catalog generation, locale negotiation and regional translation fallback are recorded in [CHANGES.md](CHANGES.md).
  Sign-in/registration labels and common validation, plus enrollment credential/code/confirmation labels, are translated. Native-name GET pickers and validated locale survive registration/setup/retry/completion/session redirects and board/Admin/Designer navigation without cookies or JavaScript. Home board/empty-state, account/admin and authentication-link captions now reuse existing native strings under the resolved viewer locale; all installed guest/member views and profile/query/header/role/private-board isolation pass linked/CLI HTTP checks, with no-JS/no-cookie Chromium navigation and OTP/enrollment regressions. Published widgets now receive the resolved frame locale through transient session context, keeping header/profile/query-driven captions, links and signed hidden language consistent without changing preferences or saved page direction. Linked/CLI HTTP and no-JS/no-cookie Chromium verify guest/member/admin/private-board isolation. Board titles/overview links, empty lane/list/card states and direct/published not-found text now use existing native keys with resolved viewer language, all-installed-caption tests and linked/CLI HTTP/Chromium privacy/navigation checks. Native movement inputs now use stable submit names and language-neutral ASCII arrows; linked/CLI parser, HTTP and no-JS/no-cookie browser checks cover physical RTL moves, legacy drag/actions and ambiguous-command refusal without mutation/proof consumption. Viewport captions, minimap descriptions and legend now reuse native keys with isolated physical arrows; all installed captions and Finnish/Arabic/Hebrew browser navigation pass linked/CLI checks. Selection toolbar actions and count labels now reuse existing native keys through resolved locale context and caption-independent submit names. Linked/CLI parser, all-installed guest/admin HTTP and no-JS/no-cookie Chromium checks cover native dispatch/export, foreign-selection refusal and ambiguous-command rejection without mutation/proof consumption. Selection edit headings, item kinds, field labels and native Save now use resolved locale, associated labels and caption-independent commands; installed-locale HTTP and no-JS/no-cookie Chromium cover Unicode/punctuation field identity, preserved user content, invalid-save rollback and locale round trips on both backends. Deletion confirmation now uses native headings, Confirm/Cancel controls and selected/affected-data counts, including card cascades and same-board inbound dependencies while retaining shared definitions. Installed-locale HTTP and linked/CLI no-JS/no-cookie Chromium verify previews/cancel preserve item rows/bytes, native confirmed deletion matches counts and consumed proofs cannot target an intact sibling. Localized Designer page-list, page settings, widget controls and sorting, import/export controls and attachment form validation checks are recorded in CHANGES.md. Designer missing-page errors use the viewer catalog. Other validation/error prose, longer instructions and many application labels/messages still need translation. See CHANGES.md for the Finnish and Arabic enrollment password instructions.
  Shared viewer frames cover normal pages, authenticated Designer/selection errors, administrator denial, unknown-domain UI and board/route 404s, early board-move errors and authentication/enrollment admission failures. Negative tests verify status, profile isolation, no private disclosure, retained Retry-After/no-store/no-referrer and unchanged rejected data; Admin domain/account validation and storage errors also retain metadata with forced registry/account rollback checks; early Designer import/export errors now also use the shared HTML frame without attachment headers, while successful JSON/ZIP downloads retain their formats.
  Direct boards mirror columns/minimap once, preserve physical keypad/viewport/card/list movement and retain locale. Designer spanning grids honor fixed/automatic direction and doctypes; widget arrows use physical semantics and isolated glyph direction. Published board widgets validate page role/enabled state/binding before saved-direction moves and return to their origin. Data-table columns, search toolbar and pagination mirror structurally while preserving field/edit/query state. Linked/CLI HTTP and no-JS/no-cookie Chromium cover these behaviors, including an ignored-table-direction simulation; actual retro acceptance is unverified.
  Offline token repair preserves surrounding human prose and records exact argument inventories. Three contextual French field/search-code repairs now complete all baseline French argument inventories without replacing surrounding prose. Three Traditional Chinese attachment activity values now restore canonical arguments and replace an English swimlane fragment using existing native vocabulary. Bulgarian Serbian-seed and Acehnese Malay/Indonesian-seed corrections have vocabulary checks; nine Acehnese compatibility phrases remain low confidence. French Belgium/Canada, Colombian Spanish and Japanese Japan now have physical assets with maintained source strings and reviewed legacy phrases; existing Khmer/Russian/Portugal mappings retain local text. Bosnian now has a physical asset with maintained vocabulary, direct compatibility phrases and a native byte-unit label.
  Corrected 117 entries containing Persian-specific letters and 80 more
  found by comparing Persian vocabulary and catalogs. All replacements use
  current WeKan Arabic translations and retain English placeholders.
  Restored numbered protected markers in 515 entries across eight catalogs without replacing the surrounding prose.
  The installed catalogs pass the placeholder and protected-marker audit. HTML card and attachment 404 pages now render the viewer’s locale and direction.
  Remaining: review other wrong/mixed-language data and untranslated entries beyond the Arabic batch recorded in CHANGES.md, translate remaining pages/errors and extend enrollment translations beyond Finnish, Arabic, German, French, Spanish, Italian, Swedish, Dutch, Polish, Czech, Slovak, Hungarian, Romanian, Danish, Portuguese, Greek, Turkish, Indonesian, Vietnamese, Ukrainian, Japanese, Korean, Russian, Hebrew, Persian, Thai, Hindi, Bengali, Tamil, Norwegian Bokmål, Icelandic, Bulgarian, Croatian, Slovenian, Catalan, Basque, Galician, Latvian, Lithuanian, Esperanto, Afrikaans, Swahili, Malay, Welsh, Irish, Scottish Gaelic, Maltese, Albanian, Serbian, Macedonian, Georgian and Armenian, verify other error-route coverage and audit remaining physical RTL controls with responsive/retro acceptance.
- [ ] Verify responsive HTML4 colors and workflows on retro browser targets.
  Published Designer pages now honor saved HTML4 versus HTML3.2 doctypes, with both-backend round trips, invalid-input refusal and Chromium standards-mode checks. Linux Dillo 3.0.5 at 640×480 and 320×480 passed minimap color and viewport navigation. Linux Dillo and NetSurf sign-in, board navigation, and attachment navigation results are recorded in CHANGES.md. Other retro targets and workflows still need responsive and color acceptance.
- [ ] Verify embedded assets and supported cross-platform builds.
  The 245-language bundle cross-build checks passed and are recorded in CHANGES.md. The m68k build menu collects the external resource alongside its executable, with lookup verified under vamos.
  Embedded generation skips dangling/non-file aliases, with native exact UTF-8/binary/valid-alias lookup, all installed locale files and full resource compilation. Private tenant/Designer SQL resources now enable fresh admin/tenant/Designer initialization from a copied executable without source/asset/schema directories on linked/CLI backends. UTF-8/BOM/override/refusal boundaries, SQL-only bundles, exact HTTP catalog/locale bytes, non-public SQL and clean shutdown are verified. Current disk and full embedded CLI servers now cross-link as verified Linux x86-64 ELF on the aarch64 SDK host; `tests/cross64.py` reproduces both builds with an isolated compiler/binutils/libc sysroot. The copied-executable embedded CLI HTTP suite also passes under amd64 QEMU with target libc/libgcc, including registration/Designer/locale bytes and clean shutdown; SQLite child processes use the native host CLI. The linked amd64 embedded HTTP suite also passes with target SQLite 3.46.1 under QEMU, and all four disk/embedded CLI/linked cross-builds pass. Windows x86 and amd64 disk/embedded linked/CLI builds now pass PE32/PE32+ architecture/console checks after fixing the generated Windows resource-type import; actual import-table checks confirm the linked-only SQLite DLL dependency. Linux armhf/armv7 disk/embedded CLI builds also pass with matching hard-float compiler/RTL, EABI5 headers and the correct loader. FPC still emits known soft-float metadata (issue 40374); runtime libc/libm/HTTP checks fail inside QEMU on this 16 KiB-page host (Debian 1114725), so actual ARM calling conventions/resources remain unverified. Remaining: ARM runtime/metadata acceptance, Windows runtime/DLL/entropy/shutdown acceptance, physical amd64 hardware, Amiga-family SQLite linkage or CLI process transport and runtime acceptance, AROS SDK/build acceptance on supported CPUs, upstream compiler support for AROS ARM64/m68k/PowerPC, other cross-target builds and platform-specific acceptance.

Already implemented before this checklist: PBKDF2 password hashing in `wlpasswd.pas`,
web/API password verification, registration, loopback tenant provisioning, REST API
subset and the initial Global Admin panel. These need regression coverage as their
related workflows are completed; they are not missing skeletons.

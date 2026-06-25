# ChangeLog

WeKan-Lite — the FreePascal reimplementation of WeKan: one native binary, SQLite-only, no-JS /
no-cookie capable, runs where Meteor cannot (Amiga 68k/PPC, MorphOS, AROS, Haiku, BSD, …).
Distilled from the [`wami/`](https://github.com/wekan/wami) and [`omi/`](https://github.com/wekan/omi) prototypes against the portable contract in `docs/`.

## 2026-06-25 Local tenant, registration / Global Admin, Admin Panel, build layout

First-run usability: browsing `http://localhost:5500/` used to answer `404 Unknown domain`
because `localhost` matched no registered domain. Added a built-in tenant, an account/registration
flow, a Global Admin Panel, and reorganized the build output. Verified on FreePascal 3.2.3 (aarch64).

- **Built-in `local` tenant** (`wltenant`): loopback hosts (`localhost`, `127.0.0.1`, `::1`) now
  resolve to a `local` tenant stored at `data/local/` (`db/data.db`, `files/attachments`,
  `files/avatars`), auto-provisioned on first request from `src/schema.sql` (override with
  `WELITE_SCHEMA`). The reserved `admin` registry dir is also created up front so a fresh checkout
  just works; unknown domains still 404 with no fallback.
- **Registration + first-user Global Admin** (`wlhttp.lpr`): `GET /` redirects to `/sign-in` when
  the tenant has no users; new `/register` page (no-JS/no-cookie) creates an account, the **first**
  account in a tenant becomes the Global Admin (`users.isAdmin=1`) and the rest are Normal users.
  Sign-in/home pages cross-link to register; passwords hashed via the existing PBKDF2 path.
- **Global Admin Panel** (new `wladmin` unit): gated to `users.isAdmin=1` (404/redirect/403 as
  appropriate) with three sections — **Domains** (registry add / enable / disable, via new
  `wlregist.RegistryListDomains`), **Designer** (links to the existing `/designer`), and **People**
  (promote/demote Global Admin, enable/disable login; cannot self-demote or self-lock-out). Same
  action-token + PRG contract as the rest of the app.
- **Build output layout** (`build.sh`/`build.bat`/`build.ami`): each target now builds into
  `build/arch/<code>/` (executable + `.o`/`.ppu`/link intermediates via `fpc -FU -FE`), then copies
  the executable to `build/bin/w<code>.exe` — a `w` prefix plus a ≤7-char platform code
  (`wlinx64.exe`, `wdos.exe`, `wami68k.exe`, …) so every path component stays ≤8 chars and the
  binaries are unique in one directory. "Build current platform" → `build/bin/wcurrent.exe`.
- **`CLAUDE.md`**: documents the DOS 8.3 filename rule (≤8-char names, ≤3-char extensions, safe
  charset, tooling exceptions) with an audit snippet, plus the build-output layout. Audited the
  tracked tree: zero 8.3 violations outside host tooling (`.gitignore`, `.tx/`).

## 2026-06-25 WeKan-Lite — `welite` rename, DOS 8.3 names, build scripts

Renamed the repo/binary to `welite` and made the whole tree DOS 8.3-safe (≤8-char names,
≤3-char extensions, one dot) so the sources copy onto a FAT filesystem and compile there.

- Added cross-platform build scripts at the repo root — `build.sh` (bash), `build.bat`
  (cmd.exe), `build.ami` (AmigaDOS) — each a 4-item menu (current platform / all / select /
  quit) that builds `src/wlhttp.lpr` with FreePascal for Linux amd64/arm64/armhf/armv7/s390x/
  ppc/ppc64le, macOS arm64, Windows x86/amd64, DOS (go32v2), Haiku, Amiga m68k, AmigaOS 4.1 PPC,
  MorphOS, and AROS x86/amd64/arm64/m68k/ppc. Output to `build/` (gitignored).
- Rebrand `wekanlite` → `welite`: binary name (also fixes its own 8.3 overflow, 9→6 chars),
  env vars `WEKANLITE_*` → `WELITE_*`, repo URL, `.gitignore`, and the designer export JSON keys
  (`welite_page` / `welite_pages`). The human product name **WeKan-Lite** is unchanged.
- 8.3 source renames (FPC unit name = filename): `wlbrowser`→`wlbrowse`, `wldesigner`→`wldesign`,
  `wlenhance`→`wlenhanc`, `wlpassword`→`wlpasswd`, `wlregistry`→`wlregist`,
  `designer-schema.sql`→`designer.sql`; designer export ext `.wlpage`→`.wlp`, zip index
  `manifest.json`→`manifest.jsn`; the glue script `wl-multidrag.js`→`wlmdrag.js`.
- 8.3 docs: `architecture`→`arch`, `sqlite-access-decision`→`sqlite`, `move-component`→`move`,
  `progressive-enhancement`→`enhance`, `static-assets`→`static`, `schema-decision`→`schema`,
  `web-stack-decision`→`webstack`; `CHANGELOG.md`→`CHANGES.md`; dirs `docs/multidrag`→`docs/mdrag`,
  `docs/roundcard`→`docs/round` (`.html`→`.htm`, `round-blue.gif`→`rndblue.gif`).
- 8.3 helper scripts: `genassets.py`→`genasset.py`, `convert-languages.py`→`convlang.py`,
  `changelog.sh`→`chglog.sh`, `releases/translations/`→`releases/xlate/`
  (`push-translation.sh`→`txpush.sh`, etc.).
- 8.3 translations: `i18n/languages.json`→`i18n/langs.jsn`; all 154 `i18n/data/<tag>.i18n.json`
  → `<tag>.jsn` (`ca@valencia`→`cavalenc.jsn`); updated the import index, `.tx/config`, and the
  `.jsn` MIME mapping in `wlstatic`.
- 8.3 static assets: `public/windows11/`→`public/win11/` (tiles renumbered `w001..w080`),
  `public/font/notification/`→`.../notif/`, `wekan.html`→`wekan.htm`,
  `interact-bottom.js`→`interbot.js`, `site.webmanifest.default`→`manifest.def`, and ~120
  favicon/PWA icons given short names; `manifest.def` (the PWA manifest) rewritten to match.
- Verified on FreePascal 3.2.3 (aarch64): builds clean, repo-wide 8.3 check passes, and the
  server serves the renamed URLs (`/i18n/langs.jsn`, `/i18n/data/en.jsn`, `/win11/w001.png`,
  `/js/interbot.js`, `/manifest.def`). DOS cross-compile additionally needs the FPC i386/go32v2
  cross build installed.

## 2026-06-25 WeKan-Lite — minimal `welite` repo

Split WeKan-Lite into its own minimal repo, https://github.com/wekan/welite (only the
required files), out of the old `wami2` tree where it lived under `freepascal/`.

- Moved the `freepascal/` contents to the repo root: FreePascal units, `wlhttp.lpr`, and the
  `*.sql` schemas now live in `src/`; design docs in `docs/`; static assets in `public/`.
- Split translations into their own tree: `public/i18n/` → `i18n/data/`, and
  `public/langs.jsn` → `i18n/langs.jsn`. `wlstatic` now serves `i18n/` as a second
  static root mounted at `/i18n` (`StaticAddRoot`), and `releases/genasset.py` embeds both the
  `public/` and `i18n/` trees, so translation URLs stay stable in disk and single-binary builds.
- Moved the build/release helper scripts under `releases/`: `genasset.py` (embed
  `public/` + `i18n/`) and `convlang.py` (regenerate `i18n/langs.jsn` from the
  sibling `../wekan` repo's `imports/i18n/languages.js`).
- Updated every cross-reference path to the new layout: `README.md`, `docs/*.md`, the FPC unit
  comments, `.tx/config` (`i18n/data/<lang>.jsn`), and the helper scripts' defaults.
- Refreshed `.gitignore` for the new binary name (`/welite`), the runtime `/data/` tree, and
  the generated embed artifacts (`src/wlassets.pas`, `src/wlpublic.{rc,res}`, `*.o` / `*.ppu`).
- Verified on FreePascal 3.2.3 (aarch64): the tree builds, and the server serves both roots —
  `/robots.txt` (public) and `/i18n/langs.jsn` + `/i18n/data/en.jsn` (translations).

## 2026-06-25 WeKan-Lite FreePascal — v0.1

First skeleton of the FreePascal backend. Compiles and links on FreePascal 3.2.3 (aarch64),
both the linked-SQLite and `-dWLDB_CLI` backends; the server runs, resolves tenants by Host,
and renders a board page from SQLite.

### Updates

- Reorganized the tree: design docs live in `freepascal/docs/`, the FreePascal code and
  `schema.sql` / `designer.sql` / `README.md` at `freepascal/`, and the [`wami/`](https://github.com/wekan/wami), [`omi/`](https://github.com/wekan/omi),
  [`tcl-tk-kanban/`](https://github.com/wekan/tcl-tk-kanban), [`minio-metadata/`](https://github.com/wekan/minio-metadata) prototypes alongside them.
- Updated every cross-reference path to match the new layout — `README.md` (docs → `docs/`,
  prototypes → siblings), `docs/*.md` (co-located docs lose `../`, prototypes/`schema.sql`
  keep `../`), and code comments (prototypes → siblings, design docs → `docs/`).
- Verified the whole unit set still builds on FreePascal 3.2.3 after the move.
- Documented SQLite on Amiga/retro targets (`docs/sqlite.md`): FreePascal
  bundles no SQLite (its `sqlite3` unit is only bindings); Amiga/MorphOS/AROS have none, so
  statically link the official amalgamation (no Aminet port needed), with retro build notes.

### Features

- Architecture & stack (`wlhttp.lpr`, `docs/arch.md`): `fphttpapp` + `httproute`
  (RTL-only, no C deps), tenant → auth → endpoint request lifecycle, HTML 3.2 baseline +
  HTML 4 enhancement tiers.
- Multitenancy (`wltenant.pas`, `wlregist.pas`, `docs/goals.md`): one binary serves many
  domains; `Host:` → `data/domains/<domain>/db/data.db` (unknown host → 404, no fallback);
  reserved `data/admin/` Global Admin tenant + per-domain Domain Global Admin; central TLS
  certs in `data/certs/<host>/`; per-operation scratch in `data/temp/YYYY-MM-DD_MM-SS_COUNTER/`.
- Authentication (`wlauth.pas`): no-cookie / no-JS sessions (session id in URL + hidden fields)
  with replay- and context-bound per-action tokens and idle timeout, persisted to
  `schema.sql` `login_tokens`.
- Database (`wldb.pas`, `docs/sqlite.md`): SQLite behind one interface — linked
  SQLite (default single binary) or the external `sqlite3` CLI (`-dWLDB_CLI` bootstrap).
- Schema & import (`schema.sql`, `docs/schema.md`): canonical 24-table schema;
  Kanboard SQLite (incl. BigBoard) and Meteor WeKan Mongo data imported into it.
- Designer (`wldesign.pas`, `designer.sql`, `docs/designer.md`): data-driven pages
  (page + widgets) with a no-JS/no-cookie form editor, custom URLs, seeded editable built-ins,
  LTR/RTL mirrored from one definition, and import/export (`.wlp` JSON, all pages as `.zip`).
- Table component (`wldesign.pas`): reusable no-JS data table — search, "Page n / m"
  pagination, column-visibility chooser, click-a-cell-to-edit — all stateless in the URL.
- Colors & theming (`wlcolors.pas`, `docs/theming.md`): WeKan named colors or any hex on any
  element; selectable picker components (hex / named / swatches / native wheel / web-safe grid);
  imported Trello/Kanboard palettes mapped to WeKan colors.
- Vector graphics (`wlvector.pas`): Red Strings render as SVG (modern/NetSurf), VML (old IE),
  or ASCII arrows (IBrowse/Dillo/Lynx).
- Progressive enhancement (`wlenhanc.pas`, `docs/enhance.md`): no-JS form
  baseline always works; MultiDrag (from [`wami/public/multidrag`](https://github.com/wekan/wami/tree/main/public/multidrag)) auto-activates with JS+touch
  to drag many cards at once on a big touch screen, driving the same endpoints.
- Combined move component (`wlmove.pas`, `docs/move.md`): one no-JS arrows keypad
  (▲◀▼▶) moves all selected swimlanes/lists/cards via `POST /board/move` (reorder/relocate over
  `sort` / `listId` / `swimlaneId`), modeled on the combined [`tcl-tk-kanban/kanban.go`](https://github.com/wekan/tcl-tk-kanban/blob/main/kanban.go).
- Static assets (`wlstatic.pas`, `docs/static.md`): serve `public/` at a configurable URL
  (default '/'), plus the `i18n/` translations tree at `/i18n` (`i18n/langs.jsn` +
  `i18n/data/`); embedded in the binary (`-dWLEMBED`, FPC resources via `releases/genasset.py`)
  or from disk; `releases/convlang.py` regenerates `i18n/langs.jsn`.
- REST API (`wlapi.pas`, `docs/api.md`): subset of `public/api/wekan.yml` with Bearer-token auth
  (`POST /users/login` + `Authorization: Bearer`), so WeKan's Python CLI `api.py` works unchanged
  — verified login → board/swimlanes/lists → createlist → addcard → cardsbyswimlane on FPC 3.2.3.
- REST API — card editing & counts (`wlapi.pas`): `PUT .../cards/:cardId`
  (title/description/color, and `labelIds` → `card_labels`), `GET .../lists/:listId/cards`, and
  `.../cards_count` / board `.../cards_count`. Verified via api.py `editcard` / `editcardcolor`
  / `get_list_cards_count` / `get_board_cards_count`.
- REST API — board title & copy (`wlapi.pas`): `PUT .../boards/:boardId/title`;
  `POST .../boards/:boardId/copy` structural deep copy (board + members + swimlanes + lists +
  cards, ids remapped). Verified via api.py `editboardtitle` / `copyboard`.
- REST API — board labels (`wlapi.pas`): `PUT .../boards/:boardId/labels` creates a label
  (nested `{label:{color,name}}` body) → `board_labels`; adding a label to a card already works
  via the card `PUT labelIds`. Verified via api.py `createlabel`.
- REST API — checklists (`wlapi.pas`): `GET`/`POST .../cards/:cardId/checklists`,
  `GET .../checklists/:checklistId` (with items), `POST .../checklists/:checklistId/items`.
  Verified via api.py `addchecklist` (title + items) and `checklistid`.
- REST API — card comments (`wlapi.pas`): `GET`/`POST .../cards/:cardId/comments`,
  `GET`/`DELETE .../comments/:commentId` → `card_comments`. Verified: post comment → `{_id}`,
  list returns it.
- REST API — create swimlane + delete operations (`wlapi.pas`): `POST .../swimlanes`, and
  `DELETE` board / swimlane / list / card. Children cascade via FK (board→swimlanes/lists/cards
  →card children; list/swimlane remove their cards first). Verified: delete card removed its
  comment, delete board removed its lists+cards.
- REST API — card members & assignees (`wlapi.pas`): `POST`/`DELETE .../cards/:cardId/members/:member`
  and `.../assignees/:assignee` → `card_members` / `card_assignees`; the card JSON now includes
  `members` and `assignees`. Verified: add/remove reflected in the returned card.
- REST API — custom fields (`wlapi.pas`): `GET`/`POST .../boards/:boardId/custom-fields`,
  `GET .../custom-fields/:customField`, and `POST .../cards/:cardId/customFields/:customField`
  (set card value → `card_custom_field_values`). Verified via curl: create → list → get → set
  value. (api.py's own `addcustomfieldtoboard` has a `json.loads('')` bug on empty settings.)
- REST API — card JSON now includes `customFields` (`[{_id,value}]`) alongside `labelIds`,
  `members`, `assignees`. Verified: getcard returns the set custom-field value.
- REST API — attachments (`wlapi.pas`, new `attachments` table in `schema.sql`): `POST
  /api/attachment/upload` (JSON + base64), `GET .../download/:id`, `.../info/:id`,
  `DELETE .../delete/:id`, and `GET /api/boards/:boardId/attachments`. Bytes are stored on disk
  in `data/domains/<domain>/files/attachments/<id>` (`storageBackend: filesystem`). Verified
  end-to-end via api.py: upload → info → download (base64 round-trip) → list → delete (row + file
  removed).
- REST API — list card attachments (`wlapi.pas`): `GET /api/attachment/list/:b/:s/:l/:cardId`
  returns `{success, attachments:[{attachmentId,fileName,fileType,fileSize,…}]}`. Verified via
  api.py `listcardattachments`.
- REST API — checklist items (`wlapi.pas`): `GET`/`PUT`/`DELETE
  .../checklists/:checklistId/items/:item`; PUT toggles `isFinished` and/or edits the title.
  Verified: get (false) → toggle (true) → delete.
- REST API — card archive (`wlapi.pas`): `POST .../cards/:cardId/archive` sets `archived=1`
  (+`archivedAt`); body `isArchive=false` unarchives. Verified: archive → 1, unarchive → 0.

### Security

- Password hashing (`wlpasswd.pas`): real PBKDF2-HMAC-SHA1 (RTL-only, salt from
  `/dev/urandom`) replaces the placeholder "any non-empty password". The stored hash lives in
  `users.services_json.password`; web sign-in and API `POST /users/login` both verify it, and
  accounts without a real hash can't be logged into. Seed/set with `welite hashpw <plain>`.
  Verified: correct password → token, wrong/empty → 401.
- Authorization (`wlapi.pas` `ApiAuthBoard`): board-scoped API endpoints now require the token's
  user to be an active `board_members` row (writes blocked for `isReadOnly`); public boards are
  read-only to non-members; site admins (`users.isAdmin`) bypass; `/api/users` is admin-only,
  `/api/users/:id/boards` self-or-admin. Verified: member read private → 200, outsider → 403,
  outsider write (even public) → 403, public read → 200.

### Fixes

- `wldesign.pas`: replaced an SQL-style `--` comment inside a Pascal record (compile error
  "END expected but - found") with a `//` comment.
- `wldesign.pas` zip import: `TUnZipper.UnZipAllFiles(stream)` is not available in
  FreePascal 3.2.x — spool the uploaded archive into a per-operation `data/temp/` dir and unzip
  via `UnZipper.FileName`, removing the dir afterwards.
- `docs/contract.md`: reverted a path-rewrite false positive — the prose "([wami](https://github.com/wekan/wami)/[omi](https://github.com/wekan/omi))
  reimplementation" was turned into a `../wami/omi` path and is now restored.
- `wldb.pas`: `journal_mode` is now `DELETE` under `{$IF DEFINED(AMIGA) or MORPHOS or AROS}`
  (WAL needs shared-memory/mmap that classic Amiga filesystems lack), WAL elsewhere.
- `wlhttp.lpr`: call `Randomize` at startup — without it `NewId` (api/designer) produced the
  same id sequence on every run, so restarts collided on board/list/card ids.
- `wlhttp.lpr`: dropped `cmem` — FPC's `hmac` unit (used by password hashing) corrupts the heap
  under `cmem` ("free(): invalid pointer"); the default FPC memory manager is already
  thread-safe, so `cmem` was unnecessary.
- `wldb.pas` (CLI backend): pass `-cmd "PRAGMA foreign_keys=ON"` to `sqlite3` so `ON DELETE
  CASCADE` fires (the CLI opens each connection with foreign keys off by default).

### Known TODO (carried forward)

Board/list `dataview` renderers; `wlmdrag.js`; password hashing into
`users.services_json`; Domain-Global-Admin role checks; list↕-across-swimlanes and the
Edit/Clone/Delete/Export move actions.

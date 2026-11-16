# ChangeLog

WeKan-Lite — the FreePascal reimplementation of WeKan: one native binary, SQLite-only, no-JS /
no-cookie capable, runs where Meteor cannot (Amiga 68k/PPC, MorphOS, AROS, Haiku, BSD, …).
Distilled from the [`wami/`](https://github.com/wekan/wami) and [`omi/`](https://github.com/wekan/omi) prototypes against the portable contract in `docs/`.

## 2026-11-16 Deep selected-item cloning

- Enable Clone for selected cards, lists and swimlanes. Coalesce overlapping selections,
  copy their content/descendants, and remap list/lane/parent/checklist/comment/cover and
  internal dependency IDs while retaining shared board labels, fields and external targets.
- Append copied items deterministically, assign new card numbers, and record clone events
  under the acting user. Historical activities stay with the original entities.
- Copy filesystem attachment bytes before one database transaction; missing files,
  unsupported storage backends or SQL failures remove prepared copies and leave original
  rows/bytes unchanged. Existing filesystem targets are never deliberately overwritten.
- Initialize UTF-8 conversion explicitly: the host's unset Pascal codepage was turning
  non-ASCII JSON strings into question marks. Cloning/import regressions now pin Unicode
  fidelity, with embedded NUL text preserved through SQL hex literals when needed.
- Verified mixed/card/list/swimlane clone variants, child IDs, shared references, covers,
  original row preservation, byte copies, replay rejection and file/SQL rollback. HTTP and
  Chromium Clone workflows pass with JS/cookies disabled on both SQLite backends.

## 2026-11-16 Selected-item editing, deletion, clearing and export

- Enable selected-item Edit/Save forms for swimlane/list/card titles and colors, plus card
  descriptions. Validate the complete form before one transactional update; failed SQL
  rolls back all selected edits.
- Add explicit Delete confirmation, then remove selected containers, descendant cards,
  child records, activities and attachment metadata transactionally. Unlink filesystem
  attachment bytes only after commit, so rollback never removes live attachment content.
- Add Clear (including stale selections) and `select.jsn` export of selected entities,
  related records and base64 filesystem attachment content. Account/token data is excluded.
- Read-only downloads retain the visible form's token, allowing the next no-JS action;
  mutations still consume it. Mixed-case selection names now use the same ownership policy
  as movement, closing an authorization/selection parsing mismatch.
- Verified HTTP data/bytes, descendant cleanup, bad fields and forced edit/delete failures,
  plus Chromium Edit/Save/Export/Clear/Delete workflows with JS/cookies disabled on both
  SQLite backends. Deep Clone remains a separate unfinished TODO and stays hidden.

## 2026-11-16 Atomic, validated Designer imports

- Share page/widget validation and span rules between forms and imports. Decode and
  validate all content before replacing existing pages, then execute one transaction.
- ZIP imports validate every page, duplicate URLs, entry names and the manifest before
  committing the whole bundle. A malformed page or SQL error leaves every old page intact;
  ZIP entry streams never fall back to filesystem extraction.
- Add working no-JS upload/export forms and authenticated raw JSON imports using the
  same action token in `X-Welite-Action`, `X-Welite-Counter`, `X-Welite-Hash` headers.
- Export disabled pages too; use `page.wlp`, `pages.zip`, and numbered DOS 8.3 bundle entries.
- Verified invalid models, traversal/duplicate/manifest errors, token replay and forced SQL
  failures (including failure on the second ZIP page) without database changes. JSON/ZIP
  browser upload/download and round trips pass with JS/cookies disabled on both backends.

## 2026-11-16 Render Designer spans and cell ordering

- Render row/column spans once in published and editor grids, suppressing covered cells
  and using the same logical rectangles for LTR/RTL. Reject overlapping spans during
  widget save/move and inconsistent spans among widgets sharing an anchor cell.
- Add Sort up/down buttons that reorder widgets inside their cell transactionally,
  normalizing sort positions so tied values also have deterministic ordering.
- Emit required attributes and visible required markers for input widgets. Browsers
  without native constraint validation still show the marker; endpoints retain their
  own validation responsibilities.
- Honor explicit page direction and avoid double-mirroring in modern browsers by fixing
  the grid's physical direction while retaining per-cell text direction.
- Verified HTTP span/overlap/required/sort/direction cases and Chromium physical RTL,
  spanning cells and sort-button submissions with JS/cookies disabled on both backends.

## 2026-11-16 Separate Global Admin and domain administration

- Reserve the central domain registry for administrators authenticated in `data/admin`;
  administrators of `local` and served domains retain only their own People/Designer panels.
  Navigation and role labels now distinguish Global Admin from Domain Global Admin.
- Add local `welite initadmin <username>` bootstrap using `WELITE_ADMIN_PASSWORD`, refusing
  repeat initialization. Public registration never creates accounts in the reserved tenant.
- Provision new registered domains explicitly, applying the portable schema transactionally
  even when the registry DB already exists. Reject reserved/malformed domain names and
  match loopback hosts exactly instead of accepting attacker-controlled substrings.
- Verified local bootstrap, tenant/session separation, domain creation, disable/enable,
  malformed names and spoofed loopback hosts against both linked and CLI SQLite servers.
  Operational instructions are in `docs/admin.md`.

## 2026-11-16 Verify fresh linked and CLI server installations

- Keep SQL beginning with `--` comments from being parsed as SQLite command-line options;
  this fixes automatic schema provisioning and first registration on the CLI backend.
- Added the leading-comment regression and a `WELITE_DB_CLI=1` HTTP/browser test mode.
  The valid-card ownership assertion now follows the card's actual list after UI movement.
- Verified fresh linked and CLI installations through registration, Designer page/widget
  forms, board rendering/movement/minimap and 29 rejected API ownership attempts. Both
  Chromium runs disable JavaScript and cookies; all accumulated Pascal DB/move/role tests pass.

## 2026-11-16 Enforce API resource ownership

- Added a shared child-resource chain check after board authorization: swimlane/list/card,
  checklist/item/comment and custom-field IDs must belong to the board and parents named
  in the route, including when the caller is a site administrator.
- Validate card/attachment upload parents before writes. Board-scoped list/swimlane card
  queries, counts and deletes also constrain boardId, protecting against inconsistent
  legacy child rows.
- Verified 29 forged-resource requests across endpoint families return rejection without
  any database change, while the valid card remains readable. Added source-wide guard
  coverage so another child endpoint cannot silently omit ownership checks.
- Body label/member/assignee/author validation and disabled-login/session behavior remain
  explicit follow-up steps in TODO.

## 2026-11-16 Board minimap and coordinate navigation

- Added a top-right, server-rendered minimap with occupied/empty markers, a yellow
  current position and X/Y coordinates. Each cell is a session-preserving navigation link.
- Board pages default to one list in one swimlane for small-screen/retro use; view arrows
  change that window and View all restores the full-board selection surface.
- Clamp coordinates to existing rows/columns and preserve the viewport on form submission.
- Verified map links, occupancy changes after moves, highlight, out-of-range coordinates
  and all-items view. Chromium tests pass at widths 320/768/1920 with no horizontal
  overflow in the fixture, with JavaScript and cookies disabled. Retro devices still
  require the platform-specific checks listed in TODO.

## 2026-11-16 Authorized board views and no-JS card movement

- Added real board links on the home page and registered Designer board/board-list
  dataviews. Board pages render active swimlanes, lists and cards with escaped text.
- Full editors receive one selection form with board ID, action token, return path and
  shared arrow controls. Other viewers see board data without mutation controls.
- Scope neighbor/card-list queries to the board and swimlane, include legacy shared
  lists, and deduplicate repeated selections. RTL board pages reverse list columns.
- Verified HTTP visibility/controls and Chromium selection-to-right-arrow card movement
  with JavaScript and cookies disabled, including the resulting persisted list ID.
- Unfinished action buttons remain hidden until their handlers are implemented. Minimap,
  responsive retro color verification and optional drag/drop remain separate TODO steps.

## 2026-11-16 Shared board permissions and move selection isolation

- Added shared board read/write checks used by UI visibility, move authorization and
  API board guards. Private boards require active membership; full-board mutations
  exclude read-only, comment-only, assignment-limited and worker roles.
- Move requests require a validated session and an explicit board; every selected card,
  list and swimlane must exist, be active and belong to that board before any mutation.
- Restrict move return URLs to local paths and prevent anonymous home-page disclosure
  of private board titles. Unknown/archived boards and disabled admins cannot write.
- Verified both SQLite backends against a role/selection/redirect matrix and live API
  editor/read-only/comment-only requests. Separate API child-ID scoping remains in TODO.

## 2026-11-16 Reliable CLI SQLite results and errors

- Use FreePascal's process runner to drain stdout/stderr while SQLite runs and check
  its exit code. Syntax, constraint and foreign-key failures now return false.
- Use SQLite CSV output instead of splitting on pipes/newlines; preserve quoted commas,
  pipes, quotes, UTF-8 and embedded CRLF/LF while retaining empty/NULL text semantics.
- Verified both SQLite backends with executable Pascal text/error regressions and a
  5,000-row result larger than pipe capacity. Existing move and Designer HTTP tests pass.
- Reference: SQLite CLI output modes (`https://www.sqlite.org/cli.html`) and the
  FreePascal `TProcess`/`RunCommand` implementation in the installed FCL sources.

## 2026-11-16 Working Designer widget editor

- Added full no-JS widget forms and persisted creation, updates and deletion, with
  administrator gates, matching action tokens and session-preserving editor redirects.
- Validate widget types, JSON options, finite sort values, colors, local targets and
  row/column/span bounds; reject moving a widget between unrelated pages.
- Move controls derive the owning page from the widget and clamp to its column and row
  limits. Select widgets render escaped option labels/values and the selected value.
- Verified widget operations, negative inputs and movement bounds over HTTP and through
  Chromium with JavaScript and cookies disabled. Recorded separate remaining work for
  published spans/required inputs, cell-sort arrows, import validation and CLI DB fidelity.

## 2026-11-16 Working Designer page management

- Added page listing, creation, editing by ID (including disabled pages), enable/disable
  and deletion with cascading widget removal, using plain forms and action tokens.
- Provision Designer tables on first administrator access without replacing existing
  pages; schema statements are idempotent. `WELITE_DESIGNER` overrides `src/designer.sql`.
- Validate local URLs, reserved routes, columns, document type, direction and access role;
  reject duplicate URLs and column changes that would hide widgets. Published admin pages
  now require the actual administrator role; invalid sessions cannot retain page access.
- Verified page workflows, invalid inputs, authorization and deletion over HTTP, plus
  Chromium form create/edit/disable/enable/delete with JavaScript and cookies disabled.

## 2026-11-16 Require administrator permissions throughout Designer

- Guarded every Designer listing, editor, import and export endpoint with the shared
  tenant-local administrator gate. Mutations also require their action token.
- The gate now checks session validation's Boolean result, so revoked tokens and wrong
  client bindings cannot reuse residual session fields. Disabled users cannot administer.
- Verified all eight endpoints over HTTP with no cookies: anonymous, normal user,
  invalid session, mismatched client, administrator, missing action token, demotion,
  disabled account and revoked token cases (`tests/admin.py`).
- Recorded the remaining distinction between reserved-host Global Admin domain management
  and tenant-local administration in `TODO.md`; this step only secures Designer access.

## 2026-11-16 Move lists across swimlanes

- Implemented up/down list movement to adjacent active swimlanes on the same board,
  appending after existing lists and moving all list cards, including archived cards.
- List/card updates share one transaction in both SQLite backends. Boundary, archived,
  missing and legacy lists remain unchanged; other-board cards cannot be reparented.
- Verified executable Pascal regressions with `tests/movelist.py`, using the canonical
  schema and both linked and CLI SQLite backends, including multi-list movement.

## 2026-11-16 Implementation audit and remaining steps

- Added a sequential, testable implementation checklist to `TODO.md`, preserving the
  original design requirements and distinguishing existing code from remaining work.
- Confirmed password hashing already exists; identified unfinished board rendering,
  Designer handlers/permissions, move actions, minimap and progressive enhancement.
- Removed the duplicate repository instruction file; parent repository instructions
  apply here, while the existing build layout and DOS 8.3 rules remain documented below.

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
- **Cross-compiler installer** (`build.sh` menu option 4, Ubuntu/Debian amd64/arm64): apt can't
  provide FPC cross-compilers (none packaged, `fpc-source` is stripped of the build Makefiles,
  exotic OSes have no Ubuntu binutils), so this uses
  [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe). Preferred path: apt-install
  Lazarus (`lazbuild` + nogui LCL), build fpcupdeluxe's real headless console tool `fpclazup`
  (`LCLWidgetType=nogui`, forced to the host CPU/OS), then run it to build the FPC compiler + cross
  compiler/binutils per target — Amiga/AROS/MorphOS/Haiku/macOS as well as Linux/Windows/DOS — and
  point the session `FPC` at the result. Getting this working on Ubuntu 26.04 needed several
  pieces, all handled automatically: seed the bootstrap compiler from the system FPC; `--disablejobs`
  (the parallel RTL build races); `--fpcVersion=fixes-3.2` (FPC 3.2.2 doesn't link on glibc ≥2.34,
  which removed `__libc_csu_init/_fini`); `--only=FPC` (skip Lazarus/LCLCross); and treat "a working
  `fpc` binary exists" as success rather than fpclazup's exit code. `do_build` also exports
  `PPC_CONFIG_PATH` next to the chosen `FPC` so the fpcupdeluxe `fpc.cfg`/units are used (the static
  compiler otherwise falls back to the system `/etc/fpc.cfg`). If the build path can't be set up it
  falls back to launching the fpcupdeluxe GUI. The install dir is kept outside the repo
  (default `~/fpcupdeluxe`); fpcupdeluxe derives its basedir from the working dir and aborts if that
  is inside another git repo. Verbose log to `build/log/xtools.log`, per-target pass/fail.
- **Cross-target sweep + per-target flags**: swept all 18 cross targets (install cross FPC, then
  cross-build welite) on an aarch64 host. Working there: `x86_64-linux`, `arm-linux`, `i386-win32`,
  `x86_64-win64` (plus native `aarch64-linux`); the rest fail because fpcupdeluxe ships no
  aarch64-host cross-binutils/libs for them (they work from an x86_64 host). welite's default build
  links `libsqlite3`, which can't be cross-linked, so every non-Windows `PLATFORMS` entry now carries
  `-dWLDB_CLI` (external `sqlite3`, links nothing); Windows keeps the linked default (runtime DLL).
  armhf/armv7's hard-float flags clash with fpcupdeluxe's soft-float arm RTL ("different FPU mode").
  Each `PLATFORMS` row is annotated with its host requirement; "Build for current platform" still
  builds the native linked-SQLite default.
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

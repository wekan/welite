# WeKan-Lite — FreePascal code + design

NOTE: This WeKan-Lite version has retro-look. Modern-look original WeKan is at
https://wekan.fi and https://github.com/wekan/wekan .

Uses DOS filenames 8 characters, with extension 3 characters, like FILENAME.TXT

WeKan-Lite is a FreePascal HTTP server with an HTML board interface and a subset of the
WeKan REST API. Its architecture draws on two companion prototypes:

- [`wami/wekan.pas`](https://github.com/wekan/wami/blob/main/wekan.pas) — single-file WeKan web prototype (routing + retro HTML surface).
- [`omi/public/server.pas`](https://github.com/wekan/omi/blob/main/public/server.pas) — mature server (no-cookie/no-JS auth, SQLite-via-CLI, i18n).
- `docs/contract.md`, `src/schema.sql`, `docs/goals.md`, `docs/webstack.md`,
  `docs/schema.md` — the portable contract these target.

## Source and build conventions

Keep shipped path components DOS 8.3-safe: names of at most eight characters,
extensions of at most three, letters/digits/hyphen/underscore, and one extension dot.
Host-only VCS/editor dotfiles are exceptions. Runtime paths, strict SQLite auxiliary names and offline migration are documented in [docs/runtime.md](docs/runtime.md). Build intermediates belong under
`build/arch/<code>/` and collected binaries under `build/bin/w<code>.exe`, with platform
codes of at most seven characters. See `TODO.md` for implementation status.

The native embedded build includes public/i18n assets and private tenant/Designer
SQL defaults. Fresh initialization and HTTP workflows are verified from a copied
executable on linked/CLI SQLite without source or asset directories. Disk builds
also need the SQL files or explicit path overrides. See [embedded builds](docs/static.md#build)
and [SQL bootstrap](docs/static.md#private-bootstrap-sql); cross-target acceptance remains in TODO.

## Run with standalone SQLite

From the repository root, use Free Pascal with its FCL and SQLite units
and the system SQLite library. To use the SQLite command-line tool
instead, add `-dWLDB_CLI` and make `sqlite3` available on `PATH`.

```sh
mkdir -p build/native
fpc -O3 -Xs -FUbuild/native -FEbuild/native -owelite src/wlhttp.lpr
WELITE_SHARED=0 WELITE_DATA="$PWD/build/data" WELITE_PORT=5500 ./build/native/welite
```

Open `http://localhost:5500/`. Run the disk build from the repository root
so it can load the SQL, assets, and catalogs. Plain HTTP is the default.
The [cross-build record](docs/cross.md) gives target-specific compiler and
SQLite requirements.

## Import a board ZIP

Send the archive as the request body to `POST /api/boards/import` with
`Content-Type: application/zip` and the usual API credentials. The import
creates a new board and returns its ID in `_id`. A metadata-only archive
restores the board without its attachment files.

## PDF export fonts

Set `WELITE_PDF_TTF` to the path of a TrueType font with the glyphs needed
in your exports. WeLite embeds only the used glyphs. With no configured
font, PDF export uses the standard PDF Courier fonts and WinAnsi encoding.
The embedded font path currently handles characters in the Unicode Basic
Multilingual Plane.

## Read WeKan data folders

WeLite reads a WeKan's own folders read-only and shows them as HTML4 kanban
pages: the FerretDB SQLite database in `files/db/wekan.sqlite` and the
attachments in `files/attachments`, for Docker/bundle `WRITABLE_PATH` folders,
Snap `files` folders and Weddy's `domains/<domain>` folders. Set
`WELITE_WEKAN_ROOTS` to one or more folders separated by `;`, sign in as the
Global Admin on the reserved `admin` host and open **WeKan: Domains**. The pages
list the domains with their sizes, the boards of a domain, a board as swimlanes
by lists, a card with its checklists, comments, custom fields and attachments,
and an attachment viewer and download. Only the Global Admin sees them, because
WeKan's users and board members are not WeLite's. See [docs/wekandir.md](docs/wekandir.md).

## Verified behavior and current limits

- Native Linux linked and CLI SQLite builds run the [HTTP and Chromium suites](tests/README.md).
  Web sign-in and board navigation work with JavaScript disabled and first-party
  cookies blocked. Card titles open an HTML page with their descriptions and
  checklists, subtasks and attachment downloads. Board movement, selection actions and Designer use HTML forms.
- The [REST API](docs/api.md) supports bearer-token login and board-scoped
  custom-field operations. On Linux, all 114 upstream REST cases pass on linked
  and CLI SQLite in shared mode. The REST browser cases run without JavaScript
  or cookies. See the [upstream REST test runner](tests/README.md#run-the-upstream-wekan-rest-specs).
- The [FerretDB adapter](docs/ferret.md) opens existing shared SQLite stores and
  provisions new tenants in shared format when the SQLite backend supports it.
  Consult [TODO.md](TODO.md) for remaining interoperability gaps.
- The [cross-build record](docs/cross.md) distinguishes successful builds, emulated
  runtime checks and platform acceptance still to be tested. Chromium results
  cover Chromium. Amiga, MorphOS, and FreeDOS browser acceptance remains open.

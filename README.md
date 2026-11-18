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

## Verified behavior and current limits

- Native Linux linked and CLI SQLite builds run the [HTTP and Chromium suites](tests/README.md).
  Web sign-in and board navigation work with JavaScript disabled and first-party
  cookies blocked. Board movement, selection actions and Designer use HTML forms.
- The [REST API](docs/api.md) supports bearer-token login and board-scoped
  custom-field operations. The complete WeKan API and browser suite require
  additional compatibility work.
- The [FerretDB adapter](docs/ferret.md) opens existing shared SQLite stores and
  provisions new tenants in shared format when the SQLite backend supports it.
  Consult [TODO.md](TODO.md) for remaining interoperability gaps.
- The [cross-build record](docs/cross.md) distinguishes successful builds, emulated
  runtime checks and platform acceptance still to be tested. Chromium results
  cover Chromium. Amiga, MorphOS, and FreeDOS browser acceptance remains open.

# WeKan-Lite — FreePascal code + design

NOTE: This WeKan-Lite version has retro-look. Modern-look original WeKan is at
https://wekan.fi and https://github.com/wekan/wekan .

Uses DOS filenames 8 characters, with extension 3 characters, like FILENAME.TXT

FreePascal-specific design docs and reference code for WeKan-Lite, **distilled from the two
working prototypes in this tree** and aligned to the portable contract:

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

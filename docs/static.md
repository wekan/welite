# WeKan-Lite — static assets — v0.1

Companion to `webstack.md` (Decision 4). How the development-time files under
`public/` and `i18n/` are served, and how they get into the single binary. Code: `wlstatic.pas`;
generator `../releases/genasset.py`.

`public/` holds robots.txt, favicons/PWA icons, `css/`, `js/` (incl. the vendored
`interact.js`), `font/` arrow GIFs, and the OpenAPI `api/`. The translations live in their own
tree `i18n/` (the bulk — ~21 MB of translation JSON): `i18n/langs.jsn` (the language list)
and `i18n/data/<lang>.jsn`. Each tree is served at a configurable URL mount:

- `public/robots.txt`        → `http://<host>/robots.txt`        (public mount `/`)
- `public/js/interact.js`    → `http://<host>/js/interact.js`    (public mount `/`)
- `public/css/reset.css`     → `http://<host>/css/reset.css`     (public mount `/`)
- `i18n/langs.jsn`      → `http://<host>/i18n/langs.jsn`   (i18n mount `/i18n`)
- `i18n/data/en.jsn`   → `http://<host>/i18n/data/en.jsn` (i18n mount `/i18n`)

`langs.jsn` references each translation as `import('./data/<lang>.jsn')`, which
resolves against `/i18n/` to `/i18n/data/<lang>.jsn`.

Assets are **global** (identical for every tenant) and are served *before* tenant resolution.
`wlstatic` registers one root per tree (`StaticInit` for `public/`, `StaticAddRoot` for `i18n/`).

## Two sources, tried in order (`wlstatic.ServeStatic`)

1. **Embedded** — when built with `-dWLEMBED`, the generated `wlassets` unit reads files
   bundled into the executable as FPC resources (`{$R wlpublic.res}`) and registers
   `wlstatic.EmbeddedLookup`. True single binary; nothing on disk.
2. **Disk** — otherwise (dev, and any target without a resource compiler) read from the
   configured directory for each root (`public/`, `i18n/`) next to the binary.

Path traversal is rejected (`..`, absolute, NUL); MIME type is by extension (`MimeForName`).

### Why not embed as Pascal `const` byte arrays?
The asset trees are ~24 MB; byte-array literals would balloon the source past what FPC can
compile. FPC **resources** bundle the real bytes with no source bloat, so embedding uses those.

## Configuration

| Env var | Default | Meaning |
|---------|---------|---------|
| `WELITE_STATIC_URL` | `/` | URL mount the `public/` tree is served under |
| `WELITE_PUBLIC` | `public` | on-disk `public/` dir (disk mode only) |
| `WELITE_I18N` | `i18n` | on-disk `i18n/` translations dir (disk mode only); served at `/i18n` |

## Build

**Disk mode (default, dev, any target):** just ship the binary next to `public/` and `i18n/`.
```
fpc -O3 -Xs -o welite src/wlhttp.lpr
./welite     # serves ./public/* and ./i18n/* ; WELITE_PUBLIC / WELITE_I18N override the dirs
```

**Embedded single binary (release):** run `genasset.py` from the repo root, build in `src/`.
```
python3 releases/genasset.py                       # writes src/wlassets.pas + src/wlpublic.rc
cd src
fpcres wlpublic.rc -o wlpublic.res -of res       # compile resources (public/ + i18n/)
fpc -dWLEMBED -O3 -Xs -o ../welite wlhttp.lpr # embed + build
./../welite                   # serves from inside the exe; no public/ or i18n/ needed
```
`genasset.py` embeds the `public/` and `i18n/` trees (overridable: `genasset.py OUT_PAS OUT_RC
ROOT[:URL_PREFIX] …`). RCDATA paths are written relative to the `.rc` file's dir, so `fpcres`
runs from `src/`. Verified on FPC 3.2.3 (aarch64): with `public/` and `i18n/` deleted, the
`-dWLEMBED` binary still serves `/robots.txt`, `/js/interact.js`, and `/i18n/langs.jsn`
from the executable.

### Size note (retro targets)
Embedding `public/` + `i18n/` adds ~24 MB to the binary, most of it `i18n/`. For an Amiga 68k or
other small target, either keep disk mode (binary + `public/` + `i18n/` folders) or run
`genasset.py` against a trimmed `i18n/` (e.g. only the needed languages).

## Translations index
`i18n/langs.jsn` (the language list consumed for i18n) is generated from WeKan's
`imports/i18n/languages.js` by `../releases/convlang.py`; re-run it to pick up new
languages. It writes `i18n/langs.jsn`; the per-language data lives in `i18n/data/`.

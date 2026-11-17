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

Run `python3 releases/convlang.py [languages.js] [langs.jsn]` to regenerate the
catalogs from WeKan metadata. Without arguments the script finds the enclosing
WeKan checkout's `imports/i18n/languages.js` and writes this repository's
`i18n/langs.jsn`. It understands the current compact metadata/static-loader format
and the older literal-object format, without executing either as JavaScript.

`langs.jsn` retains the browser object with literal dynamic imports. The adjacent
`locales.jsn` is strict JSON containing `key`, `code`, `tag`, native `name`, `rtl`
and translation `file`, for server use without a JavaScript interpreter. Both
catalogs advertise only files present in the destination's `data/` directory.
Existing local asset mappings retain `cavalenc.jsn`, `km_KH.jsn` and `ru_RU.jsn`
for their corresponding source loader identities; source aliases remain
separate identities. Unsafe paths, duplicate identities, invalid metadata and a
missing English fallback are refused before writing output. Translation contents
are never modified by this command.

The current snapshot lists 148 installed languages; 97 more source languages
still need local translation assets and portable filename decisions. Missing or
broken legacy alias files are excluded rather than offered as failed imports.
Server negotiation and board/Designer direction now use the strict catalog.
Sign-in GET labels now use per-page translation readers; other pages and complete
RTL integration remain in `TODO.md`. `tests/catalog.py` verifies conversion and matching
catalog contents against the files actually installed.

### Server translation rendering

`TWLTranslator` owns only the selected language and English objects for the page
being rendered. It reads registered embedded assets before disk, with the same
16 MiB asset limit as catalog loading. Local string values win; missing, empty,
wrong-type or malformed local data falls back to English, then an explicit caller
fallback. The reader returns literal text, including underscore and percent tokens;
it does not interpret HTML or format substitutions. Renderers escape that text
for their HTML text/attribute context. Callers use the application's UTF-8 codepage.

The sign-in GET form uses the existing log-in, username, password, OTP and
create-account keys. It emits `lang`/`dir`, `Content-Language` and
`Vary: Accept-Language`, keeps language in its POST query, and works without scripts
or cookies. Failed-login messages, enrollment flows, other application surfaces and
language pickers/navigation still need localization; the checklist remains open.

The sign-in picker is a separate GET form containing only `lang` and its apply
button; native names and option values are HTML-escaped. Failed login re-renders
the translated form with no entered credential values. Successful sign-in carries
a valid explicit language in the session redirect; it does not change stored
profile preferences. Registration/enrollment now preserve validated language through their forms,
retries, completion links and session redirects; general navigation still needs
propagation. These routes emit language/direction metadata while retaining private
enrollment no-store/no-referrer controls. Only language is added to flow URLs,
with credentials and setup tokens kept in POST bodies/response forms. The generic failed-login message remains English until
remaining application messages receive translation keys.

Registration shares the per-page translation reader for title/button,
username/password/repeated-password labels, sign-in link and common validation
messages. Its own GET picker switches native language names without including
credential inputs. Failed registration renders empty inputs in the chosen locale;
failed sign-in reuses the shared invalid-credentials label. First-admin and
account-completion/policy notices and enrollment instructions remain English pending
remaining message keys; translation contents are unchanged by these renderers.

Enrollment setup and confirmation reuse the existing username/password/start,
OTP/confirm and log-in keys through their own per-request readers. Output remains
escaped and private controls/proof handling remain in the enrollment endpoints.
Long setup instructions, titles, retry explanations and completion/policy messages
still require dedicated translation keys.

### Navigation language state

A validated explicit locale travels in generated navigation URLs and action/GET
hidden fields. `TWLSession.LanguageTag` holds only request rendering context; session
serialization excludes it. Validation and action-token handling derive it from the
current query or posted field, so an earlier request cannot silently set the next
request's locale. Profile language continues to resolve at render time.

Board/minimap/view/selection, Designer/table and admin links and mutation redirects
use that context. Session/locale parameters are inserted before URL fragments;
existing locale parameters are retained, including encoded names. Dynamic IDs and
search values are URL-encoded so embedded query characters preserve data identity.
Re-login preserves a valid locale while dropping failed session identity. Language
choice does not modify stored profile preferences. Page text and direction/language
metadata outside the completed renderers remain in `TODO.md`.

### Viewer page frames

`wllocale.pas` reads only an authenticated session's profile from its bound tenant,
then resolves explicit query/posted locale, profile and standard Accept-Language.
Home, board, Admin, Designer index/editor, published and selection edit/delete frames
emit matching HTML `lang`/body direction and Content-Language/Vary headers. Saved
page direction overrides the derived direction; published page doctype is retained.
Profile data remains read-only. Authentication forms reuse the frame helper while
preserving enrollment no-store/no-referrer controls. Early error frames and physical
RTL controls remain in the outstanding UI audit.

### Translation token maintenance

`python3 releases/tokfix.py` audits existing physical locale files against
`i18n/data/en.jsn`. It proposes only a unique unmatched placeholder or uniquely
matched case differences. For the two known code-only activity title keys, it also
restores malformed/missing arguments when no prose occurs outside argument
containers. Values containing prose remain for contextual review. `--apply` writes those repairs; optionally use
`--record tests/tokdone.jsn` to retain repaired-key regression coverage. Set TMPDIR
to the parent checkout's existing `.tools/tmp` on the same filesystem. Files are
staged there before individual atomic replacements; a changed input is refused.
Repair records must stay outside the locale data directory. Symlinks are skipped.

The tool preserves prose outside token spans and every other value/key order.
HTTP(S) URL percent octets remain data; named and printf tokens preserve their
source spelling, case and format. Flat/unique/UTF-8 dictionary validation happens
before writing. Missing/repeated/malformed/ambiguous token cases remain untouched
for contextual review. The first batch fixes 233 values in 86 files, with 1,159
ambiguous differences still outstanding. Wrong/mixed-language auditing and additional
language imports are separate remaining tasks. No translation text is generated by
this repair command.

### Acehnese seed correction

The Acehnese file formerly contained Malay/Indonesian labels and sentences. It now
reuses the 2,090 matching values from WeKan's current
`imports/i18n/data/ace.i18n.json`, in WeLite English key order. Eleven legacy keys
are absent upstream: two contain code-only title templates, and nine prose phrases
were written from the existing Acehnese UI terms. Those nine compatibility phrases
are low confidence and may be refined by a native speaker. Every value preserves
the corresponding English underscore/percent token inventory.

Term references include [Daud and Durie (1999)](https://dokumen.pub/kamus-basa-aceh-kamus-bahasa-aceh-acehneseindonesianenglish-thesaurus-0858835061.html)
for `keulabee` and `ubah`, and the government-published
[Acehnese grammar](https://repositori.kemendikdasmen.go.id/29860/2/TATA%20BAHASA%20ACEH.pdf)
for `peusom`. Other technical wording follows the maintained Acehnese catalog.
Correct-language human values remain preferred in future merges. Vocabulary
regressions supplement script checks.

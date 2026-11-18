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
The asset trees are ~37 MB; byte-array literals would balloon the source past what FPC can
compile. FPC **resources** bundle the real bytes with no source bloat, so embedding uses those.

## Configuration

| Env var | Default | Meaning |
|---------|---------|---------|
| `WELITE_STATIC_URL` | `/` | URL mount the `public/` tree is served under |
| `WELITE_PUBLIC` | `public` | on-disk `public/` dir (disk mode only) |
| `WELITE_I18N` | `i18n` | on-disk `i18n/` translations dir (disk mode only); served at `/i18n` |

## Build

**Disk mode (default, dev, any target):** ship the binary, `public/`, `i18n/`,
`schema.sql` and `designer.sql`, or configure the SQL file paths. Source checkouts
use `src/schema.sql` and `src/designer.sql` as their first disk candidates.
```
fpc -O3 -Xs -o welite src/wlhttp.lpr
./welite     # serves ./public/* and ./i18n/* ; WELITE_PUBLIC / WELITE_I18N override the dirs
```

**Embedded single binary (release):** run `genasset.py` from the repo root, build in `src/`.
```
python3 releases/genasset.py                       # writes src/wlassets.pas + src/wlpublic.rc
cd src
fpcres wlpublic.rc -o wlpublic.res -of res       # public/i18n + private SQL resources
fpc -dWLEMBED -O3 -Xs -o ../welite wlhttp.lpr # embed + build
./../welite                   # serves from inside the exe; no public/ or i18n/ needed
```
The generator skips missing/dangling aliases and non-files, matching disk asset
availability; valid file aliases remain indexed. `tests/embgen.py` compiles the
full current bundle and checks exact UTF-8/binary/alias resource bytes, including
a SQL-only bundle. The executable also carries private tenant/Designer SQL defaults
through a separate lookup, excluded from public asset URLs.

`genasset.py` embeds the `public/` and `i18n/` trees (overridable: `genasset.py OUT_PAS OUT_RC
ROOT[:URL_PREFIX] …`). RCDATA paths are written relative to the `.rc` file's dir, so `fpcres`
runs from `src/`. Verified on FPC 3.2.3 (aarch64): with `public/` and `i18n/` deleted, the
`-dWLEMBED` binary still serves `/robots.txt`, `/js/interact.js`, and `/i18n/langs.jsn`
from the executable.

### Size note (retro targets)
Embedding `public/` + `i18n/` adds ~37 MB to the binary, most of it `i18n/`. For an Amiga 68k or
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
Existing local asset mappings retain `cavalenc.jsn`, `km_KH.jsn`, `ru_RU.jsn` and `pt_PT.jsn`
for their corresponding source loader identities; source aliases remain
separate identities. Unsafe paths, duplicate identities, invalid metadata and a
missing English fallback are refused before writing output. Translation contents
are never modified by this command.

The current snapshot lists 245 installed language identities, including the 91
new catalogs with portable 8.3 filenames. Those catalogs use the WeLite English
key inventory. Keys with missing source translations or mismatched placeholder
inventories use the English value. Missing or broken legacy alias files are excluded.
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

The home page resolves its viewer locale before rendering body captions, so
header/profile-driven output matches the frame metadata. Board-list headings and
empty states reuse `boards` / `no-items-message`; account/admin and authentication
links reuse existing native keys. Board titles and usernames remain user content,
HTML-escaped without translation. Board visibility and administrator links retain
their existing access checks. All installed guest/member captions, profile/query/
header isolation and no-JS/no-cookie navigation have HTTP/browser coverage.

Direct board rendering passes the resolved viewer locale to native board/title,
all-boards/view-all and no-items captions, including header-only anonymous views.
Missing/inaccessible direct boards retain 404 status with translated not-found text;
published unavailable board views use the same key without disclosing private data.
Empty swimlane/list/card regions reuse the existing generic no-items string. User
board/list/card titles retain their original text and are HTML-escaped. Native movement arrows use fixed submit names and ASCII captions independent of
command values. Viewport links use native View plus isolated ASCII arrows; minimap
descriptions and legend reuse Board/View/yellow/current/cards/no-items keys. User
labels and logical coordinates retain their meanings. Selection toolbar buttons and count labels reuse existing native Edit/Delete/
Unselect/Export/Copy selection and Multi-Selection/swimlanes/lists/cards keys. Fixed
submit names separate those captions from action commands; the resolved board
language reaches the toolbar even when selected by header or profile. Selection
editing also reuses native edit/selection/item/title/color/description/Save keys.
Labels are associated on supporting browsers, while raw field names/user content
remain intact; `action_save` is caption-independent. Confirmation reuses native
Confirm/Delete selected/Details/Cancel and affected-kind labels in a structured
deletion preview. Fixed confirmation names separate captions from commands, with
scoped cascades/related counts and retained definitions checked by HTTP/browser
fixtures. Validation/error prose and other application messages remain open.

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

Published page widgets receive the frame's resolved locale through a temporary
copy of the validated session. Header/profile-based locale therefore reaches native
board-list captions, links and signed widget hidden language, as explicit query
locale already did. The original session and profile are unchanged; saved page
LTR/RTL direction remains independent of the translation language. Invalid session
identity cannot travel into generated widget links or reveal private boards.

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

### Regional French assets

`fr-BE.jsn` and `fr-CA.jsn` are physical local assets replacing broken legacy
symlinks. They retain 2,090 matching maintained regional source strings, eight
existing French compatibility phrases and two code-only title templates. The
removed board-members restriction phrase is translated directly into French.
All values follow local English key order and exact argument inventories.

### Colombian Spanish asset

`es-CO.jsn` replaces a broken symlink with 2,090 unchanged maintained regional
source strings and eleven compatibility values: three existing Spanish phrases,
six directly translated phrases and two literal title templates. English key
order and every source argument inventory are verified.

Both Portuguese Portugal source aliases (`pt-PT` and `pt_PT`) share the established
`pt_PT.jsn` file. Exact source identity remains selectable; no regional prose is
overwritten or duplicated to repair the loader filename mismatch.

### Japanese Japan asset

`ja-JP.jsn` replaces a broken link with 2,090 unchanged maintained regional
source values, seven existing Japanese compatibility phrases, two literal title
templates and direct Japanese translations for the legacy membership restriction
and zoom hint. Vocabulary/script and every argument inventory are checked.

### Authenticated Designer errors

Designer validation/missing-object/action-token errors use the same per-request
viewer frame as normal pages, including explicit query/posted language, tenant-bound
profile fallback, Content-Language/Vary and HTML/body direction. Error prose stays
escaped. Tenant/authentication gate failures and other early routes remain under
audit; message translation is separate remaining work.

Tenant-administrator and reserved Global Admin 403 HTML frames also use the
denied authenticated viewer’s own language/profile context, including validated
query/posted overrides. Their role and host restrictions remain the response gate.
Unknown-domain and other early route frames remain separate outstanding work.

Board selection errors (empty selection, invalid save/action and failed clone,
delete or export) also use the authenticated request’s viewer frame. Error prose
is escaped, with the existing failure status and rollback behavior retained.

### UI not-found frames

Unknown-domain UI gates use a public viewer frame resolved from validated
query/posted language and Accept-Language, with no tenant/profile fallback. Known
tenant route and missing/inaccessible-board 404 frames use normal viewer context.
The generic messages omit requested private names/IDs. JSON API tenant errors
continue through their existing separate JSON handler.

Early board-move failures (missing session, forbidden selection, bad action token
and invalid drop) now render the same frame. Failed session validation clears
viewer identity before language resolution; validated failures can use their own
tenant-bound profile. Rejection status/messages and card data remain unchanged.

Authentication rate-limit/session failures, enrollment admission/start failures and
reserved-admin registration denial now use the public authentication frame, honoring
query/posted/header language without a profile lookup. Existing retry and enrollment
private-response headers remain intact; error prose is escaped and contains no
credentials or setup secret. Full message translation remains separate work.

Admin domain/account validation, bad-token and storage failures now use the
authenticated viewer frame too. Forced domain insertion and account update
failures verify frame metadata while preserving the registry/account transaction
behavior and keeping rolled-back member credentials valid. Early Designer
import/export failures remain the next frame audit step.

Designer missing-page exports and import action-token failures now use the shared
HTML error frame, with no attachment disposition on failure. Successful page JSON
and archive ZIP downloads keep their existing formats and filenames.

### Contextual French arguments

Three base French values now restore a missing custom-field closing fence and
the source-authoritative literal search examples `user:` and `has:-due`. Only
reviewed code spans changed; all surrounding French prose, other values and key
order remain intact. The baseline French file now matches every English argument
inventory, alongside the regional French asset checks.

### Traditional Chinese attachment activity

Hong Kong, Traditional and Taiwan activity templates now restore canonical
attachment/card/list/board arguments from the corresponding native noun labels.
The English `at swimlane` fragment is replaced using each locale’s existing
swimlane term. Correct Chinese prose, all other values and key order stay intact;
argument and wrong-language-fragment regressions cover the three repaired keys.

### Bosnian asset

`bs.jsn` adds 2,101 keys in local English order. It retains 2,089 maintained
source values, fills the English byte-unit placeholder and provides nine direct
legacy phrases plus two literal title templates. Native source terminology
(`tabla`, `kartica`, `lista`, `traka`) guides the phrases; catalog, vocabulary
and exact argument inventories are verified.

### Private bootstrap SQL

`wlseed` resolves the two approved SQL kinds. An explicit `WELITE_SCHEMA` or
`WELITE_DESIGNER` file wins; a missing/invalid explicit file fails instead of falling
back. With no override, embedded defaults take priority. Ordinary disk builds try
`src/<name>.sql` then `<name>.sql`. SQL inputs are bounded to 16 MiB and reject
empty/NUL data; UTF-8 BOMs are accepted. Invalid embedded data never silently uses
a different disk version.

Native linked/CLI tests copy only the executable into an empty run directory,
initialize the reserved administrator and local tenant, create Designer tables/pages
and serve translated forms plus exact catalog/locale bytes. No source/asset/schema
directories are needed, SQL requests return 404, invalid explicit schema paths fail,
and shutdown is clean. Cross-target runtime acceptance remains separate.

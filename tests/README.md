# Welite regression tests

Set `TMPDIR` to an existing writable directory under the parent checkout's `.tools/tmp`.
Set `FPC` to your FreePascal compiler and, if needed, `PPC_CONFIG_PATH` to its configuration.
No system installs or changes to production databases are needed. Each runner creates
and removes its own temporary directory.

- `python3 tests/crypto.py`: compare SHA/HMAC to independent vectors, test proxy chains,
  and verify durable API token binding across process restart, copied DBs and credentials.
- `python3 tests/session.py`: exercise real session/tenant/credential boundaries,
  16 concurrent token consumers and idle expiry with both SQLite backends.
- `python3 tests/access.py`: verify board role permissions, selection isolation and
  safe redirects with both SQLite backends.
- `python3 tests/dbtext.py`: test text fidelity, SQL failures, foreign-key enforcement
  and large query results with both SQLite backends.
- `python3 tests/movelist.py`: compile actual Pascal movement code and test canonical
  schema fixtures against linked and CLI SQLite (the latter needs `sqlite3` on PATH).
- `python3 tests/admin.py`: compile the server, run it on an ephemeral local port with
  a temporary data root, and test Global/Domain Admin isolation, domain provisioning, Designer gates and page
  management over HTTP.
- `WELITE_UI=1 python3 tests/admin.py`: also drive Designer forms in Chromium with
  JavaScript disabled and Cookie request headers removed. Set `NODE` to Node.js and
  `WELITE_PLAYWRIGHT` to an installed Playwright module path if absent on module search
  paths. `PLAYWRIGHT_BROWSERS_PATH` selects an existing browser installation.

`WELITE_DB_CLI=1` selects the CLI SQLite server for `tests/admin.py`; combine it
with `WELITE_UI=1` to repeat the browser workflows against that backend.

Server processes and test databases are removed on success or failure. Browser tests
use no persistent profile and assert the cookie store remains empty.

`python3 tests/entropy.py` checks OS and portable entropy for linked and CLI SQLite,
including concurrent processes, stock exhaustion/corruption and failed deletions.
Set `WELITE_NO_OS_RNG=1` when running `admin.py` to compile without OS providers and
use a fresh test-only stock. Combine with `WELITE_DB_CLI=1 WELITE_UI=1` to exercise
the complete HTTP and no-JS/no-cookie browser workflows through this portable path.

`drop.py` runs through `admin.py`: shared-route multi-card drop persistence, invalid
board/lane destinations, SQL rollback and action-token replay refusal. With
`WELITE_UI=1`, `drag.js` additionally uses real Chromium mouse movement and CDP
simultaneous touch contacts, with cookies stripped, to verify selection groups and
serialized independent multi-touch drops. Baseline browser scripts still disable JS.

`python3 tests/short.py` verifies persistent short tenant keys, process restarts,
short temp directory collisions, offline migration and unsupported strict-build denial.
For `WELITE_SHORT_NAMES=1`, every client (including Python's SQLite module) must
load a library compiled with `SQLITE_ENABLE_8_3_NAMES=2`; the CLI must have that same
option. See `docs/runtime.md`. In strict mode, `admin.py` also scans the complete
live runtime tree, including WAL/SHM and hashed attachment components. `store.py`
checks binary upload/download/delete and preservation of original Unicode names.

`python3 tests/sjson.py` uses the **actual companion FerretDB Go codec** as its oracle,
with a temporary Go overlay and cached dependencies (`GOPROXY=off`). Set `GO` and,
if necessary, `FERRET_SRC`, `GOMODCACHE`, `GOCACHE`, `GOPATH`. It compiles the Pascal
codec, linked SQL harness and CLI extension; checks the extension ABI against
`sqlite3ext.h`; verifies typed TEXT/JSONB view updates and rollback against FerretDB;
and compares exact floating-point bits. It requires FPC, Go, a C compiler, SQLite
headers and SQLite 3.45+ for JSONB. See `docs/ferret.md` for the remaining adapter work.

`python3 tests/clifile.py` observes the real SQLite CLI boundary through a test wrapper:
megabyte script input, private 0700 directories/0600 files, quoted Unicode temp paths,
structured `-init` arguments, relative ATTACH paths and cleanup after success, SQL errors and spawn failure.
`dbtext.py` also checks a megabyte field with 2,000 newlines, exact CRLF and multiline
SQL defaults. The runtime uses private short files rather than an oversized SQL argv.

`python3 tests/ferroot.py` builds the root projection harness and CLI extension, then
runs isolated FerretDB servers to verify live two-way root collection edits, fresh SQL
collection creation, legacy TEXT/restart, typed metadata, rollback and safe reinstallation. It also exercises
embedded object/scalar array insert/update/delete, all thirteen child SQL views,
simultaneous key/value edits, custom child trigger retention, unowned child-table refusal
and byte-exact failed-edit preservation. Every declared root foreign key is tested on
insert/update; a forced nested cascade failure checks all collection bytes before/after,
followed by successful cascade deletion and unrelated-record retention. The real token
harness also checks private-token issuance/validation through fresh processes, user
references, reinstall persistence, credentials, SQL/Mongo deletion cleanup and atomic
restoration after a forced Mongo cleanup failure. It also checks schema username
uniqueness, typed-source and update denial, concurrent SQL writers, BINARY/NULL semantics,
ambiguous/disabled account lookup and duplicate-source preflight refusal/recovery.
Set `FERRETDB` to a native server built from the companion source revision documented in
`docs/ferret.md`. Use normal-sidecar SQLite for this test: a short-name library must not
open the same live database as a normal-sidecar FerretDB binary. No production data is used.
`python3 releases/genmodel.py --check` checks generated root specifications against DDL.

`python3 tests/bcrypt.py` verifies portable bcrypt against cached `golang.org/x/crypto`
v0.59.0 (Go 1.26+; set `GO` and optionally `CRYPTO_SRC`). Normal and checked Pascal
builds cover 2a/2b/2y, several costs, Unicode/NUL/key boundaries, malformed encodings,
Meteor SHA256 envelopes, fresh cost-10 credentials and legacy PBKDF2. No runtime crypto
library or service is used. `admin.py` additionally tests actual Meteor bcrypt web/API
logins, preserved service metadata and Argon2 precedence denial on each SQLite backend;
`ferroot.py` tests the real verifier against a Mongo-created typed account.

`admin.py` checks the default Meteor credential object for registration and bootstrap,
independent salts for identical plaintext, long UTF-8 passwords, `hashpw` JSON-object
seeding and token invalidation after replacing a credential. An independently generated
Python PBKDF2 fixture also verifies legacy web/API login without rewriting its bytes.
The CLI/portable-entropy variant exercises these same new-account paths.

`python3 tests/blake.py` compares BLAKE2b with Python hashlib and Argon2 H' with the
actual cached Go helper (Go 1.26+, `GO`/`CRYPTO_SRC` as for bcrypt). Isolated copies and
a temporary export overlay leave cached source unchanged. Normal/checked Pascal builds
cover binary/Unicode/NUL data, empty and exact/partial blocks, variable output boundaries
through 1 KiB and invalid lengths. This tests the hash foundation, not full Argon2 login.

`python3 tests/argon.py` checks portable Argon2 v1.3 d/i/id derivation against the
maintained Go helper and all three published RFC tags. It uses the same isolated cached
source/overlay approach as `blake.py`. Normal/checked builds exercise lanes, passes,
memory rounding and addressing, secret/associated data, binary/Unicode/NUL input,
a 64 MiB profile and rejected budgets. On POSIX, a memory-limited child checks allocation
failure. Credential parsing and HTTP Argon2 login are not covered by this kernel test.

`argon.py` also builds `phc.lpr` and checks Go-generated PHC/Meteor credentials in
normal/checked builds, including associated data, long UTF-8/NUL input, malformed and
duplicate records, canonical base64, structural limits, lowered/raised operator budgets
and stale-bcrypt refusal. `admin.py` tests actual Argon2 web/API logins and revocation
on each SQLite backend; `ferroot.py` checks a Mongo-created Argon2 account without BSON
changes. Legacy v16 and secret policy are covered by `argonv.py` and `secret.py`.

`python3 tests/argonv.py` builds the official P-H-C/phc-winner-argon2 C reference only
as a temporary test oracle. Set `ARGON2_SRC` to an unpacked official source checkout;
verified revision `f57e61e19229e23c4445b85494dbf7c07de721cb`. A C compiler is required.
Normal/checked Pascal builds cover d/i/id v16/v19, secret/associated data, lanes/passes,
rounding, explicit/versionless PHC and unsupported-version denial. Actual legacy
web/API and live FerretDB account tests run through `admin.py` and `ferroot.py`.

`python3 tests/secret.py` checks actual native/CLI secret-backed Argon2 web/API login,
independent credential HMAC markers, rotation between password proof and token issuance,
missing/empty secret denial, cross-process token validation and permanent revocation
after observed failure. Bcrypt accounts stay usable under a broken Argon2 file policy.
`argonv.py` additionally compares binary and 64 KiB file secrets with the official C
reference, private-file rejection and Python HMAC; `ferroot.py` checks a secret-backed
Mongo account without modifying BSON. Test runners discard operator secret settings.

`python3 tests/policy.py` checks shared-account password-only guards in a checked
Pascal build: pending/active/malformed factors, REQUIRE_2FA off/admins/all and LDAP
fallback/opt-out rules. `crypto.py` tests policy denial at direct token issuance and
cross-process validation, promotion to admin and permanent observed revocation;
`session.py` requires a fresh session after credential restoration before exercising
concurrent counters. `admin.py` tests both password routes and live web/API token denial,
while `ferroot.py` tests actual Mongo policy changes without rewriting source records.
HTTP OTP login and enrollment are covered below.

`python3 tests/totp.py` verifies the portable one-time-code core against RFC SHA1
HOTP/TOTP vectors and independent Python HMAC, with normal/checked Pascal builds.
Coverage includes base32 case/padding/binary inputs, wide counters/timestamps, leading
zeroes, Meteor-window edges, malformed input and the replay boundary. Durable counter
consumption and HTTP enrollment are covered below.

`python3 tests/replay.py` verifies durable OTP counter claims on linked/CLI SQLite:
sixteen concurrent processes with one winner, rollback of token/metadata on stale or
failed claims, retry, restart, canonical aliases, user/factor isolation, missing-token
behavior, logout retention and corrupt-schema/NULL/duplicate/negative state refusal.
`ferroot.py` also checks replay storage/cleanup in the live shared adapter. The harness
composes the actual claim with a token transaction.

`python3 tests/factor.py` exercises real password/OTP proofs and factor-bound web/API
tokens on both SQLite backends: single successful proof use, sixteen concurrent logins,
replay denial, forced metadata/counter rollback and retry, stale policy/factor snapshots,
required-factor modes and LDAP fallback. `ferroot.py` additionally checks a live shared
Argon2-secret/OTP account without BSON changes. HTTP code routing, attempt limits and enrollment are covered below.

`python3 tests/attempt.py` verifies durable pre-authentication reservations on linked/CLI
SQLite: sixteen concurrent attempts, account/peer/tenant caps, exact window boundaries,
clock rollback, restart persistence, bounded expiry cleanup, forced write rollback/retry,
schema refusal and separate tenants. `ferroot.py` checks private ownership and persistence
across shared-adapter reinstall while preserving account BSON.

`python3 tests/otphttp.py` verifies public web/form/JSON OTP login on both backends:
wrong/missing/malformed codes, replay, forced issuer rollback/retry, durable shared
web/API limits, spoofed forwarded headers, process restart, password-only compatibility,
required enrollment denial and factor-bound revocation. Set `WELITE_UI=1` with `NODE`,
`WELITE_PLAYWRIGHT` and `PLAYWRIGHT_BROWSERS_PATH` to run actual Chromium sign-in/reload
with JavaScript disabled and Cookie headers removed. Older `admin.py` and `secret.py`
credential-mutation cases explicitly expire attempt windows between independent cases;
`otphttp.py` retains real counters while testing admission policy.

`python3 tests/enroll.py` checks the limited enrollment core on linked/CLI SQLite:
password-only proof isolation, fresh 20-byte secrets, private token/client/expiry binding,
setup replacement, stale policy, forced and ignored activation rollback/retry, sixteen
concurrent confirmations, local token revocation, consumed-code login denial, fresh-code
login and user cleanup. `ferroot.py` verifies activation through shared JSON TEXT views,
unchanged unrelated BSON types, pending ownership/reinstall and physical user cleanup.
HTTP enrollment routing and its attempt limiting are covered below.

`python3 tests/enrhttp.py` verifies required-factor registration and public setup/
confirmation on linked/CLI SQLite: no early application access, fresh passwords, manual
secret, no-store/referrer headers, hidden POST tokens, client binding, shared account/
peer allowances, spoofed posted usernames/forwarded headers, rollback/retry, pending
restart, expiry/replacement and fresh-code sign-in. `WELITE_UI=1` runs `enrhttp.js` with
the same Playwright/Node settings as `otphttp.py`, completing setup, confirmation and
sign-in with JavaScript disabled and Cookie headers removed.

`ferroot.py` also verifies private auth source identity against actual users collection
UUID/table metadata: normal reinstall retains state; Mongo drop/recreate with reused IDs
and credentials denies old authentication before repair and clears it atomically on
reinstall. It covers stale login/enrollment proofs, old unbound-adapter migration with
conservative replay retention, and malformed-source rollback without private data loss.
Native factor/enrollment/session and public HTTP tests verify the no-marker path.

`ferroot.py` verifies owned physical model unique keys on both SQLite backends: Mongo
insert duplicate code 11000, rejected duplicate updates, eight concurrent mixed SQL/
Mongo attempts with one winner, case/NULL/missing usernames, fresh FerretDB startup,
altered/unowned index refusal, removed-index repair and legacy duplicate preflight/
ambiguous-login denial. It confirms managed listIndexes metadata stays unchanged.
Mongo-managed sparse/multikey account indexes and cache/error coordination remain open.

`python3 tests/resume.py` verifies Meteor SHA256/base64 hashes against Python, strict
command/digest/date input, typed append/remove/clear on TEXT/JSONB, malformed parent
refusal, 16 concurrent distinct appends without lost tokens and one duplicate winner.
It compiles the direct Pascal harness and both SQLite backends/extension. `ferroot.py`
checks live stored BSON, shifted Date/legacy/binary/long metadata, precision-sensitive
doubles, duplicate removal, rollback and clearing. Shared bearer authorization, expiry,
revocation and legacy conversion remain separate integration steps.

`resume.py` additionally checks typed/legacy token validity, equality-at-expiry, fractional
Date truncation, strict-before pruning, future timestamps, duplicate ambiguity and
Date/lifetime bounds. `ferroot.py` verifies live validity and expiry pruning with exact
BSON preservation. Shared bearer authorization and lifecycle wiring remain open.

`ferroot.py` also executes the real all-user revocation fragment through `revoke.lpr`
and enrollment: shared/legacy and local token clearing, pending setup cleanup, another
account's surviving credentials, failed/ignored writes, later metadata failure rollback,
source-switch denial and re-enable behavior. `admin.py` covers the actual native HTTP
disable route on both backends. Shared issuance and per-token lifecycle work remain open.

Targeted revocation coverage in `ferroot.py` removes both hashed and legacy plain forms
of one bearer, retains other sessions, checks ignored/failed-write rollback, missing-token
no-op and exact BSON, and exercises actual validator cleanup on credential change and
local expiry. `resume.py` checks the dual-form command, while session/native HTTP suites
retain tenant/client-bound behavior on both SQLite backends.

`ferroot.py` now verifies co-issued shared API tokens: atomic local/OTP/Meteor records,
Date output, source removal/expiry and restored-record denial, global ownership ambiguity,
collision with OTP rollback/retry, ignored-append rollback, stored lifetime precedence and
policy/SQRL-only refusal. Native suites retain private/browser behavior. Full Meteor
application round trips and broader settings compatibility remain separate gates;
existing-bearer adoption and fractional lifetimes are covered below.

Stored-policy coverage in `ferroot.py` verifies MFA overriding an opposite environment,
LDAP enable/fallback/migration overrides and null fallback, changed settings after proof
creation, and password disable/restore with durable observed bearer revocation. The
native policy/crypto/enrollment and HTTP suites retain private-store behavior on both
backends; `enrhttp.py` also covers required-factor registration and setup.

`python3 tests/lifetime.py` checks decimal/scientific day parsing and Date expiry
arithmetic against Node.js with 89 vectors in normal/checked builds: defaults, fractional
and submillisecond durations, negative/positive timestamps, Date boundaries and rejected
syntax/nonfinite/resource limits. Set `NODE` to the Node.js executable if needed.
The shared configuration/issuer integration is covered below.

Fractional lifetime integration in `ferroot.py` checks live password/OTP issuance,
exact local expiry against Node.js using the BSON Date issue timestamp, submillisecond
expiry without rounding up, stored/null/environment precedence and invalid settings.
`resume.py` checks fractional millisecond SQL expiry boundaries. Configuration and
issuance now use the kernel; existing-bearer adoption is covered below and scheduled
expiry remains open.

Legacy conversion in `resume.py` covers atomic TEXT/JSONB raw-to-hashed edits,
16 concurrent callers, original fractional timestamp preservation, idempotence,
already-installed hash precedence, ambiguous/malformed refusal and rollback. Live
`ferroot.py` checks eight concurrent conversions with exact BSON Date/Long/unknown
and sibling preservation. The guarded authorization/adoption path is covered below.

Shared bearer history tests in `ferroot.py` check owned `_wl_seen` creation/backfill,
ignored backfill/issuance write rollback, direct SQL old/new digest retention and history
survival after token revocation, reinstall and source UUID/unbound-store migration.
The adopter below uses this history to refuse re-creation of deleted credentials.

Shared adoption tests in `ferroot.py` exercise existing hash/legacy bearers, concurrent
validators, exact issue/expiry and BSON, ignored metadata/conversion writes with rollback
and retry, expiration, duplicate ownership, disabling, MFA resume without OTP consumption,
credential-change revocation and restored-record denial. Conservative policy gates and
full shared HTTP/Meteor application workflows remain separate work.

Shared expiry sweep tests in `ferroot.py` compile `sweep.lpr` and check owned durable
cadence, Date/numeric strict cutoff and equality, concurrent due callers, ignored account
and checkpoint writes with complete rollback/retry, reinstall, backwards clocks, stale
source and fractional cutoff against Node.js. Retained BSON/precision/unknowns are
compared exactly on both backends. Background worker/discovery and shared-store local cleanup coverage follow.

Background maintenance coverage in `ferroot.py` uses the real `maint.lpr` worker with
separate connections and an accelerated polling interval. It observes a failed sweep,
checks no partial commit, removes the failure and verifies idle retry, another due pass,
exact BSON, native/missing path isolation and clean stop. Production polling remains one
minute with the durable ten-minute cadence. `enrhttp.py` verifies both-backend HTTP
startup/registration/enrollment regressions; root discovery and shared-store local cleanup are covered below.

`discov.py`, called by `ferroot.py`, tests root-based startup and refreshed discovery
without HTTP access. Independent SQLite backups of real shared data verify local and
enabled-domain cleanup, dynamic enabling/new registry entries, disabled/orphan/invalid
host exclusion, no provisioning of missing directories, native-registry skip, broken
registry detection/recovery and clean shutdown. The copies are separate databases, never filename aliases. Both backends run.

Bearer-link coverage in `ferroot.py` checks owned `_wl_pair` records for shared issuance
and adoption, ignored insert/backfill rollback, unknown-hash migration, validated-access
enrichment, post-local-deletion targeted revocation and source isolation/reinstall.
`crypto.py` retains native/private token behavior. Shared-store local cleanup follows.

`expiry.py`, invoked by `ferroot.py`, verifies shared-store local expiry at equality,
linked hash/legacy/duplicate retirement, orphan cleanup, retained BSON/scalar entries,
unknown-hash identity, history, sibling/account isolation and five ignored-write rollback
stages. A real worker then removes an expired private/shared credential during idle time.
`resume.py` verifies digest-set commands and SQL hash vectors including Unicode/NUL on
both backends. Pending-enrollment and legacy-store coverage follow.

Pending enrollment cleanup in `expiry.py` creates real setup records, expires one at
confirmation equality and retains another unchanged. An ignored pending deletion rolls
back shared/local/history cleanup and the due checkpoint. The idle worker later removes
the other expired setup. OTP replay state remains unchanged. Both backends and the
separate `enroll.py` proof/activation/binding/replay suites verify the lifecycle.

`python3 tests/lsweep.py` tests normalized-store maintenance on linked/CLI SQLite using
real password issuance and pending setup. It checks inclusive expiry, valid/replay
retention, optional table absence, ignored deletes and checkpoint seed/update rollback,
concurrent due calls, backwards clocks, incompatible/mixed layout refusal and actual
idle worker cleanup. No shared/history tables or missing optional auth tables are created.

`python3 tests/shrhttp.py` requires `FERRETDB` pointing to the maintained live
FerretDB binary and normal SQLite filename mode. It builds both HTTP backends and
the CLI extension, checks canonical filename refusal without file creation, then
opens an existing Mongo-created store with `WELITE_SHARED=1`. It verifies both-way
HTTP/Mongo changes, BSON preservation, private browser sessions, API restart and
shared revocation, with no normalized shadow database. Fresh shared creation,
strict 8.3 sharing and full Meteor application workflows are not covered by this test.

`python3 tests/stop.py` verifies Unix SIGTERM/SIGINT on both HTTP backends: idle
accept, sustained request traffic, an incomplete request, repeated stop signals,
worker-cleanup completion, exit status zero, immediate restart and SQLite integrity.
Incomplete sockets must be woken without leaving framework threads blocked.

`python3 tests/catalog.py` checks current compact and legacy literal language
metadata without JavaScript execution, native Unicode names, escaped text,
malformed/unsafe/duplicate refusal, failed-input retention and exact agreement
between the strict JSON and browser catalogs. Every advertised translation file
must exist; the converter never changes translation bytes.

`python3 tests/langsel.py` checks every installed language/direction, explicit/profile/
weighted-header precedence, aliases, regional and legacy Hebrew fallback, invalid
ranges/catalogs, bounded disk/embedded asset lookup and traversal refusal. `admin.py`
uses the actual translation root and `langhttp.py` verifies native HTTP profile/header
precedence and structural grid reversal on either backend. `shrhttp.py` also checks
live Mongo profile-language changes, explicit override and preserved BSON profile data.

`python3 tests/xlate.py` verifies per-page text lookup for every installed language,
UTF-8, literal markup/tokens and English/explicit fallback for absent/empty/typed or
malformed data. `python3 tests/signlang.py` checks every language's actual sign-in
HTML on both backends: escaped labels, language/direction/response headers, form
language retention and stable credential field names, without scripts/cookies.
`WELITE_UI=1 python3 tests/enrhttp.py` also drives the translated English form through
required-factor setup/login in Chromium with JavaScript/cookies disabled when
`WELITE_I18N` points at the installed translations.

Sign-in language coverage also verifies every picker option/native name/selected
state, failed-retry credential secrecy, successful redirect language and hostile
option names. The no-JavaScript/no-cookie Chromium enrollment test submits the
Finnish and Arabic picker before its setup/login flow, then checks the chosen
language survives the login redirect.

`authlang.py`, invoked by `enrhttp.py`, verifies Arabic required-factor registration,
setup failure/retry, secret issuance, invalid-code retry, confirmation and fresh-code
sign-in on both backends. It checks language-only flow URLs, private response controls,
unsupported language refusal and absence of credentials/setup secrets in redirects.
The Chromium enrollment flow also asserts only language appears in setup/confirmation
queries before the intended session redirect.

The sign-language HTTP test covers registration labels for every installed language,
its picker, Finnish missing/mismatched/taken-username errors and blank credential
retry forms. Chromium additionally submits Finnish registration without JavaScript
or cookies and checks the locale-only completion URL before its enrollment flow.

All-language HTTP coverage includes enrollment setup labels and its private response
headers. The actual Arabic enrollment test checks translated OTP/confirmation labels;
the Chromium flow follows the translated English start/confirm/sign-in controls.

Session tests also verify request-only locale state, safe hidden fields, encoded
query names, fragment placement and absence from serialized auth metadata.
`langnav.py`, called by `admin.py`, checks home/board/Designer/admin links and signed
mutation returns, GET search forms, arbitrary IDs/search containing query characters,
fragments, safe re-login and request isolation. With `WELITE_UI=1`, `langnav.js` drives
board/clear/home/admin/Designer/save in Chromium with JavaScript/cookies disabled.

Layout coverage switches an actual published page between HTML4 and HTML3.2 and
checks invalid-doctype refusal. The Chromium layout test checks HTML 4.01 Transitional
and standards parsing mode before its span/required/RTL/sorting assertions.

`frames.py`, invoked by `admin.py`, tests language/header/body-direction metadata on
home/board/Admin/Designer/published and posted selection edit/delete pages. It checks
tenant-bound profile preferences against header/query/posted choices, saved fixed
direction and unchanged profile data. The native harness pins its temporary data root
and native mode. Shared HTTP tests also assert Mongo profile changes yield matching
HTML and Content-Language without changing unrelated BSON profile values.

`python3 tests/tokfix.py` verifies token-only repairs preserve prose and untouched
human text/key order; Unicode names, case, printf/named formats, URL octets,
ambiguous/repeated refusal, known code-only title repairs with prose refusals,
dry run, guarded input/record paths, symlink isolation
and idempotence are covered. `tokdone.jsn` records repaired keys whose underscore
and percent inventories must match English. It constrains tokens, allowing future
human prose improvements. Ambiguous data remains explicitly tracked in TODO.

`python3 tests/bglang.py` guards the Bulgarian custom-field activity against its
former Serbian seed using vocabulary, distinctive letter/word forms and the exact
English placeholder inventory. It permits Bulgarian phrasing changes while keeping
source argument names/counts intact.

`python3 tests/acelang.py` guards Acehnese against its Malay/Indonesian seed using
native core/activity/legacy vocabulary, beyond Latin-script checks. It verifies
English key order and every underscore/percent inventory. The installed-language
reader and form tests exercise the updated labels without a translation service.

The Arabic navigation browser regression also measures the shared keypad: left,
down and right must appear in physical order, with up above down, under an RTL
page. It reproduces inherited table reversal without JavaScript or cookies.

The same browser regression compares physical RTL board-column and minimap-link
positions: the first logical list appears on the right in both tables.

Arabic viewport checks follow View left/right without JavaScript or cookies,
assert logical X coordinates and inspect the displayed list after each redirect.

The Arabic browser flow also moves a card physically right then left and a list
left then right, checking destination cells/geometry and restoring the fixture.

Designer layout tests cover saved RTL direction overriding English on movement,
span collisions/boundaries and reversible columns; browser geometry verifies both
physical horizontal widget arrows without JavaScript or cookies.

Catalog regression checks also require the existing Khmer/Cambodia and
Russian/Russia files under their established portable underscore filenames.

`python3 tests/frlang.py` verifies the physical French Belgium/Canada files,
catalog registration, native vocabulary, non-English compatibility prose, exact
English key order and every argument inventory.

`python3 tests/eslang.py` checks the Colombian Spanish physical asset, catalog
identity, core/compatibility vocabulary, English key order and every argument
inventory, including translated legacy phrases absent from the source catalog.

The catalog test also requires both Portugal source aliases to resolve to the
same established `pt_PT.jsn` asset; all-identity kernel/form suites cover each alias.

`python3 tests/jalang.py` checks the physical Japanese Japan asset, native
vocabulary/script and compatibility prose, catalog identity, English key order
and exact argument inventories.

`frames.py` also exercises Designer 400/403/404 error frames, explicit query/posted
language versus authenticated profile/header fallback, matching language/direction
metadata and unchanged profile data. Error text remains escaped.

`gatelang.py`, run by `admin.py`, exercises supported tenant/global administrator
denial routes with different Arabic/Hebrew profiles, Finnish query/posted overrides
and invalid-choice fallback, asserting 403, matching metadata and unchanged profiles.

The frame matrix also posts invalid board selection actions in Arabic/Finnish,
checking 400, matching language/direction metadata and unchanged card title/location.

`notlang.py`, run by `admin.py`, exercises unknown-domain UI GET/POST routes
with query/posted/header language, checks 404 metadata and no registry provisioning,
verifies inaccessible-board responses omit private content, and retains JSON API
errors. The authenticated frame matrix also covers profile-based board/route 404s.

Board error-frame coverage also checks missing/invalid sessions, forbidden selections,
bad tokens and signed invalid drops. It verifies public fallback for invalid
sessions, profile/posted choices for valid viewers and unchanged card data.

`autherr.py` supplies shared frame/privacy assertions. Enrollment HTTP tests cover
localized sign-in/setup/confirmation 429 responses and a forced enrollment-storage
500 with unchanged account/pending state. Tenant-tier tests cover Arabic reserved
registration denial, preserving status, private headers and Retry-After.

`widgetrt.py` exercises published fixed/automatic board directions, reversible
physical moves, origin/locale redirects and invalid/disabled/rebound widget
context refusals. It also denies a board writer borrowing an admin-only page’s
override. `widgetrt.js` checks physical fixed RTL/LTR columns and both move
directions in Chromium without JavaScript/cookies.

The Designer browser layout test also asserts computed LTR direction on physical
left/right arrow inputs within an RTL editor, guarding against inherited glyph
mirroring alongside its actual movement geometry checks.

`tabrtl.py` verifies RTL/LTR data-table source order, selected column mapping and
locale-preserving editable URLs. `tabrtl.js` checks header/cell geometry, forces
table direction to LTR to simulate ignored dir attributes, and submits column
selection without JavaScript/cookies. Test CSS insertion uses synchronous DOM
mutation so it does not wait for disabled page-script events.

The data-table matrix also checks mirrored search/pagination source order, isolated
physical previous/next arrows and browser geometry with ignored table direction.
Both page directions retain search, selected columns and locale through page links.

Admin frame coverage includes global-domain token/host/action validation and forced
registry insertion failure. People management forces a failed account disable and
checks unchanged flags plus still-valid member access after token-revocation rollback.
Both failure types assert authenticated language/header/direction metadata.

Error-frame checks include missing Designer exports and token-denied page/archive
imports, requiring HTML metadata and no attachment disposition. Existing HTTP and
browser import/export cases retain successful JSON/ZIP formats and download names.

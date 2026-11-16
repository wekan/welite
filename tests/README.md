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

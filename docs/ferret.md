# FerretDB SQLite interoperability — implementation in progress

The acceptance target is the **same physical document database**, read and written
by Welite's SQL and the maintained FerretDB fork. An offline JSON import into the
normalized schema does not meet that target. `TODO.md` retains the overall unchecked
item until application-level shared-database workflows pass.

## Storage evidence

Inspected the working source of `wekan/FerretDB`, revision
`984be0e8ee59afe5d19005336b81c76d44c0e695`:

- `internal/backends/sqlite/metadata/registry.go` registers collections in
  `_ferretdb_collections(name, table_name, settings)`. Physical tables have generated
  names; a collection's Mongo name is not its SQL table name.
- `metadata/metadata.go` names the document column `_ferretdb_sjson`.
- `metadata/storage.go` supports old SJSON TEXT and current SQLite JSONB BLOB columns.
  `insert.go` writes typed SJSON through `jsonb(?)` for the latter.
- `internal/handler/sjson` encodes BSON types and key order in the root `$s`, whose
  `$k` array records order and `p` map describes every field. Nested objects have
  recursive schemas; arrays have one schema per element. Dates are integer epoch
  milliseconds, not the normalized schema's ISO strings. Ordinary JSON alone loses
  distinctions such as int32/int64, date/timestamp, string/ObjectID and binary subtype.
- The pool currently discovers `.sqlite` filenames. This and shared attachment paths
  must be reconciled with the short runtime layout before claiming a drop-in deployment.

## Verified storage kernel

`wlsjson.pas` converts a complete plain document plus an optional previous SJSON
record and explicit field hints into typed SJSON. Unchanged fields retain their
BSON metadata. Nested edits and reordered array elements retain matching old types.
Explicit hints supply types for new date, int32, timestamp, binary and ObjectID
values. New unannotated integral fields use BSON int64; other ordinary JSON types
are inferred. Ambiguous integers beyond signed int64 need an explicit compatible
hint, rather than silently becoming an imprecise double.

Original numeric literals are retained, including negative zero and integral double
literals larger than uint64. Strict JSON, UTF-8, schema/key agreement and scalar
ranges are checked. Duplicate keys, NUL field names, reserved root `$s`, malformed
metadata and incompatible hints are refused. The current codec bounds serialized
input/output to 16 MiB and document nesting to 100; it does not truncate records.
This bound applies to serialized SJSON, including its schema, and must be considered
when the full model adapter's document-size policy is finalized.

The linked backend registers these deterministic, side-effect-free SQLite functions:

```
wl_plain(sjson_text)
wl_sjson(complete_plain_json, previous_sjson_text_or_empty, field_hints_json)
wl_model(previous_sjson_text_or_empty, column_patch_json, model_spec_json, mode)
wl_relation(previous_sjson_text, command_json, relation_spec_json)
```

Use `json(document_column)` when reading either SQLite storage form, and wrap the
result in `jsonb(...)` for a JSONB column. The test uses a writable SQL view over the
real column representation and verifies edited records with FerretDB's own decoder,
including exact IEEE-754 bits, all its scalar types, Unicode/NUL text and nested order.
Malformed updates fail within the SQL transaction. This kernel is tested; Welite's
full domain-model views and triggers have **not yet been installed** by it.

## CLI backend

The production linked build contains the functions in its executable. The CLI
bootstrap backend can load the same Pascal code as a local extension:

```
fpc -B -Cg -dWLSQLEXT -Fusrc -FUbuild -FEbuild -obuild/wlfunc.so src/wlfunc.lpr
```

Create `build` first; use isolated output directories when building several variants.
Set `WELITE_SQLITE_EXT` to the extension's absolute path for CLI calls. The extension
uses the host SQLite API table, never a second library on the host's connection.
SQLite 3.35 or newer is required to load this extension; JSONB needs 3.45 or newer.
A missing or failed configured extension prevents the requested SQL from executing.
No external code is fetched or loaded unless this local path is explicitly configured.
The CLI transports SQL through a private short `query.sql` file rather than a process
argument, so large adapter scripts and documents do not hit the OS argument-size limit.
Script files are removed on success/failure. Control-containing SQL literals retain their
exact bytes through the shell reader. Only the native Linux extension ABI has been
verified so far.

`tests/sjson.py` builds a Go oracle from the companion FerretDB source using an overlay;
it edits no files there. It requires Go and already cached dependencies. Tests cover
both backends, TEXT/JSONB view writes, rollback, explicit hints, malformed/deep input,
UTF-8, field order and bit-exact doubles. The Go oracle is a test dependency only.

## Verified root projections

`releases/genmodel.py` generates `src/wlmodels.pas` from `schema.sql`; `--check`
checks drift. Python is a build/test tool, not a runtime dependency. `wlferr.pas`
exposes `InstallRootModels` (now installing roots and children), currently called only
by the SQL test harness. It is
intentionally not installed by normal server startup while the remaining gates are open.

The eleven root views cover boards, swimlanes, lists, cards, comments, checklists,
checklist items, custom fields, users, activities and attachments. The installer discovers
registered physical tables and creates missing compatible collections, UUID metadata and
unique ID indexes. It owns only its marked views/triggers and private model registry;
existing normalized tables are refused, physical indexes retained and custom view triggers
recreated. Installation is one transaction. Sparse updates preserve unedited fields and
BSON metadata rather than materializing defaults into every document. Required fields,
immutable IDs, nested attachment parents/WIP settings, dates and JSON remainder fields
are checked. `_wl_source` is a write-only source for typed root cloning; child arrays
are omitted until their new IDs can be mapped by the relation layer.

`wl_storage(physical_table)` queries the host connection's actual document-column type
through SQLite's metadata API. It is innocuous but not deterministic: FerretDB can upgrade
TEXT to JSONB after installation. This avoids querying a pragma virtual table from CLI
triggers with `trusted_schema` disabled.

`tests/ferroot.py` runs isolated local FerretDB servers and the real SQL projections on
both backends. Verified with a binary built from the inspected revision above, including
fresh SQL-created collections readable/writable by FerretDB, Mongo edits visible in SQL,
legacy TEXT after restart, typed unknown data, exact numeric bits, atomic failed edits,
ID protection and ownership-safe reinstallation. These are root-storage tests; application
HTTP authorization and relation workflows are not yet exercised against this adapter.

## Embedded relation editing kernel

`wl_relation` applies one row edit to an array inside a typed document. The relation
specification supplies `path`, `keys`, `fields` (the same coercion contract as root
columns), and optional `scalar: true` for arrays of string IDs. A command supplies
`op` (`insert`, `update`, `delete`), `old` key values and sparse `values`. Insert uses
field defaults; update preserves omitted fields and unknown row properties. The
result retains sibling order and is passed through the typed codec. Duplicate keys,
missing targets, malformed arrays and invalid patches fail the SQL statement.

Live root tests exercise both object members and nested scalar ID arrays through
this function, decoded by FerretDB, with byte-exact BSON comparisons after rejected
edits. The function is available in linked SQLite and the CLI extension. `wlrel.pas` now installs thirteen child SQL views using generated relation contracts.
They read arrays from the same physical parent document and write through `wl_relation`.
A single sparse update supports key and value changes together; parent reassignment is
refused. Missing parents fail insertion. The root installer includes child installation
in its transaction, refuses unowned child objects and restores custom view triggers.
Optional dependency type defaults participate in key matching. Actual dependency storage
is `cardDependencies`, with target `cardId`; labels and dropdown IDs use `_id`.

Live tests cover every child view, Mongo edits visible to SQL, SQL edits decoded by Mongo,
unknown typed child properties, multi-column key edits, duplicates, missing parents and
ownership refusal. Declared root cascades and references are implemented as described below. Typed custom-field
value conversion and legacy bare-string dependency normalization remain open.
SQL `INSERT OR REPLACE` conflict behavior also needs application-level reconciliation
before these views replace normalized tables.

## Schema references and cascades

The generator reads root `PRAGMA foreign_key_list` metadata into each model contract.
`wlrefs.pas` emits reference checks in insert/update view triggers and declared delete
cascades in the root deletion trigger. Insert checks inspect the fully projected document,
so clone-source fields cannot bypass validation. Nullable references remain optional.
Embedded child arrays disappear with their root; they need no separate cascade. Cascades
through cards and checklists execute inside the initiating SQL statement.

Live tests check every declared root foreign key on insertion and update, including
source-based inserts. A forced failure during checklist-item deletion restores every
collection's SJSON exactly after a board deletion attempt. Successful deletion removes
the board-owned graph while retaining unrelated boards and unconstrained attachment,
activity, user and custom-field records, according to `schema.sql`. User/custom-field
root deletion also removes their embedded child rows. Both SQLite backends pass.

These are Welite view constraints. Direct Mongo writes retain FerretDB's existing
semantics: the adapter adds no reference-enforcement triggers to physical collections.
Existing dangling Mongo references are not rewritten at installation. Private token cleanup
has a separate physical user-deletion trigger described below. SQL account uniqueness
and ambiguous-login handling are described in their own section.

## Private token storage

`wlpriv.pas` installs owned `login_tokens` and `authmeta` tables. SQLite cannot use a
view as a foreign-key parent, so token insert/update triggers check the user view
explicitly. Metadata keeps its foreign key to the real token table. A private ownership
signature and exact table definition are checked before reuse; unowned or altered
objects stop the entire installer without mutation. Compatible reinstallation retains
existing private tokens.

An AFTER DELETE trigger on the physical user collection removes private tokens.
A token deletion trigger explicitly removes metadata as well, including on connections
with foreign keys disabled. These triggers use SQLite built-ins rather than Pascal
extension functions, so live Mongo deletion can execute them. A forced metadata-cleanup
failure rolls back the Mongo deletion and preserves the user's valid token. Collection
DROP/recreation and authentication migration still need application-level policy; the
physical delete trigger handles document deletion, not collection removal.

Tests run the actual `IssueLoginToken` and `ValidateLoginToken` implementation through
fresh harness processes on linked and CLI SQLite, including credentials, missing users,
reinstallation and both SQL/Mongo deletion. The existing hashing, tenant binding and
legacy-token denial regression suite also passes. These are Welite private tokens;
Meteor `services.resume.loginTokens` is not mapped by this step. Meteor bcrypt credential compatibility and Argon2 v16/v19 verification are now available as described below;
shared-session compatibility remains unfinished.

## SQL unique keys and account lookup

The generator reads non-primary unique indexes from `schema.sql` into the root model
contract. Its current unique key is `users.username`. `wluniq.pas` checks insert and
relevant update projections against the live SQL model, excluding the current row on
update. Typed clone-source values participate in the same check. The canonical schema
uses BINARY case comparison and permits multiple NULL usernames; both are retained.
SQLite serializes statement writes, so simultaneous SQL insertions cannot both pass the
check. Preflight refuses existing duplicate keys without rewriting the source records.

`LoginAccount` is shared by web/API login. It fetches at most two username matches,
including disabled accounts, and returns a login candidate only for one enabled match.
This matters because direct Mongo writes can introduce duplicates outside SQL view
checks. Existing id-bound sessions are not resolved by username and keep their existing
credential binding. Account index provisioning through Mongo is still separate work;
this step adds no physical unique index or registry index entry.

Tests verify normal and typed-source duplicates, unchanged stored bytes after denial,
case/NULL behavior, exactly one success among four concurrent SQL insertions, a disabled
Mongo duplicate causing login denial, duplicate preflight refusal and repair/reinstall
recovery on both backends. The shared lookup is exercised through fresh auth harness
processes, and both HTTP application regression suites pass. Shared Meteor account
formats and index policy still need integration before normal server activation.

## Meteor bcrypt credentials

`wlbcrypt.pas` implements portable bcrypt with a 16-byte salt, canonical bcrypt base64,
2a/2b/2y formats, standard cost range and byte-preserving password input up to 72 bytes.
Its arithmetic is explicitly modulo 2^32 even in checked builds. Blowfish constants and
expansion are adapted from maintained `golang.org/x/crypto` v0.59.0; the original BSD
notice is retained in `docs/gocrypt.txt` and must accompany binary distribution too.

`VerifyPassword` accepts legacy PBKDF2 strings and Meteor password objects. Meteor
passes the lowercase SHA256 plaintext digest into bcrypt, avoiding its raw key-size
limit for long plaintext. `HashMeteorPassword` generates a fresh-salt cost-10 bcrypt
object compatible with `services.password`. Registration, local admin bootstrap and the `hashpw` CLI now create this object by
default. The CLI output is an object to embed at `services.password`, not a quoted hash
string. Existing PBKDF2 records remain readable without login-time rewriting. Reset and
other password-object properties remain unchanged on login.

Current [Meteor accounts-password source](https://raw.githubusercontent.com/meteor/meteor/devel/packages/accounts-password/password_server.js)
also selects an Argon2 credential ahead of bcrypt:
a nonempty Argon2 value is selected for bounded verification and never falls back to
an older bcrypt value, including on parse/verification/resource failure.
Malformed object values and duplicate keys also fail closed. This is partial shared
account compatibility, not completion of all Meteor authentication modes or sessions.

`tests/bcrypt.py` compares exact generated hashes and verifies new credentials with
independent Go crypto code, using cached dependencies without network access. It checks
several costs, Unicode/NUL and boundary cases, malformed input, SHA256 envelopes, random
salts and legacy compatibility in normal/checked builds. HTTP tests exercise both login
routes and credential invalidation on linked/CLI SQLite. Live FerretDB tests verify a
Mongo-created account through the real login lookup/verifier and compare its BSON bytes
to prove no credential or metadata rewrite.

## Argon2 hash foundation

`wlblake.pas` implements unkeyed BLAKE2b from [RFC 7693](https://www.rfc-editor.org/rfc/rfc7693.html)
and Argon2's length-prefixed variable-output H' from
[RFC 9106 section 3.3](https://www.rfc-editor.org/rfc/rfc9106.html#section-3.3).
It uses explicit little-endian loads/stores, modulo-64-bit arithmetic, fixed-size
compression state and preallocated variable output. Empty/exact/partial final blocks
and digest sizes below/above 64 bytes are tested. Temporary compression state is cleared.

`tests/blake.py` compares raw BLAKE2b with Python hashlib and H' with the actual Go
Argon2 helper from cached `golang.org/x/crypto` v0.59.0. It copies only the needed
packages into a temporary test module and overlays an export wrapper; the original
module cache is unchanged. Normal and overflow/range-checked Pascal builds pass input
block boundaries, binary/Unicode/NUL input and output boundaries through 1 KiB.
Verification so far is native Linux; other target builds remain in the platform gate.

`wlargon.pas` supplies Argon2 v16/v19 d/i/id key derivation: initial parameter hashing,
first blocks, BlaMka mixing, dependent/independent addresses, lane indexing, pass XOR
and final lane reduction. Original memory cost participates in the hash; allocation is
rounded to the required lane/slice multiple. Logical lanes run sequentially inside each
synchronized slice, preserving their result without requiring OS threads. Secret and
associated-data inputs are supported. Allocated blocks/temporary state are cleared.

Callers must provide `TArgonLimits`; the default kernel policy permits 65,536 KiB,
16 passes, 64 lanes and 1,024 output bytes. Parameters beyond the chosen limits, memory
below eight blocks per lane, short salts/keys and platform byte-count overflow are
rejected before allocation. No parameter is silently weakened. Available RAM can still
be lower than these limits; allocation failure propagates to the caller. The tested
harness converts it to failure. Runtime PHC parsing/verification policy is described below.

`tests/argon.py` compares all three variants with the actual maintained Go deriveKey
helper and fixed [RFC 9106 section 5 tags](https://www.rfc-editor.org/rfc/rfc9106.html#section-5).
Normal/checked builds cover original-cost rounding, address-block boundaries, lanes and
passes, secret/associated data, binary/Unicode/NUL inputs, 64 MiB and invalid budgets.
A constrained child process verifies graceful allocation failure on the native test host.
Other target builds remain unverified. The derivation source retains the Go BSD notice
and `docs/gocrypt.txt` license.

The credential verifier uses these kernels as described below. Default derivation is
v19; selecting v16 changes both the parameter hash and subsequent-pass overwrite/XOR
rule. Optional out-of-band secret policy is documented below.

## Argon2 credential verification

`wlphc.pas` parses six-field PHC v16/v19 records for Argon2d/i/id, and five-field
versionless legacy records as v16, requiring one each of
`m`, `t`, `p` and optionally base64 `data`. Parameters may be reordered but cannot repeat;
unknown parameters, signs/leading zeroes, invalid lengths, padding and noncanonical base64
bits are rejected. Records are bounded to 1 MiB; salt and associated data to 64 KiB each.
Structural separator counts are bounded before splitting. These encodings follow the
[node-argon2 implementation](https://raw.githubusercontent.com/ranisalt/node-argon2/master/argon2.cjs)
and its [PHC serializer](https://raw.githubusercontent.com/simonepri/phc-format/master/index.js).

`VerifyPassword` passes the SHA256 plaintext digest to Argon2, selecting it ahead of
bcrypt when present. Parse errors, unsupported versions, resource excess, allocation
failure and wrong tags return denial without bcrypt fallback. Derived temporary tags
are cleared after constant-time comparison. Login does not rewrite service metadata.

Operator verification limits default to the kernel policy and can be overridden with
positive canonical decimal environment values:

| Variable | Default |
| --- | --- |
| `WELITE_ARGON_MEMORY_KIB` | 65536 |
| `WELITE_ARGON_PASSES` | 16 |
| `WELITE_ARGON_LANES` | 64 |
| `WELITE_ARGON_KEY_BYTES` | 1024 |

Invalid configured values deny Argon2 verification. Actual platform allocation bounds
still apply. No stored cost is silently reduced. These verification limits do not change
new-account creation, which continues to use compatible bcrypt objects.

Go-generated fixtures test all three PHC variants, associated data, Meteor envelopes,
long UTF-8/NUL plaintext, malformed/duplicate structures and both lowering and raising
budgets. Both HTTP backends pass real web/API logins, metadata retention and credential
revocation tests. The live FerretDB test compares BSON before/after actual verification.
Legacy v16 and versionless behavior is verified separately against the
[official C reference](https://github.com/P-H-C/phc-winner-argon2/tree/f57e61e19229e23c4445b85494dbf7c07de721cb).
`tests/argonv.py` builds that source only inside its temporary test directory; it is not
a runtime dependency. Set `ARGON2_SRC` to an unpacked official source snapshot. Tested
revision: `f57e61e19229e23c4445b85494dbf7c07de721cb`. The test covers d/i/id, both versions,
secret/associated data, lane/pass/rounding boundaries, explicit/versionless envelopes,
wrong version/tag combinations and normal/checked builds. Native/CLI HTTP and live
FerretDB tests verify both legacy encodings without rewriting credentials. Unknown
versions remain denied. Optional operator secret files are supported as described below.

## Optional Argon2 secrets and credential binding

The default secret is empty, matching standard Meteor accounts-password usage.
`WELITE_ARGON_SECRET_FILE` selects a binary secret for **all Argon2 credentials in the
process**, including all its tenants. This is explicit policy: the verifier does not
try empty/alternate secrets after failure. Bcrypt and legacy PBKDF2 remain independent
of this setting. New-account generation remains compatible bcrypt.

`wlsecret.pas` reads 1–65,536 exact bytes with no newline stripping or text conversion.
Missing/empty/oversized configured files cause denial. On Unix the file must be regular
with no group/world permission bits; symlinks and FIFOs are rejected and the opened inode
is checked against the inspected path. Other targets use read-only shared-file access
and rely on operator ACLs; those targets remain in the platform verification gate.
Use a private short filename such as `pepper.key` for strict runtime layouts. Rotate
files atomically so readers receive one coherent version. No secret is generated,
transmitted or saved into SQLite by this setting.

`VerifyCredential` returns a binding captured from the same bytes used in verification.
For Argon2 with a configured secret it is HMAC-SHA256 over the stored password object
with a dedicated domain prefix. Without a secret it retains the previous SHA256 marker.
Token issuance rechecks current policy, refusing rotation between proof and issuance.
Web/API validation also rechecks it: changed/unavailable secrets deny access, and failed
credential validation removes the token (plus the in-memory web context) so an observed
failure cannot revive after restoring the prior file. This is request-time validation;
there is no filesystem watcher or historical key registry. Secret fingerprints are
server-side credential bindings, not raw secrets or an alternate login mechanism.

`argonv.py` checks binary/64 KiB secrets and fingerprints against the official C oracle
and Python HMAC, including private-mode, missing/empty/oversized, symlink and FIFO cases.
`secret.py` runs actual native/CLI HTTP login, issuance races, cross-process bearer checks,
revocation/restoration and unaffected bcrypt login. `ferroot.py` verifies a secret-backed
Mongo account without changing its BSON. Existing HTTP/crypto regressions still pass.

## Shared account policy guards

WeKan enables `accounts-2fa`. Its [Meteor implementation](https://raw.githubusercontent.com/meteor/meteor/devel/packages/accounts-2fa/2fa-server.js)
stores `services.twoFactorAuthentication.secret` and marks a confirmed factor with
`type: 'otp'`. `wlpolicy.pas` guards the current password-only login path: a declared
factor type (including unknown/malformed types) requires a challenge that this path
cannot yet satisfy. Malformed scalar/array factor values and non-string secrets are
refused. Pending activation without a type is allowed when no requirement applies.

The helper follows [WeKan's LDAP password guard](https://github.com/wekan/wekan/blob/main/server/lib/ldapPasswordLoginGuard.js):
`authenticationMethod='ldap'` blocks local-password login when `LDAP_ENABLE='true'`,
unless `LDAP_LOGIN_FALLBACK='true'` or `LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN='true'`.
Other provider labels alone do not forbid an existing real password. Provider-backed
sign-in itself is not implemented by this password route.

`REQUIRE_2FA` follows [WeKan's requirement modes](https://github.com/wekan/wekan/blob/main/models/lib/twoFactorRequirement.js):
`off` (default), `admins` or `all`, trimmed/case-normalized; other values mean off.
Covered password accounts cannot obtain full application access through the present
password-only path. Login lookup, direct token issuance and existing token validation
all enforce it. Issuance also compares the method/services/admin snapshot in the same
SQL statement that inserts the credential, closing policy changes between reads and
write. Observed policy failures delete durable tokens and web context; restoration
cannot revive an already revoked credential.

Native/CLI tests cover pending versus active/malformed factors, LDAP fallback rules,
required-factor modes/admin promotion, password-route denial without token creation,
metadata retention and durable revocation. Live Mongo edits exercise the same lookup
policy without BSON changes. Normal HTTP/secret/crypto/session concurrency tests pass.
HTTP OTP login is implemented below. Enrollment and shared Meteor session integration
remain required before the shared-account task is complete.

## Portable TOTP foundation

`wltotp.pas` implements SHA1 HOTP and TOTP from [RFC 6238](https://www.rfc-editor.org/rfc/rfc6238.html),
using explicit big-endian counter bytes and dynamic truncation. The Meteor profile is
six digits, 30-second steps and up to ten steps of validation drift; eight-digit output
is available for RFC vectors. Base32 is ASCII, case-insensitive, bounded to 1,024 decoded
bytes, and checks canonical padding/unused bits. New enrollment will use fresh 20-byte
secrets; the core does not silently replace existing imported secrets.

`OTPMatch` scans the whole selected window, returns a matching counter and rejects
counters at/below `MinCounter` (use -1 for no previous use). It also refuses a used-counter
collision even if a higher counter in the window produces the same digits. Callers must
consume the result atomically; this pure function does not provide durable replay storage.
Negative timestamps, malformed six-digit codes and windows outside 0–10 fail closed.
Decoded key buffers and working HMAC digests are cleared.

`tests/totp.py` checks published HOTP/TOTP SHA1 vectors and independent Python HMAC,
base32 padding/case and binary secrets, counter/time boundaries, leading zeroes, drift
edges and replay boundaries in normal/checked builds. Atomic token consumption is
implemented below; enrollment remains open.

## Durable one-time-code replay state

`wlreplay.pas` defines `_wl_otp(userId, factorKey, counter)`. Factor identity hashes a
canonical base32 secret with a domain prefix, so case/padding aliases cannot reset
consumption. A new secret gets its own boundary. Replay rows survive token logout and
expiry, and are removed when their user is deleted. The shared adapter owns this table
in its private registry and cleans it through the physical user-deletion hook; native
stores get a checked cleanup trigger when replay storage is initialized.

`LastOTPCounter` distinguishes a new factor (-1) from failed queries and corrupt NULL,
negative or duplicate rows. `EnsureOTPReplay` checks the exact table/cleanup schema.
`OTPReplaySQL` is appended **inside the token transaction** after token/metadata insertion:
it claims only for an existing token belonging to that user, and a stale/duplicate
counter aborts with a constraint error. The caller must roll back the entire transaction
on any failure. It is not an independent authorization operation and does not verify a
password/code; the proof-aware issuer below supplies that authorization.

`tests/replay.py` exercises real linked/CLI backends with sixteen concurrent processes,
exactly one successful counter claim, complete token/metadata rollback, retry after a
forced failure, process restart, aliases, user/factor isolation, logout retention,
missing-token behavior and malformed-state/schema refusal. `ferroot.py` checks replay
storage inside the live shared adapter and user cleanup; TOTP vectors still pass.
No public challenge/enrollment route is enabled by the replay kernel.

## Password and OTP proofs

`AuthenticateAccount` returns an opaque, unit-owned `TWLLoginProof` after password
verification and, for an active OTP factor, matching an unused code. Policy distinguishes
password-only, active OTP, required enrollment and denied accounts. Required enrollment
still denies full access. Proofs retain account/policy snapshots, a credential fingerprint
and the matched OTP; they never retain the plaintext password or leave the process.

`IssueAccountToken` accepts a proof for at most 30 seconds, rereads credentials/policy,
rechecks the code and inserts the token, metadata and replay claim in one transaction.
Any write failure rolls back all three. Successful issuance invalidates the proof.
`CreateAuthenticatedSession` uses this issuer for web context. Factor-bound token
references combine the credential fingerprint and canonical factor identity; web/API
validation checks both without consuming another code. Password-only issuer calls
remain unable to authorize active factors. Observed credential/policy changes revoke
existing tokens, even if the original values are later restored.

`tests/factor.py` checks both SQLite backends, independent Python OTPs, web/API validation,
16 concurrent attempts, proof reuse, metadata/counter rollback and retry, stale snapshots,
factor replacement, required-factor modes and LDAP fallback. `ferroot.py` exercises an
actual shared Argon2 account with an operator secret and active OTP, preserving its BSON.
HTTP login forms and API code routing now use these proofs with the durable attempt
limiter below. Enrollment remains open.

## Durable login attempt reservations

`wlattemp.pas` reserves login attempts in `_wl_attempt` before expensive credential
verification. Windows last 300 seconds from each bucket's first reservation: account
limit 5, socket peer limit 30, tenant limit 300. Successes consume the same allowance as
failures; there is no reset based on whether an account exists or authenticates. All
three counters commit together, or all roll back. The caller must supply trusted server
Unix time and the socket peer, without trusting forwarded headers. This is a local
admission policy, independent of imported Meteor account data.

The table uses hashed account/peer identifiers and belongs to the shared adapter's
private registry. Limits persist across process restarts and adapter reinstall. Backward
clock movement fails closed until time catches up. Successful reservations remove
expired buckets; the tenant cap bounds storage to at most 601 rows. Schema/query/write
failures and invalid/oversized identifiers deny admission. Limits are deliberately fixed
in this first implementation; deployments behind a proxy share that socket peer cap.

`tests/attempt.py` verifies both backends with 16 concurrent processes, account and peer
independence, tenant capacity, window edges, clock rollback, forced write rollback/retry,
cleanup, malformed schema and tenant isolation. `ferroot.py` verifies ownership and
reinstall persistence without changing BSON. Both HTTP login routes now call this limiter
before the proof factory, using server time and the socket peer. Denials return 429 and
`Retry-After: 300`. `tests/otphttp.py` checks actual form/JSON requests, shared route caps,
spoofed forwarded headers, restart persistence and transactional OTP rollback/retry. With
`WELITE_UI=1`, Chromium submits the form and reloads its session with JavaScript disabled
and Cookie headers removed, on both SQLite backends.

## Remaining before the checklist can be checked

- Complete second-factor enrollment, shared Mongo account/index and collection-recreation/auth migration policy; reconcile typed
  custom-field values, legacy dependency forms and SQL conflict behavior.
- Reconcile Meteor session formats and file-store metadata/bytes.
- Activate the adapter for fresh and existing stores without silently creating a separate
  normalized database; adapt cloning/export and finish authentication integration.
- Verify shared-database HTTP/Mongo-wire workflows, including permissions, restart and
  rollback with both Welite SQLite backends.
- Resolve shared database filename/8.3 policy and document target-specific limitations
  from actual tests. Never share a file through aliases with different WAL names.

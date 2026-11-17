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
cascades in the root deletion trigger. Insert and reference-column update checks
inspect the fully projected typed document, so source seeds cannot bypass
validation. A nonnull reference must be a nonempty BSON string, and its matching
parent must have a canonical string ID and valid source metadata. An ObjectId ID
or Regex reference rendered as the same SQL text does not grant a relationship.
Nullable and missing references remain optional, including when no parent is read.

Explicit writes to a declared reference supply string metadata, so assigning the
same text repairs an old Regex field rather than retaining its obsolete type.
Null clearing remains null, and unrelated BSON source fields remain unchanged.
Untouched unsupported references do not become canonical through a seed insert.
These rules implement the SQL model's string reference contract; unsupported
legacy identifier relationships still need a separate migration policy.

Embedded child arrays disappear with their root; they need no separate cascade.
Root cascades verify actual owner-ID and child-reference string schemas and
validate matching source documents before deletion. They leave nonstring BSON
lookalikes unchanged, and nested cascades execute inside the initiating SQL
statement. Cascade triggers are generated after all physical root names are known.
Custom root triggers are restored after owned triggers, preserving their previous
delete ordering through reinstall.

Live tests check every declared root foreign key on insertion and update, including
source-based inserts. A forced failure during checklist-item deletion restores every
collection's SJSON exactly after a board deletion attempt. Successful deletion removes
the board-owned graph while retaining unrelated boards and unconstrained attachment,
activity, user and custom-field records, according to `schema.sql`. User/custom-field
root deletion also removes their embedded child rows. Both SQLite backends pass.

`tests/refsql.py` executes generated SQL with the real projection extension in
normal/checked builds. It covers 48 parent/child TEXT/JSONB combinations, Unicode
and case-sensitive identities, optional references beside malformed unrelated
parent data, explicit repairs, failed-write rollback and owner/child type isolation.
`tests/refkind.py` runs through `tests/ferroot.py` against real Mongo/SQL roots on
both backends, checking ObjectId parents, seeded Regex references, same-text
repairs, preserved Regex/ObjectId children and custom delete-trigger ordering.

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
Collection identity policy is now implemented below; the physical delete trigger
handles document deletion, while source binding handles collection replacement.

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
This remains necessary for older stores or an externally removed physical constraint.
Existing id-bound sessions are not resolved by username and keep their existing
credential binding. Owned physical keys are now described below; Mongo-managed account
index provisioning remains separate work.

Tests verify normal and typed-source duplicates, unchanged stored bytes after denial,
case/NULL behavior, exactly one success among four concurrent SQL insertions, a disabled
Mongo duplicate causing login denial, duplicate preflight refusal and repair/reinstall
recovery on both backends. The shared lookup is exercised through fresh auth harness
processes, and both HTTP application regression suites pass. Shared Meteor account
formats and index policy still need integration before normal server activation.

## Physical model unique keys

`UniqueIndexScript` in `wluniq.pas` installs private SQLite unique expression indexes
on physical SJSON documents for the model's declared keys (currently username). BINARY
comparison and SQL NULL-distinct semantics match the canonical schema and existing
view checks. Direct Mongo insert/update operations therefore cannot bypass those model
constraints. Missing and explicit-null usernames remain separate documents with no
non-null unique value; differently cased names remain distinct.

Each index is registered with its physical table, key specification and version in
`_wl_models`. Installation accepts an existing index only with matching ownership and
exact DDL, repairs a missing owned index, and refuses an altered or unowned object.
Fresh creation and owner registration participate in the complete adapter transaction.
Duplicate preflight still refuses older inconsistent stores without rewriting documents.
Tests deliberately remove an owned index to retain ambiguous-login/repair coverage.

These constraints leave FerretDB-managed `settings.indexes` and Mongo `listIndexes`
unchanged. At inspected FerretDB revision `984be0e8`, createIndexes ignores `sparse`,
and registry index operations use cached settings. Writing managed index metadata
behind that cache would risk later overwrites; cache coordination remains required.

[Meteor's current account setup](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_server.js)
requests sparse unique username, email-address and resume-token indexes plus timestamp
indexes. Those are still a separate compatibility gate. In particular,
[MongoDB sparse indexes](https://www.mongodb.com/docs/manual/core/index-sparse/) include
explicit nulls and skip missing fields: the private SQL NULL-distinct invariant does
not replace that behavior. Email/resume-token arrays also require multikey enforcement.
FerretDB's insert constraint path reports 11000; full duplicate-update error mapping
remains part of Mongo index parity.

`tests/ferroot.py` verifies both backends against actual Mongo duplicate inserts and
updates, eight mixed SQL/Mongo writers with exactly one success, case/NULL/missing
values, private ownership/alteration refusal, removed-index repair, unchanged managed
index metadata and fresh FerretDB startup. Existing duplicate preflight and all shared
account/source/enrollment scenarios remain covered.

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
HTTP OTP login and enrollment are implemented below. Shared Meteor session integration
remains required before the shared-account task is complete.

## Portable TOTP foundation

`wltotp.pas` implements SHA1 HOTP and TOTP from [RFC 6238](https://www.rfc-editor.org/rfc/rfc6238.html),
using explicit big-endian counter bytes and dynamic truncation. The Meteor profile is
six digits, 30-second steps and up to ten steps of validation drift; eight-digit output
is available for RFC vectors. Base32 is ASCII, case-insensitive, bounded to 1,024 decoded
bytes, and checks canonical padding/unused bits. New enrollment uses fresh 20-byte
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
implemented below, including HTTP enrollment.

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
limiter below. Enrollment is described below.

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

## Limited OTP enrollment core

`wlenroll.pas` owns `TWLEnrollProof`, a separate type from application login proofs.
`AuthenticateEnrollment` verifies an enabled, unambiguous account's password and allows
only no-factor or required-enrollment policy. Active/unknown/malformed factors cannot
be replaced with a password alone. Proofs retain database/credential/policy snapshots,
never plaintext passwords, expire after 30 seconds and start setup only once successfully.

`StartOTPEnrollment` creates an independent random bearer token and a fresh 20-byte
base32 secret in private `_wl_enrol` storage, one pending setup per user. The returned
token is hashed with the database binding; it is not a login credential. Setup expires
after five minutes and binds to a server-derived client digest. It leaves shared account
services untouched, replaces older pending setup and removes expired records on a later
successful start. Native and physical shared-user deletion remove pending secrets.

`ConfirmOTPEnrollment` checks token/client/time, the current credential fingerprint and
account snapshot, and an unused OTP. One transaction activates the factor, consumes the
counter, deletes pending setup and revokes all local web/API tokens and metadata. A
constraint assertion makes a stale/competing setup abort; another assertion catches user
triggers that ignore activation. Other factor metadata and unknown account fields/types
are retained. Successful activation grants no application session: sign in with a fresh
code, since the confirmation code is already consumed. Shared Meteor resume-token
revocation is now connected through the all-user revocation helper below.

`tests/enroll.py` exercises both backends, including required enrollment, private token
isolation, 20-byte secrets, replacement, binding/expiry, stale snapshots, forced/ignored
activation rollback, 16 concurrent confirmations and normal login afterward. `ferroot.py`
checks actual shared BSON, adapter reinstall and physical deletion cleanup. Shared JSON
TEXT columns explicitly strip SQLite's expression subtype before constructing patch JSON;
this supports `json_set` without confusing an object with the patcher's text value.
HTTP `/two-factor/setup` and POST `/two-factor/confirm` now use the core without
JavaScript or cookies. Setup verifies the password and displays a manual authenticator
secret; confirmation retains only a hidden bearer token. Both routes send no-store and
no-referrer headers and use a digest of socket peer/user agent for binding. Both reserve
attempts before authentication/code matching. Confirmation derives its admission account
from matching pending state, ignoring posted usernames. Invalid tokens still consume
peer/tenant allowances. Setup tokens and secrets never enter navigation URLs.

Required-factor registration creates the account, then links to setup without granting
application access. Confirmation shows instructions to sign in with a fresh code.
`tests/enrhttp.py` verifies required registration, admission identity/caps, binding,
expiry/replacement, restart and rollback/retry on both backends. With `WELITE_UI=1`,
Chromium completes setup, confirmation and sign-in with JavaScript disabled and Cookie
headers removed. Existing HTTP authorization/credential tests also cover both backends.

## Authentication source identity

`wlautsrc.pas` binds private authentication to the physical users table and its FerretDB
collection UUID in owned `_wl_authsrc` storage. User IDs and password fingerprints alone
do not identify a collection: Mongo can drop/recreate users and reuse both. Account
lookup, token validation and login/enrollment proof use now check the source record
against live collection metadata and the model registry. Proofs retain the observed
source condition; token insertion, pending setup creation and OTP activation check it
inside their SQL mutation as well. Token validation that observes a stale source deletes
that credential; web validation also removes its in-memory context.

Adapter reinstall with the same source preserves private state. A known new source
atomically clears local tokens/authmeta, pending enrollment and the old OTP ledger,
then records the new table/UUID. Before reinstall, runtime guards deny the replacement
source. Older installed adapters without a source record revoke local tokens/pending
setup on their first upgrade, retaining the unproven replay boundary conservatively.
Attempt allowances are tenant-scoped and survive these transitions. Native normalized
stores continue to authenticate without a shared-source marker; a marker beside a
native users table is not treated as an automatic migration.

Missing, non-string or wrong-length UUID metadata aborts source binding, including the
preceding cleanup and adapter changes. The source table follows the same exact-schema
and ownership checks as other private tables. This binds local credentials only; shared
Meteor resume-token/index formats and normalized-store migration remain separate work.

`tests/ferroot.py` exercises actual Mongo drop/recreate with reused account IDs and
credentials, refusal before reinstall, source rebinding, pending/OTP/token cleanup,
normal reinstall preservation, stale proof denial, old-adapter backfill and malformed
metadata rollback on both backends. Native factor/enrollment/session and public HTTP
regressions cover the no-marker path.

## Typed Meteor resume-token kernel

`wlresume.pas` implements `MeteorTokenHash`: SHA256 of raw UTF-8 token bytes encoded as
standard padded base64, matching
[Meteor's token hashing](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_server.js).
It accepts 1–4096 bytes and remains separate from the tenant-scoped private digest.
Hash-taking commands require canonical 44-character digests decoding to 32 bytes.

`ResumeDocument` operates on the actual SJSON account document. `append` takes
`hashedToken` and integer millisecond `when`, adds a record with a BSON Date and refuses
a duplicate hash. `remove` removes every matching hashed record; absent paths are left
absent. `clear` sets the token array to empty, including an explicitly malformed token
value, without replacing parent fields. Existing non-object parent containers fail
closed. New records never contain raw tokens; existing legacy plain records and unknown
fields remain until targeted legacy conversion or explicit clearing.

The editor copies complete original item schemas into an explicit array hint, deleting
schema items alongside removed records. This retains shifted BSON dates, binary/long
subtypes and other unknown metadata instead of guessing their types from position.
Append creates the new date schema explicitly. `wl_resume(previous, command)` exposes
the same pure operation through linked SQLite and the CLI host-API extension. It neither
reads external state nor authorizes the caller. Mutating a physical document with this
function in its UPDATE expression lets SQLite serialize concurrent writers without a
read/replace lost update.

`tests/resume.py` checks independent Python hash vectors, canonical digest/command/date
validation, signed millisecond dates, malformed parent refusal, TEXT/JSONB writes,
16 distinct concurrent appends and one winner for duplicate hashes on both backends.
`ferroot.py` checks actual stored BSON before/after append, removal with shifted legacy
siblings and duplicate hashes, rollback and clearing, including dates, binary, long and
precision-sensitive double values. Comparisons start from BSON read after the backend's
original insert, so source insertion normalization is not attributed to a later edit.

This is a storage prerequisite. HTTP login still issues the existing private credentials;
shared resume issuance/validation, expiry, logout/revocation, legacy token conversion,
source/policy binding and Mongo token-index parity remain to be integrated and tested.

## Resume validity and expiry

`CheckResumeToken` takes a canonical hash, trusted current milliseconds and an explicit
positive lifetime. It distinguishes absent, valid, expired and invalid records, requires
one matching hashed record and returns timestamps only on success. It accepts BSON
Date and legacy int/long/double timestamps; numeric fractions use JavaScript Date
truncation. Missing/string/nonfinite/out-of-range timestamps and duplicate hashes fail
closed. A future stamp remains governed by the supplied lifetime, matching the source
comparison rather than adding a different clock policy. Raw legacy tokens still require
conversion and are not accepted through this hashed-record checker.

[Meteor's resume handler and expiry sweep](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_server.js)
use different boundaries: authentication expires at equality, while the sweep removes
records strictly older than its cutoff. `wl_rescheck(document, hash, nowMs, lifetimeMs)`
returns the checker state; `wl_resume` now accepts `{"op":"expire","before":cutoffMs}`.
Pruning compares the original numeric value (including fractions), removes Date/numeric
records strictly before the cutoff and retains unsupported timestamps. Schema entries
move with their retained records. Cutoffs and validation arithmetic stay within the
[JavaScript Date semantics used by accounts-common](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_common.js).

`tests/resume.py` verifies Date/legacy boundaries, fractional truncation versus pruning,
future stamps, duplicate ambiguity, positive lifetime requirements and Date limits on
both TEXT/JSONB backends. `ferroot.py` checks validity and pruning against live Mongo
records while comparing complete stored BSON. These are pure primitives; application
issuance/authorization, configured lifetime policy, expiry scheduling and revocation
still need integration. Browser sessions remain private to retain client binding.

## Shared all-user revocation

`wlrevoke.pas` builds a fragment for the caller's transaction. Administrator disabling
and OTP confirmation both use it after validating the account action/proof. On a shared
store, it clears the selected user's `services.resume.loginTokens` with the typed
kernel, then deletes local credentials/authmeta and pending enrollment. Existing legacy
plain records are cleared too. Other BSON fields/types, other accounts and OTP replay
boundaries remain intact. Missing resume paths are left absent.

The fragment checks its captured collection identity inside the transaction and asserts
that a present shared token path became an empty array. A source switch or ignored
physical update cannot silently delete local state while leaving shared bearers alive.
The owning action rolls back the complete transaction on any error, including later
metadata deletion failures. Re-enabling an account restores none of the deleted state.
Native stores use the same local cleanup without introducing shared records.

`wlenmeta.pas` owns the pending enrollment DDL used by setup, the shared adapter and
revocation. Creation participates in the revocation transaction so concurrent first-time
setup cannot evade cleanup between a schema probe and the write. Incompatible existing
pending storage is refused rather than adopted.

`tests/ferroot.py` exercises actual shared enrollment and disabling on both backends,
including legacy/hashed tokens, pending setup, another account's surviving credentials,
forced and ignored updates, failure after shared clearing, source switches and re-enable.
`tests/revoke.lpr` executes the same fragment used by the HTTP administrator action;
native `admin.py` verifies the real route. Shared bearer issuance/authorization,
per-token revocation, legacy conversion and scheduled expiry remain to be connected.

## Targeted shared revocation

`RevokeTokenSQL` uses the same source-guarded edit/assertion path as all-user revocation,
but selects one account and bearer. The typed `revoke` command derives the hash from
its raw token and removes every matching hashed or legacy plain record. Other records,
unknown BSON types, pending setup and replay state remain intact. Its local deletion
also requires the account ID and tenant-scoped key. Token JSON escaping protects the
SQL text from control bytes; SQL comparisons extract the raw selector from that JSON.

The private hash now lives in `wlcrypt.TenantTokenHash`, with the same domain prefix,
database path and raw-token input as before. `wlauth` delegates to it and uses a
transactional stored-token revoker when validation observes credential/policy failure,
expiry, disabled/invalid stored identity or an invalid source. For a replaced source,
cleanup removes local state only. Browser IP/user-agent mismatch still refuses the
request without deleting another client's session. Database/metadata failure rolls back
targeted clearing; validation still refuses access.

`tests/resume.py` checks the typed dual-form removal. `ferroot.py` tests hashed/plain
fallback removal, retained sibling sessions, ignored updates, failure after shared
clearing, exact BSON preservation, missing-token no-op, credential restoration and
local expiry through the real validators on both backends. Native session and HTTP
regressions cover client/tenant and account behavior. Shared issuance/authorization,
scheduled expiry and legacy conversion remain separate integration work.

## Paired shared API bearers

`wlshared.pas` connects API issuance to the typed resume kernel. Shared-store API token,
authmeta, optional OTP claim and Meteor `{hashedToken, when: BSON Date}` append commit
together. Both password-only and OTP proof issuers use the fragment. Global checks refuse
an existing hash or legacy raw bearer in any account. Source/settings snapshots and a
post-append assertion make collisions or ignored writes roll back the complete issuance,
including an OTP claim. Browser credentials remain private so another application cannot
bypass WeLite's client binding by treating them as unrestricted resume bearers.

API validation requires the existing tenant/credential/factor metadata plus a single
matching shared account and a valid shared timestamp/lifetime. Shared removal, expiry or
cross-account ambiguity triggers targeted cleanup. Restoring a source record does not
restore deleted local metadata. Previously unseen Meteor-issued tokens can now be adopted through the guarded path
below; recorded local digests cannot be automatically re-adopted after revocation.
Older private-only API tokens on a shared store require a fresh login after this update.

Lifetime comes from the single actual Settings document's
`loginOptions.loginExpirationInDays`, then `ACCOUNTS_COMMON_LOGIN_EXPIRATION_IN_DAYS`,
then 90 days (zero also selects the default). Positive decimal/scientific days through
36500 are supported, including fractional and submillisecond durations. Invalid or
ambiguous configuration fails closed. Issuers must request this lifetime;
REST responses read the exact committed expiry. Apply the same deployment fallback to
both applications and restart Meteor after changing its startup-applied lifetime.

Shared authentication resolves stored `loginOptions.require2fa`,
`loginOptions.passwordLoginEnabled`, `ldap.enabled`, `ldap.loginFallback` and
`ldap.migrationAllowPasswordLogin` before their deployment defaults. Null and empty
values fall back; stored boolean false remains an explicit override. The portable
factor kernel receives these values explicitly without process-environment mutation.
Lookup, proofs, token issuance/validation, enrollment and registration use this policy.
Proofs and guarded writes capture the source and Settings snapshot from the decision;
changes require a fresh proof. Password-disabled registration creates no account, and
observed disabling durably revokes an existing credential. Native-store policy behavior
is preserved. Enabled SQRL-only identities also prevent shared password issuance.
Broader account configuration remains a compatibility gate.

`ferroot.py` tests actual paired password/Argon2-secret/OTP issuance, BSON Date output,
Mongo removal/expiry, restored-record denial, cross-account ambiguity, collision rollback
with OTP retry, ignored-append rollback, stored lifetime precedence, stored MFA/LDAP overrides, null fallback, stale-policy
proof refusal, password disable/restore and SQRL-only refusal on both backends. Existing native HTTP/hash/OTP/enrollment tests
cover private-store behavior. A full Meteor DDP/HTTP application round trip, broader resume-policy parity,
scheduled expiry and Mongo-managed token indexes remain outstanding.

## Fractional expiry kernel

`wllife.pas` parses decimal/scientific positive days through 36500, with empty/zero
selecting 90 days, independently of the host decimal separator. Negative, nonfinite,
nondecimal and out-of-range values are refused. Its expiry operation uses binary64
addition followed by Date-range validation and truncation, matching
[Meteor accounts-base](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_common.js)
`_getTokenLifetimeMs` and `_tokenExpiration`. In particular, truncating the duration
before adding it to a negative timestamp gives a different result and is avoided.
Resume validation uses this Date kernel. `lifetime.py` checks it against executable
Node.js Number/Date expressions in normal and checked Pascal builds.

Shared configuration, password/OTP issuance and bearer checks now use this kernel.
`ApiTokenLifetime` retains its seconds-valued caller contract as a rounded-up request
marker; shared expiry always uses the original binary64 milliseconds. The expiry reader
returns a source/settings SQL condition alongside the duration, and both issuers require
that condition when inserting. A settings change after computation cannot commit an
expiry calculated from the earlier configuration. Local ISO expiry keeps milliseconds;
the REST response reads that exact committed value. SQL `wl_rescheck` also accepts
fractional millisecond lifetimes. Native-store/browser durations are unchanged.

`ferroot.py` compares live BSON issue timestamps and local expiry against Node.js for
fractional days/seconds/submilliseconds, exercises fractional OTP issuance and null
fallback to a fractional environment value, and rejects invalid/nonfinite settings.
`resume.py` verifies SQL equality-at-expiry with fractional milliseconds on both backends.

## Typed legacy resume conversion

`wl_resume(document, '{"op":"convert","token":"raw-bearer"}')` is an atomic
storage edit. It replaces a single old raw record's token field with the canonical
SHA256/base64 hash, retaining its original `when`, BSON type and unknown fields.
Sibling records and metadata remain intact. Missing records are not created. If a
single hashed record already exists, its timestamp wins and matching raw records are
removed. Duplicate hashes, multiple raw-only candidates, matching hybrid entries and
invalid/missing timestamps are refused. Concurrent callers cannot renew a timestamp
or produce duplicate hash records.

This follows [Meteor's legacy resume conversion](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_server.js)
in preserving issue time and preferring an existing hash. The SQL edit makes conversion
atomic, retains extra source fields, and rejects ambiguous source data. It performs no
authorization and can convert an expired record; callers must check expiry and policy
before accepting credentials. The adopter below adds source/settings and cross-account
guards plus atomic local authorization metadata. Conversion alone does not make an
arbitrary Meteor bearer valid in WeLite.

`resume.py` verifies TEXT/JSONB concurrency, legacy numeric fractions, idempotence,
existing-hash precedence, malformed/ambiguous refusal and rollback. `ferroot.py` checks
concurrent conversion against actual FerretDB with exact BSON Date/Long/unknown/sibling
preservation on linked/CLI SQLite.

## Durable bearer history before adoption

The owned private `_wl_seen` table stores the local tenant-scoped token digest, never
the raw bearer. Credential inserts, digest changes and deletions record history in the
same transaction; digest changes retain both values. Trigger assertions refuse ignored
history writes. Installation backfills existing token rows before source cleanup and
asserts coverage, so a failed/ignored backfill rolls back installation.

History survives token/account deletion, source UUID replacement and legacy source
rebinding. This conservative record is deliberately retained: automatic adoption denies
a missing local credential with recorded history instead of recreating it from a
restored shared record. It cannot reconstruct credentials deleted before this upgrade,
and unpresented Meteor-only credentials have no local history. No
history-only lookup authorizes a bearer. The adopter below combines history checks with
source/account/settings snapshots, cross-account ambiguity and original expiry, then
creates local metadata atomically with any legacy conversion.
Native-store private schema and browser session behavior are unchanged.

`ferroot.py` tests backfill and ignored-backfill refusal, ignored issuance-history writes,
SQL digest updates/deletion, revocation retention, reinstall and source migrations with
actual FerretDB on both SQLite backends.

## Existing shared bearer adoption

API validation can adopt a previously unseen Meteor hashed or legacy raw bearer.
The candidate must belong to exactly one shared account and pass typed expiry using
its original `when` and current configured lifetime. Duplicate hash/raw-only records,
invalid timestamps, disabled accounts and denied/required-factor policies are refused.
The same current credential/optional OTP factor reference used by co-issued credentials
is captured at adoption. An existing authenticated resume token needs no fresh OTP claim.

Before committing, the adopter rechecks source UUID/table, complete account document,
Settings/policy snapshots, the global matching-account count and absence of local token,
metadata and seen digest. It atomically creates local authorization and history and
converts any legacy raw record. Local-row and resulting-document assertions catch
ignored writes; errors roll back conversion, token, metadata and history together.
Concurrent validators can observe one committed adoption. Subsequent validation keeps
normal shared membership/expiry, credential/factor, tenant and observed-revocation checks.
Restoring a revoked shared record cannot recreate a locally seen credential.

This still uses the conservative resolved account policy: broader Meteor resume-policy
parity (including non-password/deployment restrictions) remains to be reconciled. A
storage record cannot establish history for credentials removed before the history
upgrade. Shared HTTP activation and full Meteor application round trips remain gated.
`ferroot.py` verifies concurrency, exact original dates/BSON, hash/legacy paths, ignored
local/shared writes and retry, expiry, duplicate ownership, disabled accounts, MFA resume
without OTP consumption, credential changes and refusal after shared restoration.

## Durable shared expiry sweep

`SweepSharedTokens(Db, NowMs)` in `wlsweep.pas` performs due maintenance on a shared
store. Owned private `_wl_sweep` state starts due and retains the last successful time
across reinstall/source rebinding. Calls less than ten minutes apart are successful
no-ops; backwards clocks, invalid source identity and invalid configuration refuse work.
The caller supplies nonnegative UTC epoch milliseconds.

The cutoff follows [Meteor accounts-base expiry](https://github.com/meteor/meteor/blob/devel/packages/accounts-base/accounts_server.js):
subtract the current binary64 lifetime from the clock, construct the Date cutoff by
truncation, and remove records strictly older than that cutoff. This intentionally
keeps equality-at-cutoff records until a later sweep; authentication already rejects
expiry equality independently. Date and legacy numeric fractions retain their respective
comparison behavior. Unsupported timestamps are retained without becoming valid bearers.

A transaction checks the source/settings and previous checkpoint, advances the durable
time, edits every actual shared users document with an array of resume records, then
asserts no further expiry edit would change a document. Checkpoint and source/settings
assertions also catch ignored writes. Failed/ignored updates and stale concurrent claims
roll back all account edits and the checkpoint. Typed edits preserve retained BSON and
unknowns; bearer history is untouched. `ferroot.py` covers failure/retry, ignored clock
writes, concurrent callers, cadence, reinstall, stale source and fractional cutoffs
against Node.js on linked/CLI SQLite.

The background worker below calls this kernel for registered stores. Local credential
cleanup, discovery before first tenant access and shared-store activation/application
observer behavior still need integration. No Meteor connection-close behavior is claimed
by the database sweep alone.

## Background maintenance lifecycle

`wlmaint.pas` owns a worker with either root-based discovery or a locked, deduplicated
explicit-path set. Registration wakes it; otherwise it polls once a minute and lets the
durable ten-minute sweep checkpoint decide whether work is due. Each pass opens and closes its own connection;
request/cached handles stay with the caller. Missing files are skipped, supported legacy
stores use their own cleanup path, and a failed store does not stop other stores. An atomic
failed-pass counter permits observing retry behavior. Failure leaves the durable sweep
checkpoint unchanged, so later passes retry.

The HTTP run loop starts maintenance and stops it in a `finally` block. Tenant open
registers shared stores for both cached/new handles; unsupported registration cannot
break a request. Without a data root, the explicit path set is per process. With a data root, each pass
refreshes the registry-based set described below. Eligible stores are maintained during
idle periods without an HTTP request. Stopping signals the wait event, joins
the worker after its current database operation and releases worker-owned state.

`ferroot.py` runs the actual worker on both backends. It observes an injected failed
sweep before allowing recovery, then checks idle cleanup, another due pass, exact BSON,
missing/native-store isolation and a clean stop. `enrhttp.py` covers HTTP startup and
registration/enrollment regressions on linked/CLI SQLite.

Actual shared-store HTTP activation, process-signal lifecycle
and full Meteor observer/application workflows remain explicit integration work. The
worker does not resolve the shared filename/sidecar policy or activate the adapter.

## Startup and refreshed tenant discovery

The HTTP worker receives the configured `WELITE_DATA` root. `wldisc.pas` finds existing
`local/files/db/wekan.db`, `admin/files/db/wekan.db` and enabled canonical-domain files.
It reads the admin registry using its own connection and joins `domains` to `tenantdirs`.
Only valid canonical hosts and numeric keys 1–268435455 qualify; domain paths use the
same `d` plus seven hexadecimal digits as tenant routing. Host strings never become
filesystem paths. Missing files, disabled domains, orphan mappings and invalid hosts are
skipped; discovery does not create tenant directories or apply schemas.

Every polling pass refreshes this set, so enabled/new domains need no first HTTP request.
Registry changes apply to subsequent passes; a pass already in progress may finish.
When a data root is configured, this discovered set is authoritative and request-time
registration wakes a refresh. Without a root, standalone explicit-path registration
retains its prior behavior. A registry read failure is counted/retried while existing
local/admin candidates remain available. Native and registry-only databases without a
shared users view are skipped without a false sweep failure.

`tests/discov.py`, invoked by `ferroot.py`, uses independent SQLite backups of actual
shared source data under the managed directory layout. It verifies no-request startup
cleanup, dynamic enabling/registration, exclusion of disabled/orphan/invalid mappings,
missing-directory preservation, broken-registry detection/recovery and clean shutdown
on both backends. These are separate
databases, never `.db`/`.sqlite` aliases. Existing live tests cover the shared sweep itself;
this discovery test does not claim filename migration, cloned-auth compatibility or a
full Meteor observer round trip. `enrhttp.py` covers HTTP startup and enrollment regressions.

## Source-bound bearer links for local cleanup

Owned private `_wl_pair` rows contain the local digest, user ID, optional Meteor digest
and source UUID. These distinct digests cannot be derived from one another. Shared
issuance/adoption writes the link in its existing transaction and asserts coverage;
ignored writes roll back token/metadata/shared edits and any OTP consumption.

Installation backfills older active API identity with a null shared hash, preserving
known links and refusing incomplete backfill. It never guesses a shared digest from
issue timestamps. After normal local/shared validation, a presented raw bearer can fill
an unknown link. A link-write failure denies that access without declaring the underlying
credential invalid. Known links take the read-only path. Active native/browser token formats are unchanged.

Links survive local credential deletion. A subsequent raw request can therefore revoke
the corresponding shared hash/legacy form for the recorded user even when its local
row is gone. Source UUID matching prevents this fallback from touching a replacement
collection, and source rebinding clears obsolete links atomically. An ignored obsolete-
link deletion aborts the rebinding transaction. Seen digests continue
to prevent automatic re-adoption. This does not add authorization for a deleted token.

`ferroot.py` covers known links, ignored insert/backfill rollback, null-hash migration,
lazy enrichment, adoption rollback, targeted revocation after local deletion, unchanged
known links on reinstall and source isolation. The sweep below now uses these links for
private cleanup and defines the conservative null-hash migration behavior.

## Atomic private expiry cleanup in shared stores

The due sweep now removes expired private `login_tokens` rows and their `authmeta`, plus
orphan metadata, in the same transaction as shared age pruning and the durable checkpoint.
Private deadline equality is expired (`expiresAt <= Now`); shared age pruning deliberately
retains equality at its Date cutoff. A local deadline can precede the currently configured
Meteor lifetime, so known links explicitly retire only that expired credential's shared
records before deleting its private row.

`wl_resume` accepts `{"op":"retire","hashes":[...]}` with canonical Meteor digests.
It removes matching hashed records and legacy raw records whose computed digest matches,
preserving unrelated entries and their complete BSON schemas. SQLite `wl_methash` computes
the same digest for source matching; unsupported/empty inputs return an empty string that
cannot match a canonical digest. Nested type guards preserve scalar, null and unsupported
source siblings. Retirement commands contain only distinct hashes actually present in the
current source array, not an unbounded private history. The private source/user/hash index
supports scoped lookup.

Before deletion, missing links retain account/source identity with a null hash. This also
covers old web/orphan private rows without publishing them as Meteor credentials. Seen
history and identity links survive deletion. A legacy null-hash record cannot be mapped
by guessing timestamps: its shared record follows Meteor's current age expiry until a
presented raw bearer permits targeted revocation through retained identity. The deleted
local credential remains denied and cannot be re-adopted; healthy siblings stay valid.

Cleanup assertions run before deleting the rows needed to prove each stage. Ignored link,
shared, metadata, token or history writes roll back all effects and the due checkpoint.
OTP replay is deliberately retained; pending enrollment cleanup is described below. `tests/expiry.py`,
called by `ferroot.py`, covers inclusive deadlines, hash/raw/duplicate forms, scalar/BSON
preservation, orphan rows, five ignored-write stages, retry, sibling/account isolation,
null-hash behavior and a real idle-worker cleanup on linked/CLI SQLite. `resume.py` checks
digest-set validation and SQLite hash output against Python. Normalized legacy-store cleanup is described below.

## Expired pending enrollment maintenance

The same shared-store sweep transaction deletes `_wl_enrol` rows whose seconds-based
`expires` is less than or equal to the sweep clock's whole UTC seconds. This matches
confirmation's requirement that `expires > Now`. An assertion checks that no expired
pending row survives; an ignored deletion rolls back all credential/source cleanup and
the checkpoint as well. The ten-minute maintenance cadence bounds cleanup opportunities,
while confirmation already refuses an expired setup independently of maintenance.

Unexpired pending records survive unchanged. Cleanup never activates a factor, publishes
a pending secret or clears OTP replay state. `expiry.py` creates real pending enrollment
through the proof/setup flow, checks equality and retained setup, injects an ignored
pending deletion after earlier cleanup stages, then checks actual idle-worker expiry.
Both SQLite backends run. `enroll.py` retains proof, binding, expiry, activation/replay
and rollback coverage. Normalized legacy stores use the separate path below.

## Normalized legacy-store maintenance

`SweepLegacyTokens` handles the existing normalized `users`/`login_tokens` layout without
converting credentials or introducing shared records. It checks the four expected text
columns and single token primary key; optional `authmeta` needs its expected text fields,
and optional pending/checkpoint tables must match known layouts. Minimal registry/stores
without a credential table are skipped. A FerretDB collection marker or shared-source
binding prevents use of this path.

The sweep captures inspected schema definitions and optional-table absence in transaction
guards. It creates only the private `_wl_sweep` checkpoint when needed, then applies the
same ten-minute cadence and backwards-clock refusal. Expired tokens, credential/orphan
metadata and pending setup are removed at inclusive deadlines; valid tokens and replay
state survive. It does not create missing optional metadata, `_wl_pair`, `_wl_seen` or
shared-source tables. A checkpoint with an incompatible layout is refused.

Assertions catch ignored checkpoint seeds/updates and cleanup writes. Native SQLite
`RAISE` is trigger-only, so lazy `CASE` with the integer-overflow failure of
`abs(-9223372036854775808)` supplies statement assertions outside triggers. A failed or
stale concurrent claim rolls back checkpoint/schema creation and every cleanup change.
The worker dispatches by users table/view and registration wakes both supported layouts.

`tests/lsweep.py` runs linked/CLI tests with actual password issuance and pending setup:
equality, optional tables, three ignored cleanup stages, ignored checkpoint seed/update,
concurrent calls, clock boundaries, unsupported/mixed schema refusal, replay preservation
and real idle cleanup. HTTP admin/permissions and enrollment suites check the active
legacy application. This maintenance support does not replace the offline normalized-to-
shared authentication migration policy or activate shared stores automatically.

## Shared custom-field value writes

The maintained WeKan card schema accepts String, Number, Boolean, Date and
arrays of strings (`models/cards.js`, `customFields.$.value`). The shared
`card_custom_field_values` view reads the corresponding embedded values directly.
An UPDATE now consults the existing SJSON value schema rather than converting
all supplied values to text:

- Strings remain literal text, including strings that resemble JSON or booleans.
- Numbers accept finite SQL numbers or numeric strings. Existing BSON int/long/
  double metadata is retained when compatible; numeric widening remains allowed.
- Booleans accept 0/1 or true/false. Dates accept integer epoch milliseconds or
  ISO timestamps and retain BSON Date metadata.
- Existing string arrays accept JSON array text with string elements only. Empty
  arrays, Unicode and escaped strings are supported. Malformed JSON, extra wrapper
  members and non-string elements fail the statement.

Unchanged values retain their exact source metadata, including unsupported BSON
values. Attempts to replace unsupported BSON value types fail. Other row/root
properties and sibling values survive edits; a bad value aborts the whole SQL
statement. Assigned null/missing values use a usable live definition for the first
typed edit. Legacy untyped values with no definition retain the ordinary text
write fallback; an existing unsupported/ambiguous definition is refused.

`tests/custval.py`, invoked by the real-server `tests/ferroot.py` suite, compares
Mongo BSON before/after SQL edits on both backends, including integers above 2^53,
negative dates, arrays, invalid values, no-op writes and multi-row rollback.

New SQL INSERT values use the current matching `custom_fields.type` definition.
Text/dropdown/stringtemplate stay strings; number/currency become finite numbers;
checkbox becomes Boolean; date becomes BSON Date; dropdownMultiSelect becomes an
array of strings. Date insertion supplies the complete inferred array schema with
an explicit Date hint on the appended row, preserving all sibling metadata.
The field definition is read within the write statement, including definitions
changed through Mongo after adapter installation. Missing, ambiguous or unsupported
field definitions fail instead of guessing a type. Source-only legacy values may
still be updated by their existing BSON type without requiring a definition.

`tests/custins.py` adds real-server insertion coverage for every supported field
type, definition changes, unknown siblings, missing/empty source arrays, invalid
values, duplicate rows and multi-row rollback on both backends.

WeKan's `CustomFields.addToAllCards` and `Cards.assignCustomField` initialize
assigned values as null (`models/customFields.js` and `models/cards.js`). UPDATE
now reads definition count/type inside the statement and uses that definition
when the previous value is null or absent. Non-null typed values continue following
their stored BSON schema. Date hints select the edited row's index rather than the
last array element, preserving unrelated typed properties and siblings.
`tests/custnull.py`, run by the real-server suite, checks every supported type from
null/missing states, exact BSON, first-edit refusal, current-definition changes,
legacy fallback and multi-row rollback on both backends. Shared HTTP fixtures also
begin number/checkbox/date/multi-select fields in the actual assigned-null state.

The custom-value POST endpoint now sends JSON scalars/string-array text or form
strings to that SQL contract and performs UPDATE plus INSERT-if-absent in one
transaction. It does not delete/recreate an existing embedded row. A storage error
rolls back the transaction and returns HTTP 500; malformed/ambiguous value bodies
return HTTP 400. Successful IDs use proper JSON escaping. `tests/custapi.py`, run
by native `tests/admin.py` and real shared `tests/shrhttp.py`, checks repeated
writes, typed shared values, literal Unicode text, quoted IDs, missing/foreign
fields and injected AFTER-write failures without partial rows or BSON changes.

Shared card GET responses now read the matching owned card collection directly,
validate the complete SJSON and serialize the declared custom-value kinds as JSON
values. Strings stay literal, numbers/booleans/arrays retain JSON types, null stays
null and absent values remain absent. Root/row-private properties and `$s` metadata
are omitted. Scalar BSON kinds outside the declared model retain their plain SJSON
scalar representation. Corrupt metadata returns a complete HTTP 500 response,
without source mutations or a partial array.

BSON Date values follow `JSON.stringify(Date)`: UTC millisecond strings, year zero,
signed six-digit extended years, and null outside TimeClip. Non-finite doubles
become null and negative zero becomes zero. Integer Gregorian arithmetic avoids
host timezone/calendar limits. `tests/cfjson.py` compares normal and checked builds
with 177 actual Node Date outputs; `tests/custapi.py` covers live source values,
full-range dates, metadata omission, read-only GET and corrupt-source HTTP errors.
All eight Windows x86/x64 linked/CLI disk/embedded cross-build variants also pass
compilation and PE header/import inspection; platform runtime acceptance remains
a separate gate.

Explicit type changes, normalized-store typed migration/validation and selection
clone/export compatibility still need a coordinated contract. A shared INSERT
requires a usable definition; the independent normalized table still stores TEXT
and its GET responses retain the existing text contract pending typed migration.
The pinned FPC router copies raw captured route values into `Request.RouteParams`.
API entry now percent-decodes all declared identifier keys once before tenant,
authentication and parent checks. It preserves literal plus signs, validates strict
UTF-8 and rejects malformed escapes/control bytes with HTTP 400. All values are
staged before assignment; a private route-state marker prevents double decoding
and cannot be supplied through query fields. Decoded slash characters remain inside
the already-captured ID and do not cause another routing pass. Bodies and query
fields retain their existing decoding rules.

`tests/pathid.py` covers every API route key, malformed inputs, idempotence and
atomic normalization in normal/checked builds. `tests/pathhttp.py`, called by native
and shared HTTP suites, verifies Unicode/space/plus/percent/slash IDs, explicitly
escaped user IDs, member/assignee routes and foreign-parent refusal without data
changes. The custom-value HTTP suite again uses a quoted Unicode card ID through
its normally encoded URL. This closes the recorded encoded-ID failure; the typed
migration and clone/export requirements above remain open.

## Custom-field definition creation

The definition POST endpoint now validates a non-empty string name, the eight
maintained model type names and Boolean display/automatic options. Camel-case
`showOnCard`, `automaticallyOnCard`, `showLabelOnMiniCard` and `showSumAtTopOfList`
match the maintained `server/models/customFields.js` API. Legacy lowercase aliases
remain accepted; conflicting JSON aliases and duplicate form/JSON fields fail
before writes. Missing/empty type retains WeLite's existing text default.

One transaction inserts the definition, board association and createCustomField
activity. Activity identity comes from the authenticated user, never body authorId.
The activity's customFieldId is stored in native data_json / shared root metadata.
Any failing stage rolls everything back and returns HTTP 500. The list endpoint
returns the maintained `_id`, `name`, `type` summary shape.

`tests/defapi.py`, invoked by the native and real shared HTTP suites, covers every
supported type, JSON/form/canonical/legacy options, authenticated attribution,
malformed inputs and injected AFTER-write failures at all three stages. These
checks concern the currently supported metadata. Definition settings/full payloads,
edit/delete lifecycle and automatic-card policies still need source reconciliation;
typed migration/explicit type changes and selection clone/export remain open too.

## Nested custom-field setting columns

The normalized SQL column names remain currencyCode, stringtemplateFormat and
stringtemplateSeparator. On shared stores their generated source paths are now
settings.currencyCode, settings.stringtemplateFormat and
settings.stringtemplateSeparator, matching `models/customFields.js`. These three native
columns retain their names. The adapter no longer treats same-named root
properties as these canonical settings.

SQL edits create an absent settings object and preserve existing dropdownItems,
unrelated settings and typed unknown properties. An existing incompatible scalar
settings value is refused; a bad row rolls back the whole SQL statement. Reinstall
rebuilds owned views/descriptors in the corrected shape without rewriting source
documents. Legacy same-named root properties remain intact and are not promoted
or deleted automatically.

`tests/cfset.py`, run by the real-server suite on both backends, verifies SQL/Mongo
round trips, explicit SQL inserts, missing parents, exact BSON preservation,
dropdown edits, invalid-parent rollback and upgrading an old flat view/descriptor.
Full settings API mapping/validation and a provenance-aware legacy-root normalization
policy remain open; this is a projection correction, not a full definition/settings
migration or lifecycle implementation.

## Unmapped settings remainder and native upgrade

`custom_fields.settings_json` stores a JSON object for the remainder of settings.
It excludes currencyCode, stringtemplateFormat, stringtemplateSeparator and
dropdownItems, which belong to their existing columns/child relation. The generated
shared descriptor records these exclusions. Scoped SQL reads omit those owned
children; an explicit remainder write replaces only the other settings properties.
Protected children cannot be supplied through this column. New shared definitions
receive the empty-object default; existing insertion-seed settings stay intact.
Unchanged values retain
source BSON tags when the remainder is read, edited and written back.

An absent settings object can be created; an existing incompatible scalar parent
is refused. Malformed/non-object payloads and protected-name conflicts abort the
whole SQL statement. Root-level remainder behavior for other models is unchanged.

Fresh native schemas include the TEXT NOT NULL/default-object column with JSON
object/protected-name CHECK constraints. Native tenant open checks an existing
column's declaration and data, or adds the column in one transaction before caching
the handle. Existing columns, rows and related tables are retained. Concurrent
openers recognize a successful compatible upgrade. Incompatible columns/data,
views and recognized FerretDB source stores are refused without definition/schema changes;
unrelated minimal stores with no custom_fields object are left alone.

`tests/cfextra.py` verifies native fresh/legacy/concurrent upgrades and negative
schema/data cases on both backends. `tests/cfset.py` verifies shared protected-field
ownership, typed round trips, invalid-parent rollback and rebuilding old views that
lack the column. Native/shared HTTP suites retain existing import/clone/API behavior.
Full settings API mapping/validation and provenance-aware legacy-root normalization
remain separate unfinished steps; this provides their storage foundation.

## Scalar settings API mapping and definition reads

Definition creation accepts a settings object or JSON object text (for form input).
Currency/template properties go to their canonical columns; other JSON properties
go to the protected remainder. Known settings must be strings. Jira time fields
use original/remaining, estimate IDs match customfield_ plus 1..20 ASCII digits,
and estimate units have the schema's 80 JavaScript UTF-16-unit limit. The pinned
aldeed:simple-schema 1.13.1 doStringChecks implementation compares string.length.
Strict typed-document validation also checks recursive UTF-8, unique keys, finite
numbers and depth before creation. Empty template strings retain their meaning.

Definition GET now reconstructs supported native flags, dates, board IDs and
settings, including existing dropdown relation rows. On shared stores it validates
and serializes the source document with the same BSON Date JSON conversion used
for custom values; internal SJSON schema metadata is omitted. Native legacy date
strings retain their existing representation.

`tests/cfspec.py` checks normal/checked parsing and full-document conversion.
`tests/setapi.py`, invoked by native/shared HTTP suites, covers JSON/form settings,
known-column/remainder storage, full metadata, UTF-16 boundaries, invalid data and
rollback after later transaction failures.

This creation step does not accept dropdownItems payloads: exact managed-array
creation and absent/empty presence need a coordinated native/shared contract.
They return HTTP 400 instead of being silently dropped. Dropdown creation,
definition edit/delete, adminOnly/readOnly field-policy parity, automatic-card
policies, normalized typed migration and selection clone/export remain open.

## Custom-field API value permissions

Native definitions now store `adminOnly` and `readOnly` as constrained booleans;
older native stores receive additive columns before tenant-handle caching. Shared
columns project and write BSON booleans without replacing unrelated source data.

All API card payloads, including mutation responses, retain custom-field IDs and
positions but replace unreadable values with JSON null. Missing values remain
absent. A missing definition or one not associated with the card's board makes
its value unreadable, even for an administrator. Active administration of the
card's board permits reading `adminOnly` fields and writing `adminOnly`/`readOnly`
fields; site administration alone is insufficient. Other members can read
`readOnly` values under the ordinary board-access rules.

Custom-value POST returns 403 for a failed initial field-policy check. It also
checks the current user, board, card and definition within the write transaction,
before mutation and before commit. A failed transactional guard produces a
storage error and rolls back the complete write, including trigger changes.
Shared checks validate the complete typed source and pin adapter bindings;
nonboolean policy flags or unsupported identifier types cannot grant access.
Read-policy failures mask values instead of returning an unredacted array.

`tests/cfpolicy.py` exercises all card response routes and role changes against
native/shared HTTP on both backends, with after-write revocation and exact rollback
checks. It also covers malformed BSON, corrupt metadata and shared batching.
`tests/cfpol.py` checks normal/checked builds on both SQL backends, quoted Unicode
IDs, multi-batch positions/missing values and fail-closed query errors.

Definition POST accepts `readOnly`/`adminOnly` through canonical JSON, form fields
or lowercase aliases. It validates boolean values and rejects conflicting aliases
before mutation. Ordinary board writers may create read-only fields, matching the
model's definition permissions; creating admin-only fields requires active board
administration even for a site administrator. Unlike the current WeKan REST route,
which ignores these two inputs, WeLite explicitly persists and enforces them.
Creation guards check authority before writes and after the activity, validate
resulting boolean flags and require exactly the requested board association.
Triggered revocation, invalid flags, repointing or adapter-binding changes roll
back the definition, association and activity together. Definition editing/deletion
is still unfinished.

The HTML, selection/export/clone, activity, query and other value-bearing
boundaries still need equivalent policy checks. This API support does not
establish application-wide field-policy parity.

## Selection export field gate

Selection exports check board-wide visibility before collecting the graph and
again before delivery. Selecting only a harmless card does not evade an unreadable
value on another card, or an admin-only definition without an assigned value.
Active board administration is required for admin-only definitions; global admin
status alone is insufficient. Nonnull values with missing/wrong-board definitions
block even an administrator's export. Null/missing orphan values and ordinary
read-only values keep their source export semantics.

Shared source metadata is validated and failed policy queries deny the export.
Board value permissions use one correlated statement with both card and field
identities. Complete shared card documents are fetched in a board batch, with an
owned-table binding check and exactly one physical source required per projected
card. Every returned document passes typed custom-field validation, including
null/missing fields; unrelated corrupt metadata also rejects the export. Native
TEXT storage has no BSON source metadata to convert. `tests/cfsbatch.py` covers
TEXT/JSONB, cardinality/ownership/SQL failures and full-document corruption in
normal/checked linked/CLI builds, plus constant per-card CLI subprocess counts.

Board-associated definitions are also validated in one native/shared batch. Shared
sources require a unique owned binding and physical identity, and complete BSON
validation precedes reading the stored flag. Missing/null/boolean `adminOnly`
values are supported; nonboolean Date/NaN data is rejected before JSON null
conversion. Native rows reuse settings validation (including shadow rejection)
and require integer 0/1 administrative flags. The gate checks board administration
once if any definition requires it; it does not fetch unused response child rows.
`tests/defbatch.py` covers normal/checked linked/CLI TEXT/JSONB/native sources and
`tests/cfpol.py` verifies whole-board behavior and constant per-definition CLI
subprocess counts.

Card and definition validation consume `TWLDb.Scan` callbacks within one SQL
statement per batch. The linked backend steps one row at a time; the bootstrap
CLI parses CSV from bounded pipe chunks while draining stderr. No new SQLite
extension is needed. Full source/flag validation still applies to every row,
including the last one, and handlers retain no source rows. A malformed stream,
failed statement/child, stderr output or handler exception invalidates the batch;
provisional rows cannot authorize delivery. Scratch files and statements are
released on failure.

`tests/dbscan.py` exercises normal/checked linked/CLI text/CSV/UTF-8 boundaries,
late failures, handler exceptions, pipe pressure and cleanup. On Linux,
`tests/cfsbatch.py` and `tests/defbatch.py` validate over 128 MiB of source BSON or
native settings under a 96 MiB address-space cap on both backends, including late
corruption. Buffering scales with the current row and parsed document, rather
than total batch payload. SQLite work sets and the separately collected export
graph still have their own resource requirements.

The final check also inspects captured nonnull relation rows, so clearing a stored
private value after collection does not make that captured value exportable.
Denied exports return HTML 403 without an attachment response or selection graph.
`tests/actions.py` and `tests/cfexpt.py` cover native/shared actual HTML requests;
normal/checked `tests/cfpol.py` covers board gates and captured rows on both backends.

Selection export payloads also receive a recursive audit before delivery. It
checks custom-field arrays, activity value/oldValue/newValue/customFieldValue
aliases and integrityHash/previousHash, respecting nested board scope. JSON
columns are decoded for inspection, and non-null typed source seeds are validated
before inspecting their plain values. Current shared read views normally expose
`_wl_source` as null; the source-seed check covers any supplied seed rather than
assuming that column contains an exported document.

Unreadable activity/embedded values, malformed encodings and non-admin hashes
refuse the export. Historical visibility uses the definition and board, allowing
readable history even after a card was removed. Inspection does not rewrite data
or serialized columns; allowed unknown Date/Long/Binary source data remains
unchanged. `tests/cfscan.py` runs 173 cases in normal/checked builds on both SQL
backends; native/shared HTML tests cover actual activity, extras and hash gates.

Clone/import, generic HTML/data/query surfaces and other value-bearing paths
still need policy reconciliation. These checks do not establish application-wide
field-policy parity.

## Selection clone field permissions

Clone preflight checks the rows it will copy, rather than applying the whole-board
export gate. Nonnull hidden/read-only custom values require active administration
of the board, including for a site administrator. Nonnull values with missing or
wrong-board definitions are denied even to administrators. Assigned null values
are allowed under the source insert policy. Old activities are not copied and do not block a
clone merely because their values are unreadable.

Recognized nested field values and hashes in copied payloads receive the same
scope checks, with field writes requiring write permission. Successful checks
produce SQL guards. Those guards and the actor/board/source-card checks execute
inside the clone transaction before writes and again before commit. Destination
card checks also inspect actual nonnull custom values, catching protected values
that a trigger inserted after a null assignment was copied. Failed guards roll
back SQL changes and remove prepared attachment copies through existing cleanup.

Native/shared HTML regressions on both SQL backends cover editor/admin/global
boundaries, null values, uncopied history, late role/flag changes and destination
injection. Normal/checked helpers cover collected SQL guards and correlated
source/destination value checks. This establishes these clone permission gates;
exact unknown BSON types/presence in newly cloned records, import permissions and
other generic data/query surfaces remain unfinished.

## Typed selection export audit

Shared selection export collects the full typed source of each selected root row
in the same SQLite read snapshot as its ordinary projected columns. In addition
to cloneable roots, this includes boards, custom-field definitions and activities.
A private audit graph replaces shared root projections with typed source wrappers;
its native/relation rows retain the existing plain payload checks. The typed
scanner validates complete source metadata and uses canonical string schemas for
field/board identifiers. A Regex pattern matching a field ID cannot grant access,
and a Regex pattern `customFields` remains literal data rather than a string
activity marker. Keys such as `_wl_source` inside source data stay literal.

The captured root descriptors, versions, collection names and settings must match
owned metadata. Bindings are checked again before delivery, and missing ownership
or failed source queries deny collection. The ordinary whole-board field gate and
captured custom-value row checks still apply. The private audit graph/bindings are
removed before serialization; source columns retain their original null output
and no raw typed source is added to the download. This step establishes typed
identity for selection export checks, not a new typed export/import file format.

`tests/cfexpt.py` runs through real shared HTTP on both SQL backends and covers
nonstring field/board identities in card extras, activities and selected definitions,
literal Regex markers/source-like keys, exact source BSON preservation, unchanged
public export shape and missing activity-root ownership. The same focused shared
HTTP checks pass with range, overflow, I/O and assertion checks enabled in Pascal.
The previous committed selection implementation returns a download for the new
Regex field-ID case, confirming that the regression detects the original gap.
Clone/import fidelity and other value-bearing routes remain unfinished.

## Typed root clone seeds

For shared root records, clone collection reads a typed source seed and its SQL
columns in the same SQLite read snapshot. Owned metadata must match the root view
and collection. Captured model descriptors, versions and collection settings are
checked again during clone preflight and inside the transaction, so a changed
binding or collection epoch cannot redirect a captured seed into another context.
Missing ownership, malformed source or failed selection queries return a controlled
error without cloned records/files.

`RootCloneSeed` removes managed relation paths and their metadata during root
creation. Native relations use ordinary row insertion. Shared cards receive the
complete typed relations in the guarded final stage described below, while root
insertion overlays use original metadata for unchanged unknown values. Live Mongo/BSON checks compare an
opaque subtree containing Date, Long, Binary subtypes, ObjectId, unsigned Timestamp,
Regex, negative zero, NaN/infinity, arrays and nulls against the stored source.
Comparisons use stored BSON, including its NaN canonicalization, rather than
assuming the database retains every bit pattern supplied by the initial client.

Plain JSON inspection validates structure/UTF-8/finite numbers without assigning
BSON integer types, so unsigned timestamps are not rejected during inspection.
After a SQL JSON/source column is decoded, keys such as `_wl_source` or `other_json`
inside the actual data remain literal values; recursive field-policy checks still
inspect actual objects and arrays. Typed seeds retain schema identity during these
checks: ObjectId/Regex/Date lookalikes cannot become string field/board identifiers.
Existing card-field row IDs also require canonical BSON strings for API/clone
access. Ordinary opaque scope data without field values remains copyable. A typed
seed supersedes its lossy root remainder only when every remainder key and value
matches; the complete typed seed is still audited. Thus a Regex whose pattern is
`customFields` cannot become a string activity marker through the SQL projection.
Inspection never rewrites source values.

`tests/clseed.py` covers normal/checked seed stripping, insert overlays and invalid
source/model paths; shared HTTP tests verify stored BSON and metadata-change
rollback. The existing SJSON source oracle also passes using local Go 1.27.3 with
only its temporary probe module's directive lowered from 1.27.4; the declared
1.27.4 toolchain itself was not verified. No maintained Go source/module is edited.

Remaining legacy relation forms, reference/lifecycle details and import
permissions remain unfinished. Root seed support does not establish complete
clone fidelity; mapped root presence is handled by the explicit patch below.

## Typed root selection scopes

`TSelectionScope` caches owned root descriptors for one graph. It validates each
scope column's path against the compiled model, captures model/version/collection
settings and exact view SQL, and builds predicates against the owned typed source.
A root identity and each link used by a branch must be a nonempty BSON string.
The stored scope value must also equal the projected column, so a misleading
projection cannot borrow another stored value. Ambiguous plain IDs fail closed;
physical ID probes use the installed quoted-path index.

Board and explicit selected roots must resolve to exact canonical identities;
mixed invalid roots reject the complete request before edit/save rendering or
mutation. ID collection compares exact bytes and retains case-distinct IDs.
Expanded lists/cards, recursive children, checklists/items, comments, attachments
and activities check the actual link types used to establish membership. Each
`card OR list OR lane` branch carries its own check, allowing a valid list link
when a card field is merely opaque Regex data. Optional board properties on
card/checklist-owned checklists/items do not become mandatory.

Predicates check captured descriptor/view bindings when evaluated, and the full
captured set joins existing clone/export preflight and transaction/delivery guards.
This includes root classes whose selected rows are empty. Source document audits
and field-policy gates still apply. These predicates establish root link identity
and descriptor bindings, not a transaction-wide snapshot of multi-query graph
collection. Embedded-relation identity scopes, broader HTML/query boundaries and
remaining lifecycle/mixed-writer consistency remain unfinished.

`tests/selscope.py` runs 36 TEXT/JSONB predicate/ownership cases per normal/checked
linked/CLI variant, including nested paths, projection disagreement, model/epoch/
view changes and actual query-plan index inspection. Native behavior and exact-case
IDs have unit/live coverage. `tests/clroots.py` verifies export and clone exclusion
of root lookalikes, legitimate OR alternatives, explicit nonstring refusal, mixed
edit/save refusal, case-distinct IDs and unchanged source/file content. Clone tests
also verify activity-model changes after mutation roll back the transaction.

Before export-policy batching, the richer CLI fixture measured roughly 13 seconds
for a successful export after its prior clone batch, compared with about 0.1
seconds linked. Board value permissions, complete card-source validation and
definition reads are now batched; expanded CLI exports measured about 2.5–2.9
seconds locally, with linked about 0.07–0.08 seconds. Source validation now
streams result rows; it does not collect the board's complete BSON payload in
memory. The final selection/export graph is still collected separately. Only the heavy export test opts into a 30-second timeout; it retains all
rows, policy checks and assertions, while other HTTP tests keep their defaults.

## Mapped clone root fields

Shared root clones build a partial column patch from captured typed source and
intentional clone edits. IDs, declared creation/modification/activity timestamps,
selected root titles, order/counters and changed canonical string references are
written. Other mapped fields are left out, so SQL view defaults cannot materialize
missing values or replace explicit nulls. Existing BSON type/bits and nested parent
presence remain intact, even when an old source lacks a now-required model field.
Reference lookalikes with nonstring BSON schemas retain their original identity.

An insert-only `_wl_source` envelope contains exactly `_wl_clone: 1`, the typed
source string and a `columns` object. `wl_model` validates this explicit envelope
and applies clone projection to its partial patch. It requires a canonical string
source ID, a distinct nonempty string new ID and known model columns. Managed
paths are still stripped during root creation and copied in the separate guarded
card-relation stage. Existing root-view reference/unique checks run on the computed
clone document. Ordinary inserts retain their original defaults/validation, source
seed updates stay read-only, and no new columns or download keys are introduced.
A real typed source field named `_wl_clone` remains ordinary data because its root
has BSON metadata; it is not interpreted as an envelope.

Shared recursive child collection also checks the actual BSON string schema of
`parentId`. A Regex pattern matching a selected parent is not a child link. Native
parent links keep their SQL behavior, while failed selection-ID queries now deny
graph collection. The root scope rules above extend this to other root links;
embedded-relation identities remain open.

`tests/clpres.py` verifies normal/checked patches, nested null/missing parents,
unchanged types, ID/envelope rejection and actual TEXT/JSONB SQL execution/rollback.
`tests/ferroot.py` verifies that clone envelopes still hit actual root-view foreign
reference and unique checks while ordinary inserts retain defaults. Live HTTP
`tests/cfclon.py` and `tests/clroots.py` cover source absence/null/BSON preservation,
nonstring parent identity, missing required child fields and lane clones containing
swimlanes/lists/cards/checklists/items/comments/attachments. They verify remapped
references, typed nested list settings and unchanged attachment bytes on both SQL
backends. Broader source/lifecycle parity is still unfinished.

## Typed managed card clone relations

Shared card collection retains a complete typed source privately, in addition to
its stripped root seed. Recursive write-policy checks inspect that source before
file preparation, including unknown metadata inside custom-field/dependency rows.
Native cards keep ordinary relation insertion. Shared cards skip the five lossy
relation insert batches and call the deterministic `wl_clone_rel` SQL function
inside the existing clone transaction after root records and activities exist.

The function validates both typed documents and the selected card map, checks
canonical source/destination IDs and identical board binding, and copies members,
assignees, label IDs, custom fields and dependencies with complete BSON schemas.
It preserves relation field presence, explicit nulls, empty containers, array/row
order and unknown typed row data. Stored custom values retain their existing type
even if a current definition would initialize a new value differently. Canonical
string relation keys and duplicate logical keys are checked before writing.
Dependency `cardId` values are remapped for selected targets (including self and
forward/back references); external targets and opaque nested keys stay unchanged.

Source/binding/permission guards and destination-card guards run before this stage
and again after it. This catches protected values injected before or during typed
copy and prevents copying hidden relation metadata. A failed function, absent
new card, binding change or guard failure rolls back all records/activities and
uses existing attachment-file cleanup. Target TEXT/JSONB representation is kept.

`tests/clrel.py` checks typed schemas, missing/null/empty states, remapping and
invalid/duplicate/foreign bindings in normal and checked Pascal builds. It also
loads the real SQLite extension to verify TEXT/JSONB representation and rollback
of failed copy transactions in both build modes.
`tests/cfclon.py` exercises real shared HTTP/Mongo with Date/Long/Boolean/array/
Binary/Timestamp/Regex/special-double values under a text definition, typed row
extras, parent-child dependencies, malformed/duplicate keys, hidden metadata and
triggered permission rollback. These paths run on both SQL backends; remaining
legacy forms and broader clone lifecycle behavior are still unfinished.

## Remaining before the checklist can be checked

- Complete Mongo-managed sparse/multikey account indexes, registry-cache/error coordination and normalized-store authentication migration policy; reconcile typed
  custom-field values, legacy dependency forms and SQL conflict behavior.
- Reconcile broader resume-policy parity and process-signal lifecycle; reconcile file-store metadata/bytes.
- Activate the adapter for fresh and existing stores without silently creating a separate
  normalized database; adapt cloning/export and finish authentication integration.
- Verify shared-database HTTP/Mongo-wire workflows, including permissions, restart and
  rollback with both Welite SQLite backends.
- Resolve shared database filename/8.3 policy and document target-specific limitations
  from actual tests. Never share a file through aliases with different WAL names.

### Opt-in HTTP activation of existing stores

Set `WELITE_SHARED=1` to open existing public tenant FerretDB stores through the
HTTP application. The local tenant uses
`WELITE_DATA/local/files/db/wekan.sqlite`; enabled domains use their existing
registry-derived `domains/dXXXXXXX/files/db/` directory. The adapter installs its
owned projections on the existing physical collections. The reserved admin
registry remains native at `admin/files/db/wekan.db`. Empty/unset or `0` retains
native public provisioning; other mode values fail initialization.

Selection never copies, renames or links database files. Shared mode requires an
existing FerretDB metadata table and refuses normalized public stores. A recognized
FerretDB store already named `wekan.db` can also be opened explicitly. Both known
filenames together are refused, as are orphan known sidecars; native provisioning
refuses a foreign `.sqlite` file rather than silently creating a shadow database.
Ordinary mode refuses the canonical shared filename and FerretDB metadata in the
short filename. Resolve ambiguous files and recovery state offline first.

`WELITE_SHORT_NAMES=1` refuses `wekan.sqlite`: the actual FerretDB server uses
normal SQLite sidecar names. This opt-in path does not establish a portable shared
filename policy, create fresh shared databases or migrate normalized data. Do not
rename or alias an open database to work around these checks. Full Meteor application
observer/index/cache and file-byte compatibility remain separate acceptance gates.

`tests/shrhttp.py` uses the actual FerretDB server and both SQLite backends. It
checks canonical selection/refusal, HTTP API login and card creation, Mongo title
updates visible through HTTP, preserved BSON Long/Date values, private browser
sessions, restart persistence and revocation by removing the shared resume record.
It also proves ordinary mode does not create `wekan.db` beside `wekan.sqlite`.

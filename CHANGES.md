# ChangeLog

WeKan-Lite — the FreePascal reimplementation of WeKan: one native binary, SQLite-only, no-JS /
no-cookie capable, runs where Meteor cannot (Amiga 68k/PPC, MorphOS, AROS, Haiku, BSD, …).
Distilled from the [`wami/`](https://github.com/wekan/wami) and [`omi/`](https://github.com/wekan/omi) prototypes against the portable contract in `docs/`.

## 2026-11-16 Targeted shared token revocation

- Add a transaction fragment that removes one bearer's shared hashed and matching
  legacy plain records plus its scoped local credential/metadata. Keep other sessions,
  pending setup and replay counters untouched. Check source identity and assert no
  matching shared record survived an ignored write before deleting local state.
- Add the typed revoke command; derive its digest from the supplied bearer so a caller
  cannot mismatch raw/hash selectors. Serialize the bearer through escaped JSON,
  including the SQL comparison, rather than putting control bytes into SQL text.
- Connect observed credential/policy failure, local expiry and invalid stored-session
  identity to targeted cleanup. A stale collection removes only local state and never
  edits the replacement collection. Preserve existing IP/user-agent mismatch behavior.
- Centralize the unchanged tenant-scoped private hash for issuance and revocation;
  give invalid enrollment attempt digests their own explicit domain prefix.
- Verify both SQLite backends with hashed/legacy removal, ignored/failed-write rollback,
  unchanged sibling sessions/BSON, missing-token no-op, credential restoration and local
  expiry through live Mongo. Session/kernel and native HTTP account regressions pass.
- Shared bearer issuance/authorization, expiry scheduling and legacy conversion remain
  open; this step connects individual revocation to existing validation failures.

## 2026-11-16 Shared all-user token revocation

- Connect administrator account disabling and OTP enrollment to one transactional
  revocation fragment. Clear shared Meteor resume arrays, including legacy records,
  alongside local token metadata/credentials and pending enrollment tokens.
- Preserve unrelated BSON data and OTP replay boundaries. Leave absent resume paths
  absent, and scope changes to the selected user; re-enabling cannot restore removed
  shared/local bearers or pending setup. Native stores retain their private-token path.
- Guard source identity again inside the transaction and assert shared records are
  actually empty. Failed or ignored physical writes and later local deletion errors
  roll back both revocation and the owning account change.
- Share pending-enrollment schema in a small metadata unit, ensuring it exists within
  revocation's transaction without circular imports or a setup-creation race.
- Verify both SQLite backends with live Mongo enrollment/disable, shared and local
  records, pending cleanup, source changes, forced/ignored writes, rollback/retry,
  account isolation and re-enable behavior. Verify native HTTP account regressions.
- Shared bearer issuance/authorization, per-token revocation and expiry scheduling
  remain open; this step connects the all-user revocation events.

## 2026-11-16 Resume timestamp validation and expiry

- Add typed hashed-token checking with absent/valid/expired/invalid results. Require one
  matching record, a BSON Date or legacy numeric timestamp, and an explicit positive
  lifetime. Reject ambiguous hashes, malformed timestamps and invalid Date ranges;
  failed checks leave output timestamps empty.
- Match the resume expiry boundary: now equal to expiry is expired. Legacy fractional
  numeric milliseconds follow Date(number) truncation; expiration arithmetic is bounded
  to JavaScript's Date range without integer overflow.
- Add strict-before expiry pruning for Date and numeric records, including legacy plain
  records. Preserve unrelated/malformed timestamp records and shifted sibling schemas.
  Expose pure wl_rescheck alongside wl_resume on linked/CLI SQLite.
- Verify both backends with exact boundaries, future stamps, lifetime/range failures,
  legacy fractions, duplicates and live Mongo typed pruning/BSON preservation.
- Shared bearer authorization/issuance and revocation remain open. Browser sessions stay
  private so cross-application bearer use cannot bypass their client binding.

## 2026-11-16 Typed Meteor resume-token kernel

- Add Meteor SHA256/base64 token hashing, separate from WeLite's tenant-scoped private
  digest. Verify ASCII, Unicode/NUL and bounded input against Python's independent
  hashlib/base64 results; reject empty/oversized raw tokens and noncanonical digests.
- Add pure append/remove/clear operations on services.resume.loginTokens. New records
  contain a hash and BSON Date; no new raw token is stored. Retain legacy records,
  unknown fields, field order and complete sibling schemas when array positions shift.
- Expose the kernel as wl_resume on linked SQLite and the host-API CLI extension.
  Refuse duplicate appends, invalid commands/dates and malformed parent containers.
  Explicit clear can empty a malformed token value while preserving its parent fields.
- Verify TEXT/JSONB atomic writes and rollback, sixteen concurrent distinct appends
  without lost records, one winner for duplicate appends, shifted Date metadata and
  live Mongo BSON round trips including legacy tokens and precision-sensitive values.
- Keep shared token issuance/validation, expiry, logout/revocation, legacy conversion
  and Mongo token indexes open. This storage kernel does not authorize shared sessions
  or change the existing HTTP/private-token authentication paths.

## 2026-11-16 Physical model unique keys

- Install owned SQLite unique expression indexes for declared model unique keys,
  including usernames. Enforce the existing BINARY/canonical SQL NULL semantics on
  physical FerretDB documents, protecting both SQL views and direct Mongo writes.
- Record index ownership/definition in the adapter registry. Preserve exact owned
  definitions, repair an absent owned index and refuse unowned or altered objects
  without replacing them. Index creation and registry installation remain atomic;
  existing duplicates still require repair rather than rewriting account documents.
- Verify linked/CLI live Mongo duplicate inserts (11000), rejected duplicate updates,
  eight mixed Mongo/SQL writers with one winner, case/NULL/missing values, fresh server
  startup, removed-index repair, altered/unowned refusal and legacy ambiguous-login
  denial with duplicate preflight/repair. Mongo listIndexes metadata is unchanged.
- Keep Meteor-managed sparse/multikey account indexes and registry-cache coordination
  open. These private SQL constraints do not implement Mongo sparse NULL semantics,
  emails/resume-token multikey uniqueness or full Mongo duplicate-update error mapping.

## 2026-11-16 Shared authentication collection identity

- Bind private authentication state to the FerretDB users collection's physical table
  and UUID in an owned source record. Routine adapter reinstall preserves credentials,
  OTP counters and pending setup; replacing the collection invalidates the old state
  even when IDs, usernames and password records are reused.
- Check source identity during account lookup, login/enrollment proof use and web/API
  validation. Carry the observed source condition into token/setup mutations and OTP
  activation transactions, closing changes between the initial read and SQL write.
  Observed stale token validation also removes that credential and web context.
- On a known source change, atomically revoke local tokens/metadata and pending setup,
  reset the old replay ledger and bind the new source. Older unbound adapters revoke
  credentials/setup once while retaining conservative replay boundaries. Tenant attempt
  allowances survive either transition.
- Refuse missing/non-string/wrong-length UUIDs through the source-record constraints;
  failed binding rolls back cleanup and the rest of adapter installation together.
- Verify both backends against actual Mongo collection drop/recreate, reused account
  credentials, normal reinstall, proof rebinding, legacy backfill and malformed-metadata
  rollback. Native password/OTP, enrollment, session and public HTTP tests still pass.
- Mongo account index parity, shared Meteor resume tokens and application activation
  remain open; source identity does not complete those compatibility gates.

## 2026-11-16 HTTP OTP enrollment

- Add plain HTML setup and confirmation forms, linked from sign-in. Require a fresh
  password, display a manual authenticator secret and retain only an opaque setup
  token in the confirmation form. Never place setup secrets/tokens in navigation URLs
  or grant a session before activation; send no-store and no-referrer headers.
- Bind setup to socket peer and user agent. Share durable login allowances with setup
  and confirmation; derive the confirmation account from pending server state so
  posted usernames cannot rotate its budget. Denials return 429 with Retry-After.
- Send newly registered accounts covered by REQUIRE_2FA to enrollment without issuing
  application tokens or returning a misleading account-creation error. After confirming,
  instruct users to wait for a fresh authenticator code and sign in normally.
- Verify both backends through HTTP: required-factor registration, wrong passwords/codes,
  client binding, attempt caps, forwarded-header/username spoofing, setup expiry and
  replacement, restart persistence, failed activation rollback/retry, no early access
  and consumed-code denial. Verify setup, confirmation and sign-in in Chromium with
  JavaScript disabled and Cookie headers removed, plus existing HTTP regressions.
- Shared Mongo account/index/session integration and application activation remain open;
  completing enrollment does not complete the shared-database checklist.

## 2026-11-16 Limited OTP enrollment core

- Add a distinct, unit-owned password proof for accounts without an active factor,
  including accounts covered by REQUIRE_2FA. It cannot authorize application tokens.
  Bind it to the database and credential/policy snapshot, expire it after 30 seconds
  and allow only one successful setup start.
- Generate fresh 20-byte secrets and independent bearer tokens. Keep pending setup in
  private owned storage for five minutes, bound to a server-derived client digest.
  Starting setup leaves shared services unchanged and creates no login token. New setup
  invalidates an earlier pending token; user deletion removes pending secrets.
- Confirm the code and current credentials/policy, then activate the factor, consume its
  counter, remove pending setup and revoke local tokens in one transaction. Deny stale,
  expired, replaced or competing setup, and roll back failed or ignored user updates.
  The activation code cannot be reused for login; a fresh code signs in normally.
- Normalize SQLite JSON-expression subtypes at shared TEXT projection boundaries, so
  json_set updates and JSON-valued inserts reach the typed patcher as text.
- Verify linked/CLI limited proofs, independent OTPs, fresh secrets, binding/expiry,
  snapshot changes, sixteen concurrent confirmations, full rollback/retry, token
  revocation, null factor metadata and schema refusal. Verify shared BSON preservation,
  reinstall and physical user-deletion cleanup against live FerretDB.
- HTTP enrollment forms, setup confirmation routing and admission limiting remain open.
  This step supplies the core; it does not yet expose enrollment to users.

## 2026-11-16 HTTP password and OTP login

- Connect no-cookie web sign-in and REST login to the password/OTP proof factory and
  atomic token issuer. Add an optional six-digit code field to the plain HTML form;
  accept `code` alongside username/password in JSON or form REST requests.
- Reserve durable account/peer/tenant allowances before credential verification on
  both routes. Return 429 with Retry-After when denied; use the actual socket peer,
  ignoring forwarded headers for admission. Both routes share counters across restart.
- Preserve password-only accounts, factor-bound session/API validation and transactional
  replay consumption. Required accounts without an active factor remain denied pending
  enrollment. Return API credentials using proper JSON string encoding.
- Verify linked/CLI HTTP login, wrong/missing/malformed codes, replay, forced issuer
  rollback/retry, restart persistence, spoofed peer headers, shared route caps, factor
  replacement and required-factor policy. Verify actual Chromium form submission and
  reload with JavaScript disabled and Cookie headers removed on both backends.
- Keep legacy policy/secret test scenarios in independent attempt windows; token rollback
  assertions permit the intentional pre-authentication reservation while still comparing
  all other database data. Enrollment and shared Meteor session integration remain open.

## 2026-11-16 Durable login attempt reservations

- Add atomic pre-authentication reservations: five attempts per account, thirty per
  socket peer and three hundred per tenant in 300-second windows starting at the first
  reservation. Count successful attempts too; credential checks do not reset allowances.
- Store hashed account/peer buckets privately in SQLite, retaining limits across
  processes and restarts. Backward clock changes deny reservations; expired buckets
  are removed on successful reservation, bounding stored bucket cardinality to 601.
- Roll back every bucket on denial or write failure. Reject incompatible schema and
  invalid identities/time rather than admitting an uncounted attempt. Register the
  table in the shared adapter without changing account documents.
- Verify linked/CLI concurrency, boundary times, rollback/retry, peer and tenant caps,
  cleanup, separate tenants and live shared-adapter reinstall persistence.
- HTTP login integration and enrollment remain open; callers must reserve using trusted
  server time and the actual socket peer before performing credential verification.

## 2026-11-16 Password and OTP token proofs

- Add unit-owned password/OTP proofs with a 30-second lifetime and single successful
  issuance. Retain credential/policy snapshots and the matched code, never plaintext
  passwords. Recheck current policy, credentials and code before issuing a token.
- Commit token, metadata and replay consumption together. Failed writes roll back;
  competing logins using the same counter have exactly one winner. Bind web/API
  validation to the current password and canonical active factor, including Argon2
  secret-file policy. Observed changes revoke existing credentials permanently.
- Verify both SQLite backends, sixteen concurrent logins, stale account/factor policy,
  forced metadata/counter failures and retry, LDAP fallback and required-factor modes.
  Verify a live shared FerretDB account with Argon2 secret plus OTP without BSON changes.
- Keep HTTP code forms/API routing, failed-attempt limits and enrollment open. The
  existing HTTP password-only routes still deny active or required factors.

## 2026-11-16 Durable OTP replay claims

- Add private per-user/per-factor replay counters. Canonical base32 identity makes
  case/padding aliases share the same boundary. Preserve consumption across token
  logout/expiry and process restart; keep users and changed factors independent.
- Supply a claim statement for the same transaction as token/metadata insertion.
  Stale or duplicate counters violate the counter constraint, requiring rollback of
  the whole token transaction. A missing token cannot consume a counter; failed
  token/metadata/counter writes leave the code available for a valid retry.
- Distinguish unused factors from schema/query errors, NULL values, duplicate records
  and invalid stored negative counters. Validate the private table/cleanup definition.
- Include owned replay storage in the shared adapter and remove it with its physical
  user, while token deletion retains it. Verify 16 concurrent claimants (one success),
  rollback/retry, restart, aliases, isolation and corrupt-state denial on both SQLite
  backends, plus shared FerretDB ownership/cleanup and existing TOTP vectors.
- Keep second-factor proof validation, production token-issuer wiring and enrollment
  open. The replay kernel does not authorize a login by itself.

## 2026-11-16 Portable one-time-code core

- Add SHA1 HOTP/TOTP with explicit big-endian 64-bit counters, preserved leading zeroes
  and 30-second time steps. Support the six-digit Meteor profile and eight-digit RFC
  vectors. Parse bounded ASCII base32 with case-insensitive input, canonical unused
  bits and correct optional padding; clear decoded keys and HMAC working digests.
- Match the full bounded validation window without early success, return its counter,
  and reject matches at/below the caller's replay boundary. A matching used counter
  cannot be rescued by a colliding later counter in the same window. Counter consumption
  still belongs in the upcoming atomic token-issuance integration.
- Verify published RFC HOTP/TOTP SHA1 vectors and independent Python HMAC, including
  binary secrets, padding/case, maximum counters, post-2038 times, window edges and
  malformed inputs in normal/checked Pascal builds.
- Keep active-factor login guarded until replay storage, login proof/issuance and
  enrollment routes are implemented and verified.

## 2026-11-16 Shared account guards for password-only flows

- Centralize shared-account policy at login lookup, token issuance and every web/API
  token validation. Active/unknown factor types and malformed factor metadata cannot
  be bypassed with a password alone. Pending activation without a type remains usable
  when no factor requirement applies.
- Match WeKan's LDAP enable/fallback/explicit opt-out rules rather than treating every
  provider label as a local-password ban. Honor REQUIRE_2FA off/admins/all for password
  accounts, including an account promoted to admin after token issuance.
- Recheck the method, services and admin snapshot in the atomic token insert. A policy
  denial removes observed web/API credentials, so restoring the prior account state
  does not revive them. Preserve all source account metadata.
- Verify checked policy vectors, actual native/CLI password-route denial, durable
  issuance/revocation, admin promotion, live Mongo changes and pending setup. HTTP,
  secret, crypto and session/concurrent-counter tests pass. Update the older session
  fixture to require fresh login after credential revocation.
- This is a guard, not the completed two-factor flow: challenge/enrollment support,
  shared index metadata and Meteor session interoperability remain in TODO.

## 2026-11-16 Argon2 secret policy and token binding

- Keep the default empty-secret Meteor policy and add optional operator-selected binary
  `WELITE_ARGON_SECRET_FILE` input. Read 1–65,536 bytes without trimming; reject missing,
  empty or oversized configured files. Unix reads require a private regular file,
  reject symlinks/FIFOs and validate the opened inode; other targets use file sharing/ACLs.
- Capture a credential binding from the same secret snapshot used to verify a password.
  With a configured Argon2 secret, use a domain-separated HMAC fingerprint; otherwise
  preserve existing SHA256 bindings. Recheck the current binding at token issuance and
  validation, and remove rejected web/API credentials so observed rotation cannot revive
  them after restoration. Never retry an empty secret or bcrypt fallback.
- Verify exact secret bytes and HMAC markers against the official C reference/Python,
  including NUL/high-bit/newline bytes, 64 KiB and malformed/private-file cases. Test
  actual linked/CLI web/API login, rotation between proof and issuance, cross-process
  bearer validation, missing/empty secret denial, durable revocation and bcrypt isolation.
- Live FerretDB account verification preserves BSON; native/CLI HTTP and durable-token
  crypto regressions pass. Secrets and their paths are not stored in account metadata.
  Broader Mongo account/index/session policy remains in TODO.

## 2026-11-16 Legacy Argon2 compatibility

- Add explicit v16 derivation alongside default v19. Include the selected version in
  parameter hashing and use the legacy overwrite rule instead of subsequent-pass XOR.
  Keep the same validation, resource budgets and memory clearing.
- Accept explicit v16 PHC strings and versionless legacy strings (defined as v16).
  Reject unknown versions and mismatched version/tag combinations rather than trying
  both algorithms. Preserve current v19 behavior and Argon2-before-bcrypt selection.
- Compare all d/i/id variants and both versions with the official C reference at
  f57e61e19229e23c4445b85494dbf7c07de721cb, built only as an isolated test oracle.
  Normal/checked tests cover secret/associated data, lanes/passes/memory rounding,
  legacy/versionless credentials and unsupported version denial. Go/RFC v19 tests pass.
- Verify actual explicit-v16/versionless web/API logins on linked/CLI SQLite, including
  bearer validation and unchanged service metadata. Live FerretDB reads preserve BSON
  exactly during verification. Runtime remains pure Pascal with no C library dependency.
- Out-of-band secret policy and broader Mongo session/index integration remain open.

## 2026-11-16 Argon2 v19 credential verification

- Parse Argon2d/i/id PHC v19 strings with canonical unpadded base64, unsigned decimal
  parameters and optional associated data. Reject duplicate/unknown parameters,
  malformed padding/bits, short salt/hash values, unsupported versions and oversized
  records before expensive derivation. Bound structural splitting as well as output.
- Verify Meteor Argon2 objects over the SHA256 plaintext digest and compare tags in
  constant time. Keep Argon2 precedence over bcrypt even when parsing, resource checks
  or verification fails. Preserve credential metadata and existing token binding.
- Add explicit memory/pass/lane/key verification budgets with operator environment
  overrides. Reject rather than reduce stored costs; verify a higher-memory record
  only after raising its configured budget.
- Match Go-generated PHC fixtures in normal/checked builds, including associated data,
  long UTF-8/NUL passwords, malformed/duplicate records and budget changes. Both linked
  and CLI HTTP suites pass actual Argon2 web/API login and token revocation; live
  FerretDB accounts verify without BSON changes. Bcrypt/legacy oracle tests still pass.
- Keep legacy v16/out-of-band secret policy and broader shared session/index integration
  open. New account generation remains Meteor-compatible bcrypt.

## 2026-11-16 Portable Argon2 memory processing

- Implement Argon2 v1.3 d/i/id key derivation: parameter hashing, first-block expansion,
  BlaMka mixing, dependent/independent addresses, cross-lane indexing, subsequent-pass
  XOR and final lane reduction. Process synchronized slices sequentially for portability;
  retain logical lane semantics without requiring OS worker threads.
- Preserve original memory cost in the parameter hash while rounding allocated blocks
  to the required lane/slice multiple. Include secret/associated-data inputs and explicit
  little-endian block conversion. Clear allocated blocks and temporary state on exit.
- Require caller-supplied resource limits and check them before allocation; validate
  minimum memory/salt/key sizes and platform byte-count bounds. Default kernel limits
  cover 64 MiB, 16 passes, 64 lanes and 1 KiB keys without silently reducing parameters.
- Match maintained Go source and all three published RFC 9106 tags in normal and checked
  Pascal builds. Verify memory rounding, address boundaries, multiple lanes/passes,
  binary/Unicode/NUL inputs, a 64 MiB profile, budget denial and graceful allocation failure.
  Underlying BLAKE2b/H' oracle tests pass again.
- Keep PHC credential parsing, verification policy and login integration open; Argon2
  account login remains disabled until those steps are verified.

## 2026-11-16 Portable Argon2 hash foundation

- Implement unkeyed BLAKE2b and Argon2's variable-length H' in Pascal as the hashing
  foundation for shared Argon2 credentials. Use explicit little-endian byte loading/
  output and modulo-64-bit arithmetic, with no native crypto library or assembly.
- Preserve final-block handling for empty, exact-block and partial inputs, and the
  distinct digest-size parameter and length prefix required by H'. Preallocate output
  instead of repeatedly concatenating growing hashes; clear temporary working state.
- Compare BLAKE2b with Python hashlib and H' with the actual maintained Go Argon2 helper,
  using isolated cached source copies and a temporary overlay. Verify normal/checked
  Pascal builds, binary/Unicode/NUL input, input block boundaries and variable outputs
  through 1 KiB. Invalid digest lengths are rejected.
- Keep Argon2 incomplete in TODO: memory-block filling/indexing, credential parsing,
  resource checks and login integration still remain.

## 2026-11-16 Shared-format credentials for new accounts

- Make registration and local admin bootstrap create Meteor services.password bcrypt
  objects by default, using SHA256 plaintext digests, cost 10 and independent random
  salts. Bind the initial session to the complete serialized password object.
- Change `hashpw` output to the same JSON object for direct embedding at
  services.password. Update seed instructions to avoid quoting the object as a string.
  Keep existing PBKDF2 string verification and leave stored legacy records unchanged.
- Verify new registration/bootstrap object shapes and salt independence, long UTF-8
  plaintext, CLI JSON seeding, password-change token revocation and legacy web/API
  logins against an independently generated Python PBKDF2 record. Update the token
  binding test to hash an object credential correctly.
- All HTTP regressions pass on linked SQLite and CLI SQLite, with the CLI build forced
  through portable one-use entropy. Argon2, shared Mongo session/index policy and
  application storage activation remain open.

## 2026-11-16 Portable Meteor bcrypt credentials

- Add a pure Pascal bcrypt kernel with explicit modulo-32-bit Blowfish arithmetic,
  canonical salt/hash parsing, 2a/2b/2y support and constant-time hash comparison.
  Adapt maintained Go crypto expansion/constants with their BSD license retained.
  No platform crypto library or external password service is required at runtime.
- Verify Meteor services.password JSON objects using bcrypt over the SHA256 plaintext
  digest. Retain legacy Welite PBKDF2 verification and add a fresh-salt cost-10 Meteor
  credential generator. Reject malformed/duplicate-key envelopes; a nonempty Argon2
  credential takes precedence and is denied until supported, never falling back to
  potentially stale bcrypt. Existing default account creation is unchanged in this step.
- Verify against the independent Go implementation with normal and checked Pascal
  builds: several costs, versions, Unicode/NUL/72-byte inputs, malformed hashes, long
  Meteor plaintext, fresh salts and legacy credentials. Exercise real web/API logins
  and credential-bound tokens on both SQLite backends, plus byte-preserving reads of
  an actual FerretDB account. Existing HTTP regressions pass.
- Keep Argon2, default shared-format credential creation, Meteor resume-session/index
  policy and application activation open in the interoperability checklist.

## 2026-11-16 Account uniqueness and unambiguous login

- Derive non-primary unique keys from the canonical schema and enforce them in SQL
  model insert/update triggers. Check the fully typed projection so clone sources
  cannot bypass username uniqueness. Preserve BINARY case comparison and nullable
  username behavior; refuse existing duplicates during adapter preflight.
- Use one account lookup for web/API login. Require exactly one matching username,
  counting disabled matches too, then check its enabled state. Direct Mongo duplicates
  can no longer cause an arbitrary first account to be selected.
- Verify duplicate inserts/updates/source clones, NULL/case behavior, four concurrent
  writers, duplicate-source reinstall refusal and recovery, disabled/ambiguous lookup
  denial and record preservation on both SQLite backends. Linked/CLI HTTP application
  regressions and the source-codec/extension tests pass.
- Keep Mongo index provisioning and Meteor account/session compatibility as separate
  integration work; these SQL guards do not introduce a new Mongo uniqueness policy.

## 2026-11-16 Private tokens with FerretDB user views

- Install owned private `login_tokens` and `authmeta` tables alongside document views.
  Replace the invalid foreign key to a user view with explicit token insert/update
  checks; retain the real metadata-to-token foreign key. Refuse unowned or structurally
  changed private objects rather than overwriting them.
- Remove private tokens and metadata after physical user deletion, whether initiated
  by Welite SQL or Mongo. Explicit metadata cleanup also works with foreign keys off
  on the deleting connection. Keep tokens across compatible adapter reinstallation.
- Exercise the actual token issue/validate code against both adapters: restart-safe
  validation, credential changes, missing users, SQL/Mongo deletion and cleanup with
  foreign keys off. Force a Mongo cleanup failure and verify user/token restoration.
  Codec/extension and existing SHA/HMAC/durable-token regression tests also pass.
- These remain Welite private tokens, not Meteor resume tokens. Shared password/session
  compatibility, username uniqueness and application activation are still open.

## 2026-11-16 FerretDB view references and delete cascades

- Generate root foreign-key metadata directly from the canonical schema. Reject SQL
  inserts and reference-column updates that point at missing parent models, including
  typed clone-source inserts. Preserve nullable-reference semantics.
- Reproduce declared root ON DELETE CASCADE chains through writable views: deleting a
  board removes its lanes/lists/cards/comments, with card/checklist descendants removed
  recursively. Embedded children disappear with their owning document. Retain records
  whose references are deliberately not foreign keys in the schema.
- Verify every declared root reference on insert/update against live FerretDB, optional
  NULL references, unrelated-record retention and nested cascades on both backends.
  Force a checklist-item deletion failure and compare every collection's stored SJSON
  before/after to prove rollback of the complete board deletion. Source-codec tests pass.
- These checks govern Welite SQL views; no foreign-key triggers are added to FerretDB's
  physical tables. Account uniqueness/private-token references and other compatibility
  gates remain before application activation.

## 2026-11-16 Writable FerretDB child views

- Generate thirteen child contracts from the canonical SQL schema and install writable
  views for board labels/members/groups/domains, card membership/labels/custom values/
  dependencies, custom-field boards/dropdown items and user emails. Use actual `_id`
  fields and nested paths; correct dependencies to `cardDependencies`.
- Apply one sparse patch per SQL row update, including simultaneous key/value changes.
  Preserve unknown child properties and BSON metadata. Match omitted optional dependency
  types using their defaults; reject duplicate child keys, invalid booleans, missing
  parents and parent reassignment.
- Install root and child views in one transaction, refuse unowned child tables/views,
  and retain custom child-view triggers across reinstallation.
- Verify every child view against live FerretDB on linked and CLI SQLite, SQL/Mongo
  updates in both directions, typed unknown data, failed inserts and ownership refusal.
  Source-codec tests pass again. Cascades, full typed custom-value conversion, shared
  account/file support and application activation remain open.

## 2026-11-16 Typed embedded relation editing

- Add the shared `wl_relation` SQL function for sparse insert/update/delete of embedded
  object and scalar arrays, including nested array paths. Preserve sibling order,
  unmodeled member fields and existing BSON metadata instead of rebuilding arrays
  from flattened SQL rows.
- Validate required values and booleans; reject duplicate keys, missing update/delete
  targets, unknown patch columns and malformed source arrays. Return an SQL error so
  failed statements cannot partially replace documents.
- Verify real FerretDB reads after linked/CLI relation writes, including typed nested
  dates/int64, default values, Unicode scalar keys and byte-exact BSON after denial.
  Re-run the source-codec and TEXT/JSONB tests. Child SQL views, reference constraints
  and application integration remain to be wired before interoperability is complete.

## 2026-11-16 FerretDB root document projections

- Generate eleven root-model specifications from the canonical schema and install
  writable SQL views over actual registered FerretDB collections. Discover physical
  names, create compatible metadata/indexes for missing collections, and refuse
  unowned normalized tables. Preserve physical records, indexes and custom view triggers.
- Apply sparse typed patches, preserving unknown fields, BSON types and numeric bits.
  Map nested attachment parents/WIP settings, booleans, dates and JSON columns; validate
  required values and immutable IDs. Keep clone source metadata separate from child arrays.
- Resolve TEXT/JSONB storage at write time through the host SQLite metadata API, including
  the CLI's restricted trigger environment. Keep installation atomic and repeatable.
- Verify both directions over the Mongo wire against maintained FerretDB source
  984be0e8ee59afe5d19005336b81c76d44c0e695, on linked and CLI SQLite: all roots,
  fresh collections, old TEXT/restart, exact scalar bits, unknown fields and failed-edit rollback.
- Keep this installer outside application startup until child relations, account/file
  compatibility and shared-file policy are complete. Overall interoperability remains open.

## 2026-11-16 Large SQL scripts through the CLI backend

- Remove the per-argument size ceiling before installing the FerretDB model adapter.
  Feed the SQLite shell a private `query.sql` through its structured `-init` filename
  option; user SQL and values never become process arguments. Preserve the caller's
  working directory for relative ATTACH/VACUUM paths.
- Share short temporary-directory allocation with framework uploads. On Unix, reserve
  directories as 0700 and SQL files as 0600; delete script bytes and the directory after
  success, SQL failure or failure to spawn the CLI.
- Preserve control-containing string literals as parenthesized hex-to-TEXT expressions,
  avoiding the shell's physical CRLF normalization and expression-depth limits for many
  newlines. Keep comments and quoted identifiers distinct, and reject shell dot commands
  in SQL input. Replace quadratic CSV field concatenation with a geometrically
  growing byte buffer.
- Verify megabyte inputs/outputs, 2,000 newlines, Unicode and quoted paths, multiline
  defaults, relative ATTACH paths, private modes, structured arguments and failure cleanup,
  plus typed SJSON, entropy, strict paths and existing HTTP/browser regressions.
  Model mapping remains open.

## 2026-11-16 FerretDB typed storage kernel

- Add a Pascal SJSON codec preserving BSON metadata, ordered keys, nested values and
  exact numeric literals. Explicit field hints cover new dates, int32, timestamps,
  binary subtypes and ObjectIDs. Reject malformed JSON/UTF-8/schema, duplicate keys,
  incompatible hints and out-of-range values instead of silently rounding integers.
- Register pure typed-document SQL functions in linked SQLite and expose the same code
  as an optional local CLI extension using the host API table. Failed extension loading
  blocks SQL execution. This does not yet switch application models to FerretDB storage.
- Verify actual FerretDB source encoding/decoding, all its scalar types, reordered arrays,
  Unicode/NUL text and exact double bits (including negative zero), plus transactional
  SQL-view edits of old TEXT/current JSONB records on both backends. Existing SQL, entropy,
  HTTP and no-JS/no-cookie browser workflows pass with the extension loaded.
- Keep the overall interoperability task open: collection/model mappings, shared accounts
  and files, filename policy and live application-level two-way tests remain.

## 2026-11-16 Framework upload scratch paths

- Route the FPC RTL temporary-file hook into atomically reserved short directories
  under the runtime data root. Multipart uploads retain 8.3 names and cannot race
  for a shared CGI temporary filename. A router try/finally explicitly closes and
  removes framework upload bytes and their private directories, including denied
  requests and handler failures; FPC destructors alone do not remove the files.
- Extend the runtime test to verify the framework hook ignores long system paths
  and prefixes. Re-run strict linked/CLI path and multipart HTTP/browser checks.

## 2026-11-16 Short runtime paths and offline data migration

- Store tenant databases under `files/db/wekan.db`, attachment bytes under `attachme`
  and avatars under `avatars`. Persist short domain keys in the reserved registry;
  preserve full names, aliases and IDs in SQLite. Hash full file IDs into short path
  components so case-sensitive IDs remain distinct on case-insensitive filesystems.
- Atomically allocate short temporary directories and skip pre-existing names. Add
  `WELITE_DATA` for selecting the runtime root. Refuse detected legacy layouts.
- Add `releases/pathmove.py`: copy legacy databases/bytes to a fresh verified tree,
  publish only after preparation succeeds and retain the original data unchanged.
- Add strict `WELITE_SHORT_NAMES=1` validation of `SQLITE_ENABLE_8_3_NAMES=2`, including
  actual live WAL/SHM/journal filenames. Every database client must use the same policy.
  Use one CLI initialization argument to retain query execution on SQLite 3.54.1.
- Verify durable domain keys, restart and temp collisions, migrated row/byte retention,
  unsafe migration refusal, attachment upload/download/delete and full HTTP workflows
  with linked and CLI backends. Real retro filesystem verification remains pending.

## 2026-11-16 Optional selected-card and multi-touch dragging

- Activate local vendored InteractJS on editable boards while retaining checkbox and
  arrow controls. Drag one card or its checked-card group to a visible list/lane cell.
- Support disjoint simultaneous pointer selections. Serialize drop requests and refresh
  the single-use counter/MAC from each redirected form before the next queued request.
  Use the explicit form action attribute so action buttons cannot shadow its URL.
- Extend `/board/move` with validated same-board destination cells and atomic append
  of selected cards. Preserve existing session, write permission and token checks.
- Verify target ownership/lane rejection, rollback on SQL failure and replay refusal,
  plus Chromium real-pointer selection dragging and simultaneous two-finger moves with
  cookies absent. Existing JavaScript-disabled browser flows pass independently.
  Physical touch-display and retro-browser verification remains on the platform list.

## 2026-11-16 Fail-closed native and portable entropy

- Remove the weak Random fallback from password salts and authentication tokens.
  Use OS randomness or an explicitly configured private one-use SQLite entropy stock.
- Add `welite entropy random.db [bytes]` for offline provisioning from a supported
  host. Atomic committed deletion prevents concurrent consumers from reusing blocks;
  exhaustion, missing files and database failures refuse to return entropy.
- Withhold linked SQLite RETURNING rows until SQLITE_DONE succeeds, including deferred
  foreign-key commit failures. Add busy timeouts and portable rollback-journal stocks.
- Verify Linux OS randomness and forced OS-less consumption on linked/CLI backends,
  concurrent fresh processes, private-file generation, refusal to overwrite, invalid
  and exhausted stocks, and SQL failures. Target-specific native API verification
  remains in the cross-platform checklist. Full HTTP regressions pass with native RNG;
  all no-JS/no-cookie Chromium flows also pass with OS randomness disabled and a
  fresh stock through CLI SQLite.

## 2026-11-16 Cryptographic tokens, durable binding and trusted proxies

- Replace FNV with SHA-256 token/credential digests and HMAC-SHA-256 action tokens using
  an independent server-only key and unambiguous JSON context. MAC comparisons scan all
  bytes of equal-length values. Legacy weak token records have no acceptance fallback.
- Add supplemental `authmeta` binding and tenant-scoped token digests. Durable API tokens
  survive process restart, reject copied databases/credential changes, and revoke on a
  detected credential mismatch. Web tokens used in API calls retain client/idle checks.
- Ignore forwarded IP headers by default. `WELITE_TRUSTED_PROXIES` lists exact proxy IPs;
  validation walks the forwarded chain from the nearest trusted hop and normalizes IPs.
- Verified SHA/HMAC against independent Python/RFC 4231 vectors, source-wide weak-hash
  guards, proxy spoof/chain cases, fresh-process persistence and credential/tenant binding,
  plus live MAC tamper/client checks and all no-JS/no-cookie browser flows on both backends.
- Existing sessions require fresh sign-in after the digest change. Portable entropy is
  still tracked separately because the previous non-Unix `Random` fallback remains.

## 2026-11-16 Disabled-account revocation and session integrity

- Refuse disabled accounts at web/API sign-in and every token lookup. Disabling through
  People revokes durable tokens in the same transaction as the flag; re-enable keeps those
  tokens revoked. Login token persistence failures return an error instead of false success.
- Bind web metadata to the exact database, persisted user/username and password-hash
  marker; failed validation returns an empty identity. JSON metadata preserves Unicode and
  delimiter characters, and fresh login nonces replace username/time-derived session IDs.
- Lock metadata validation/counter consumption so concurrent submissions cannot reuse a
  mutation token or overwrite a newer counter. Enforce a 30-minute idle timeout (override
  `WELITE_SESSION_IDLE` in seconds), revoking expired web tokens; compare timestamps in UTC.
- Verified disabled login/live-token denial, actual panel revocation/re-enable, fresh login
  and forced persistence failures over HTTP. Native tests cover copied DB/token IDs,
  credential/client binding, empty failure identity, 16 competing token consumers and idle
  expiry with both SQLite backends.
- The audit also identified remaining FNV hashes/MACs, retro entropy fallback and API
  credential/tenant/proxy binding work. These remain explicit TODOs; this step does not
  claim to finish cryptographic or all-platform authentication hardening.

## 2026-11-16 Validate API relation IDs and author attribution

- Validate card label/member/assignee collections before creation or edits. Labels must
  belong to the board; user targets must be enabled active board members. Arrays and
  comma-separated strings support deduplication and explicit clearing.
- Apply card text/relations in one transaction and report write failures. Invalid mixed
  collections or SQL errors leave both existing cards and attempted new cards unchanged.
- Validate path-based member/assignee additions too; deletion remains available to remove
  stale associations. Ordinary editors can attribute cards/comments to themselves; tenant
  admins may explicitly attribute them to an enabled member of the same board.
- Reject malformed/non-object JSON before API writes. Verified foreign/missing/disabled/
  inactive targets, author forgery, clear/dedup formats, malformed JSON and forced SQL
  failures against both SQLite backends. Disabled-login/session audit remains in TODO.

## 2026-11-16 Deep selected-item cloning

- Enable Clone for selected cards, lists and swimlanes. Coalesce overlapping selections,
  copy their content/descendants, and remap list/lane/parent/checklist/comment/cover and
  internal dependency IDs while retaining shared board labels, fields and external targets.
- Append copied items deterministically, assign new card numbers, and record clone events
  under the acting user. Historical activities stay with the original entities.
- Copy filesystem attachment bytes before one database transaction; missing files,
  unsupported storage backends or SQL failures remove prepared copies and leave original
  rows/bytes unchanged. Existing filesystem targets are never deliberately overwritten.
- Initialize UTF-8 conversion explicitly: the host's unset Pascal codepage was turning
  non-ASCII JSON strings into question marks. Cloning/import regressions now pin Unicode
  fidelity, with embedded NUL text preserved through SQL hex literals when needed.
- Verified mixed/card/list/swimlane clone variants, child IDs, shared references, covers,
  original row preservation, byte copies, replay rejection and file/SQL rollback. HTTP and
  Chromium Clone workflows pass with JS/cookies disabled on both SQLite backends.

## 2026-11-16 Selected-item editing, deletion, clearing and export

- Enable selected-item Edit/Save forms for swimlane/list/card titles and colors, plus card
  descriptions. Validate the complete form before one transactional update; failed SQL
  rolls back all selected edits.
- Add explicit Delete confirmation, then remove selected containers, descendant cards,
  child records, activities and attachment metadata transactionally. Unlink filesystem
  attachment bytes only after commit, so rollback never removes live attachment content.
- Add Clear (including stale selections) and `select.jsn` export of selected entities,
  related records and base64 filesystem attachment content. Account/token data is excluded.
- Read-only downloads retain the visible form's token, allowing the next no-JS action;
  mutations still consume it. Mixed-case selection names now use the same ownership policy
  as movement, closing an authorization/selection parsing mismatch.
- Verified HTTP data/bytes, descendant cleanup, bad fields and forced edit/delete failures,
  plus Chromium Edit/Save/Export/Clear/Delete workflows with JS/cookies disabled on both
  SQLite backends. Deep Clone remains a separate unfinished TODO and stays hidden.

## 2026-11-16 Atomic, validated Designer imports

- Share page/widget validation and span rules between forms and imports. Decode and
  validate all content before replacing existing pages, then execute one transaction.
- ZIP imports validate every page, duplicate URLs, entry names and the manifest before
  committing the whole bundle. A malformed page or SQL error leaves every old page intact;
  ZIP entry streams never fall back to filesystem extraction.
- Add working no-JS upload/export forms and authenticated raw JSON imports using the
  same action token in `X-Welite-Action`, `X-Welite-Counter`, `X-Welite-Hash` headers.
- Export disabled pages too; use `page.wlp`, `pages.zip`, and numbered DOS 8.3 bundle entries.
- Verified invalid models, traversal/duplicate/manifest errors, token replay and forced SQL
  failures (including failure on the second ZIP page) without database changes. JSON/ZIP
  browser upload/download and round trips pass with JS/cookies disabled on both backends.

## 2026-11-16 Render Designer spans and cell ordering

- Render row/column spans once in published and editor grids, suppressing covered cells
  and using the same logical rectangles for LTR/RTL. Reject overlapping spans during
  widget save/move and inconsistent spans among widgets sharing an anchor cell.
- Add Sort up/down buttons that reorder widgets inside their cell transactionally,
  normalizing sort positions so tied values also have deterministic ordering.
- Emit required attributes and visible required markers for input widgets. Browsers
  without native constraint validation still show the marker; endpoints retain their
  own validation responsibilities.
- Honor explicit page direction and avoid double-mirroring in modern browsers by fixing
  the grid's physical direction while retaining per-cell text direction.
- Verified HTTP span/overlap/required/sort/direction cases and Chromium physical RTL,
  spanning cells and sort-button submissions with JS/cookies disabled on both backends.

## 2026-11-16 Separate Global Admin and domain administration

- Reserve the central domain registry for administrators authenticated in `data/admin`;
  administrators of `local` and served domains retain only their own People/Designer panels.
  Navigation and role labels now distinguish Global Admin from Domain Global Admin.
- Add local `welite initadmin <username>` bootstrap using `WELITE_ADMIN_PASSWORD`, refusing
  repeat initialization. Public registration never creates accounts in the reserved tenant.
- Provision new registered domains explicitly, applying the portable schema transactionally
  even when the registry DB already exists. Reject reserved/malformed domain names and
  match loopback hosts exactly instead of accepting attacker-controlled substrings.
- Verified local bootstrap, tenant/session separation, domain creation, disable/enable,
  malformed names and spoofed loopback hosts against both linked and CLI SQLite servers.
  Operational instructions are in `docs/admin.md`.

## 2026-11-16 Verify fresh linked and CLI server installations

- Keep SQL beginning with `--` comments from being parsed as SQLite command-line options;
  this fixes automatic schema provisioning and first registration on the CLI backend.
- Added the leading-comment regression and a `WELITE_DB_CLI=1` HTTP/browser test mode.
  The valid-card ownership assertion now follows the card's actual list after UI movement.
- Verified fresh linked and CLI installations through registration, Designer page/widget
  forms, board rendering/movement/minimap and 29 rejected API ownership attempts. Both
  Chromium runs disable JavaScript and cookies; all accumulated Pascal DB/move/role tests pass.

## 2026-11-16 Enforce API resource ownership

- Added a shared child-resource chain check after board authorization: swimlane/list/card,
  checklist/item/comment and custom-field IDs must belong to the board and parents named
  in the route, including when the caller is a site administrator.
- Validate card/attachment upload parents before writes. Board-scoped list/swimlane card
  queries, counts and deletes also constrain boardId, protecting against inconsistent
  legacy child rows.
- Verified 29 forged-resource requests across endpoint families return rejection without
  any database change, while the valid card remains readable. Added source-wide guard
  coverage so another child endpoint cannot silently omit ownership checks.
- Body label/member/assignee/author validation and disabled-login/session behavior remain
  explicit follow-up steps in TODO.

## 2026-11-16 Board minimap and coordinate navigation

- Added a top-right, server-rendered minimap with occupied/empty markers, a yellow
  current position and X/Y coordinates. Each cell is a session-preserving navigation link.
- Board pages default to one list in one swimlane for small-screen/retro use; view arrows
  change that window and View all restores the full-board selection surface.
- Clamp coordinates to existing rows/columns and preserve the viewport on form submission.
- Verified map links, occupancy changes after moves, highlight, out-of-range coordinates
  and all-items view. Chromium tests pass at widths 320/768/1920 with no horizontal
  overflow in the fixture, with JavaScript and cookies disabled. Retro devices still
  require the platform-specific checks listed in TODO.

## 2026-11-16 Authorized board views and no-JS card movement

- Added real board links on the home page and registered Designer board/board-list
  dataviews. Board pages render active swimlanes, lists and cards with escaped text.
- Full editors receive one selection form with board ID, action token, return path and
  shared arrow controls. Other viewers see board data without mutation controls.
- Scope neighbor/card-list queries to the board and swimlane, include legacy shared
  lists, and deduplicate repeated selections. RTL board pages reverse list columns.
- Verified HTTP visibility/controls and Chromium selection-to-right-arrow card movement
  with JavaScript and cookies disabled, including the resulting persisted list ID.
- Unfinished action buttons remain hidden until their handlers are implemented. Minimap,
  responsive retro color verification and optional drag/drop remain separate TODO steps.

## 2026-11-16 Shared board permissions and move selection isolation

- Added shared board read/write checks used by UI visibility, move authorization and
  API board guards. Private boards require active membership; full-board mutations
  exclude read-only, comment-only, assignment-limited and worker roles.
- Move requests require a validated session and an explicit board; every selected card,
  list and swimlane must exist, be active and belong to that board before any mutation.
- Restrict move return URLs to local paths and prevent anonymous home-page disclosure
  of private board titles. Unknown/archived boards and disabled admins cannot write.
- Verified both SQLite backends against a role/selection/redirect matrix and live API
  editor/read-only/comment-only requests. Separate API child-ID scoping remains in TODO.

## 2026-11-16 Reliable CLI SQLite results and errors

- Use FreePascal's process runner to drain stdout/stderr while SQLite runs and check
  its exit code. Syntax, constraint and foreign-key failures now return false.
- Use SQLite CSV output instead of splitting on pipes/newlines; preserve quoted commas,
  pipes, quotes, UTF-8 and embedded CRLF/LF while retaining empty/NULL text semantics.
- Verified both SQLite backends with executable Pascal text/error regressions and a
  5,000-row result larger than pipe capacity. Existing move and Designer HTTP tests pass.
- Reference: SQLite CLI output modes (`https://www.sqlite.org/cli.html`) and the
  FreePascal `TProcess`/`RunCommand` implementation in the installed FCL sources.

## 2026-11-16 Working Designer widget editor

- Added full no-JS widget forms and persisted creation, updates and deletion, with
  administrator gates, matching action tokens and session-preserving editor redirects.
- Validate widget types, JSON options, finite sort values, colors, local targets and
  row/column/span bounds; reject moving a widget between unrelated pages.
- Move controls derive the owning page from the widget and clamp to its column and row
  limits. Select widgets render escaped option labels/values and the selected value.
- Verified widget operations, negative inputs and movement bounds over HTTP and through
  Chromium with JavaScript and cookies disabled. Recorded separate remaining work for
  published spans/required inputs, cell-sort arrows, import validation and CLI DB fidelity.

## 2026-11-16 Working Designer page management

- Added page listing, creation, editing by ID (including disabled pages), enable/disable
  and deletion with cascading widget removal, using plain forms and action tokens.
- Provision Designer tables on first administrator access without replacing existing
  pages; schema statements are idempotent. `WELITE_DESIGNER` overrides `src/designer.sql`.
- Validate local URLs, reserved routes, columns, document type, direction and access role;
  reject duplicate URLs and column changes that would hide widgets. Published admin pages
  now require the actual administrator role; invalid sessions cannot retain page access.
- Verified page workflows, invalid inputs, authorization and deletion over HTTP, plus
  Chromium form create/edit/disable/enable/delete with JavaScript and cookies disabled.

## 2026-11-16 Require administrator permissions throughout Designer

- Guarded every Designer listing, editor, import and export endpoint with the shared
  tenant-local administrator gate. Mutations also require their action token.
- The gate now checks session validation's Boolean result, so revoked tokens and wrong
  client bindings cannot reuse residual session fields. Disabled users cannot administer.
- Verified all eight endpoints over HTTP with no cookies: anonymous, normal user,
  invalid session, mismatched client, administrator, missing action token, demotion,
  disabled account and revoked token cases (`tests/admin.py`).
- Recorded the remaining distinction between reserved-host Global Admin domain management
  and tenant-local administration in `TODO.md`; this step only secures Designer access.

## 2026-11-16 Move lists across swimlanes

- Implemented up/down list movement to adjacent active swimlanes on the same board,
  appending after existing lists and moving all list cards, including archived cards.
- List/card updates share one transaction in both SQLite backends. Boundary, archived,
  missing and legacy lists remain unchanged; other-board cards cannot be reparented.
- Verified executable Pascal regressions with `tests/movelist.py`, using the canonical
  schema and both linked and CLI SQLite backends, including multi-list movement.

## 2026-11-16 Implementation audit and remaining steps

- Added a sequential, testable implementation checklist to `TODO.md`, preserving the
  original design requirements and distinguishing existing code from remaining work.
- Confirmed password hashing already exists; identified unfinished board rendering,
  Designer handlers/permissions, move actions, minimap and progressive enhancement.
- Removed the duplicate repository instruction file; parent repository instructions
  apply here, while the existing build layout and DOS 8.3 rules remain documented below.

## 2026-06-25 Local tenant, registration / Global Admin, Admin Panel, build layout

First-run usability: browsing `http://localhost:5500/` used to answer `404 Unknown domain`
because `localhost` matched no registered domain. Added a built-in tenant, an account/registration
flow, a Global Admin Panel, and reorganized the build output. Verified on FreePascal 3.2.3 (aarch64).

- **Built-in `local` tenant** (`wltenant`): loopback hosts (`localhost`, `127.0.0.1`, `::1`) now
  resolve to a `local` tenant stored at `data/local/` (`db/data.db`, `files/attachments`,
  `files/avatars`), auto-provisioned on first request from `src/schema.sql` (override with
  `WELITE_SCHEMA`). The reserved `admin` registry dir is also created up front so a fresh checkout
  just works; unknown domains still 404 with no fallback.
- **Registration + first-user Global Admin** (`wlhttp.lpr`): `GET /` redirects to `/sign-in` when
  the tenant has no users; new `/register` page (no-JS/no-cookie) creates an account, the **first**
  account in a tenant becomes the Global Admin (`users.isAdmin=1`) and the rest are Normal users.
  Sign-in/home pages cross-link to register; passwords hashed via the existing PBKDF2 path.
- **Global Admin Panel** (new `wladmin` unit): gated to `users.isAdmin=1` (404/redirect/403 as
  appropriate) with three sections — **Domains** (registry add / enable / disable, via new
  `wlregist.RegistryListDomains`), **Designer** (links to the existing `/designer`), and **People**
  (promote/demote Global Admin, enable/disable login; cannot self-demote or self-lock-out). Same
  action-token + PRG contract as the rest of the app.
- **Build output layout** (`build.sh`/`build.bat`/`build.ami`): each target now builds into
  `build/arch/<code>/` (executable + `.o`/`.ppu`/link intermediates via `fpc -FU -FE`), then copies
  the executable to `build/bin/w<code>.exe` — a `w` prefix plus a ≤7-char platform code
  (`wlinx64.exe`, `wdos.exe`, `wami68k.exe`, …) so every path component stays ≤8 chars and the
  binaries are unique in one directory. "Build current platform" → `build/bin/wcurrent.exe`.
- **Cross-compiler installer** (`build.sh` menu option 4, Ubuntu/Debian amd64/arm64): apt can't
  provide FPC cross-compilers (none packaged, `fpc-source` is stripped of the build Makefiles,
  exotic OSes have no Ubuntu binutils), so this uses
  [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe). Preferred path: apt-install
  Lazarus (`lazbuild` + nogui LCL), build fpcupdeluxe's real headless console tool `fpclazup`
  (`LCLWidgetType=nogui`, forced to the host CPU/OS), then run it to build the FPC compiler + cross
  compiler/binutils per target — Amiga/AROS/MorphOS/Haiku/macOS as well as Linux/Windows/DOS — and
  point the session `FPC` at the result. Getting this working on Ubuntu 26.04 needed several
  pieces, all handled automatically: seed the bootstrap compiler from the system FPC; `--disablejobs`
  (the parallel RTL build races); `--fpcVersion=fixes-3.2` (FPC 3.2.2 doesn't link on glibc ≥2.34,
  which removed `__libc_csu_init/_fini`); `--only=FPC` (skip Lazarus/LCLCross); and treat "a working
  `fpc` binary exists" as success rather than fpclazup's exit code. `do_build` also exports
  `PPC_CONFIG_PATH` next to the chosen `FPC` so the fpcupdeluxe `fpc.cfg`/units are used (the static
  compiler otherwise falls back to the system `/etc/fpc.cfg`). If the build path can't be set up it
  falls back to launching the fpcupdeluxe GUI. The install dir is kept outside the repo
  (default `~/fpcupdeluxe`); fpcupdeluxe derives its basedir from the working dir and aborts if that
  is inside another git repo. Verbose log to `build/log/xtools.log`, per-target pass/fail.
- **Cross-target sweep + per-target flags**: swept all 18 cross targets (install cross FPC, then
  cross-build welite) on an aarch64 host. Working there: `x86_64-linux`, `arm-linux`, `i386-win32`,
  `x86_64-win64` (plus native `aarch64-linux`); the rest fail because fpcupdeluxe ships no
  aarch64-host cross-binutils/libs for them (they work from an x86_64 host). welite's default build
  links `libsqlite3`, which can't be cross-linked, so every non-Windows `PLATFORMS` entry now carries
  `-dWLDB_CLI` (external `sqlite3`, links nothing); Windows keeps the linked default (runtime DLL).
  armhf/armv7's hard-float flags clash with fpcupdeluxe's soft-float arm RTL ("different FPU mode").
  Each `PLATFORMS` row is annotated with its host requirement; "Build for current platform" still
  builds the native linked-SQLite default.
- **`CLAUDE.md`**: documents the DOS 8.3 filename rule (≤8-char names, ≤3-char extensions, safe
  charset, tooling exceptions) with an audit snippet, plus the build-output layout. Audited the
  tracked tree: zero 8.3 violations outside host tooling (`.gitignore`, `.tx/`).

## 2026-06-25 WeKan-Lite — `welite` rename, DOS 8.3 names, build scripts

Renamed the repo/binary to `welite` and made the whole tree DOS 8.3-safe (≤8-char names,
≤3-char extensions, one dot) so the sources copy onto a FAT filesystem and compile there.

- Added cross-platform build scripts at the repo root — `build.sh` (bash), `build.bat`
  (cmd.exe), `build.ami` (AmigaDOS) — each a 4-item menu (current platform / all / select /
  quit) that builds `src/wlhttp.lpr` with FreePascal for Linux amd64/arm64/armhf/armv7/s390x/
  ppc/ppc64le, macOS arm64, Windows x86/amd64, DOS (go32v2), Haiku, Amiga m68k, AmigaOS 4.1 PPC,
  MorphOS, and AROS x86/amd64/arm64/m68k/ppc. Output to `build/` (gitignored).
- Rebrand `wekanlite` → `welite`: binary name (also fixes its own 8.3 overflow, 9→6 chars),
  env vars `WEKANLITE_*` → `WELITE_*`, repo URL, `.gitignore`, and the designer export JSON keys
  (`welite_page` / `welite_pages`). The human product name **WeKan-Lite** is unchanged.
- 8.3 source renames (FPC unit name = filename): `wlbrowser`→`wlbrowse`, `wldesigner`→`wldesign`,
  `wlenhance`→`wlenhanc`, `wlpassword`→`wlpasswd`, `wlregistry`→`wlregist`,
  `designer-schema.sql`→`designer.sql`; designer export ext `.wlpage`→`.wlp`, zip index
  `manifest.json`→`manifest.jsn`; the glue script `wl-multidrag.js`→`wlmdrag.js`.
- 8.3 docs: `architecture`→`arch`, `sqlite-access-decision`→`sqlite`, `move-component`→`move`,
  `progressive-enhancement`→`enhance`, `static-assets`→`static`, `schema-decision`→`schema`,
  `web-stack-decision`→`webstack`; `CHANGELOG.md`→`CHANGES.md`; dirs `docs/multidrag`→`docs/mdrag`,
  `docs/roundcard`→`docs/round` (`.html`→`.htm`, `round-blue.gif`→`rndblue.gif`).
- 8.3 helper scripts: `genassets.py`→`genasset.py`, `convert-languages.py`→`convlang.py`,
  `changelog.sh`→`chglog.sh`, `releases/translations/`→`releases/xlate/`
  (`push-translation.sh`→`txpush.sh`, etc.).
- 8.3 translations: `i18n/languages.json`→`i18n/langs.jsn`; all 154 `i18n/data/<tag>.i18n.json`
  → `<tag>.jsn` (`ca@valencia`→`cavalenc.jsn`); updated the import index, `.tx/config`, and the
  `.jsn` MIME mapping in `wlstatic`.
- 8.3 static assets: `public/windows11/`→`public/win11/` (tiles renumbered `w001..w080`),
  `public/font/notification/`→`.../notif/`, `wekan.html`→`wekan.htm`,
  `interact-bottom.js`→`interbot.js`, `site.webmanifest.default`→`manifest.def`, and ~120
  favicon/PWA icons given short names; `manifest.def` (the PWA manifest) rewritten to match.
- Verified on FreePascal 3.2.3 (aarch64): builds clean, repo-wide 8.3 check passes, and the
  server serves the renamed URLs (`/i18n/langs.jsn`, `/i18n/data/en.jsn`, `/win11/w001.png`,
  `/js/interbot.js`, `/manifest.def`). DOS cross-compile additionally needs the FPC i386/go32v2
  cross build installed.

## 2026-06-25 WeKan-Lite — minimal `welite` repo

Split WeKan-Lite into its own minimal repo, https://github.com/wekan/welite (only the
required files), out of the old `wami2` tree where it lived under `freepascal/`.

- Moved the `freepascal/` contents to the repo root: FreePascal units, `wlhttp.lpr`, and the
  `*.sql` schemas now live in `src/`; design docs in `docs/`; static assets in `public/`.
- Split translations into their own tree: `public/i18n/` → `i18n/data/`, and
  `public/langs.jsn` → `i18n/langs.jsn`. `wlstatic` now serves `i18n/` as a second
  static root mounted at `/i18n` (`StaticAddRoot`), and `releases/genasset.py` embeds both the
  `public/` and `i18n/` trees, so translation URLs stay stable in disk and single-binary builds.
- Moved the build/release helper scripts under `releases/`: `genasset.py` (embed
  `public/` + `i18n/`) and `convlang.py` (regenerate `i18n/langs.jsn` from the
  sibling `../wekan` repo's `imports/i18n/languages.js`).
- Updated every cross-reference path to the new layout: `README.md`, `docs/*.md`, the FPC unit
  comments, `.tx/config` (`i18n/data/<lang>.jsn`), and the helper scripts' defaults.
- Refreshed `.gitignore` for the new binary name (`/welite`), the runtime `/data/` tree, and
  the generated embed artifacts (`src/wlassets.pas`, `src/wlpublic.{rc,res}`, `*.o` / `*.ppu`).
- Verified on FreePascal 3.2.3 (aarch64): the tree builds, and the server serves both roots —
  `/robots.txt` (public) and `/i18n/langs.jsn` + `/i18n/data/en.jsn` (translations).

## 2026-06-25 WeKan-Lite FreePascal — v0.1

First skeleton of the FreePascal backend. Compiles and links on FreePascal 3.2.3 (aarch64),
both the linked-SQLite and `-dWLDB_CLI` backends; the server runs, resolves tenants by Host,
and renders a board page from SQLite.

### Updates

- Reorganized the tree: design docs live in `freepascal/docs/`, the FreePascal code and
  `schema.sql` / `designer.sql` / `README.md` at `freepascal/`, and the [`wami/`](https://github.com/wekan/wami), [`omi/`](https://github.com/wekan/omi),
  [`tcl-tk-kanban/`](https://github.com/wekan/tcl-tk-kanban), [`minio-metadata/`](https://github.com/wekan/minio-metadata) prototypes alongside them.
- Updated every cross-reference path to match the new layout — `README.md` (docs → `docs/`,
  prototypes → siblings), `docs/*.md` (co-located docs lose `../`, prototypes/`schema.sql`
  keep `../`), and code comments (prototypes → siblings, design docs → `docs/`).
- Verified the whole unit set still builds on FreePascal 3.2.3 after the move.
- Documented SQLite on Amiga/retro targets (`docs/sqlite.md`): FreePascal
  bundles no SQLite (its `sqlite3` unit is only bindings); Amiga/MorphOS/AROS have none, so
  statically link the official amalgamation (no Aminet port needed), with retro build notes.

### Features

- Architecture & stack (`wlhttp.lpr`, `docs/arch.md`): `fphttpapp` + `httproute`
  (RTL-only, no C deps), tenant → auth → endpoint request lifecycle, HTML 3.2 baseline +
  HTML 4 enhancement tiers.
- Multitenancy (`wltenant.pas`, `wlregist.pas`, `docs/goals.md`): one binary serves many
  domains; `Host:` → `data/domains/<domain>/db/data.db` (unknown host → 404, no fallback);
  reserved `data/admin/` Global Admin tenant + per-domain Domain Global Admin; central TLS
  certs in `data/certs/<host>/`; per-operation scratch in `data/temp/YYYY-MM-DD_MM-SS_COUNTER/`.
- Authentication (`wlauth.pas`): no-cookie / no-JS sessions (session id in URL + hidden fields)
  with replay- and context-bound per-action tokens and idle timeout, persisted to
  `schema.sql` `login_tokens`.
- Database (`wldb.pas`, `docs/sqlite.md`): SQLite behind one interface — linked
  SQLite (default single binary) or the external `sqlite3` CLI (`-dWLDB_CLI` bootstrap).
- Schema & import (`schema.sql`, `docs/schema.md`): canonical 24-table schema;
  Kanboard SQLite (incl. BigBoard) and Meteor WeKan Mongo data imported into it.
- Designer (`wldesign.pas`, `designer.sql`, `docs/designer.md`): data-driven pages
  (page + widgets) with a no-JS/no-cookie form editor, custom URLs, seeded editable built-ins,
  LTR/RTL mirrored from one definition, and import/export (`.wlp` JSON, all pages as `.zip`).
- Table component (`wldesign.pas`): reusable no-JS data table — search, "Page n / m"
  pagination, column-visibility chooser, click-a-cell-to-edit — all stateless in the URL.
- Colors & theming (`wlcolors.pas`, `docs/theming.md`): WeKan named colors or any hex on any
  element; selectable picker components (hex / named / swatches / native wheel / web-safe grid);
  imported Trello/Kanboard palettes mapped to WeKan colors.
- Vector graphics (`wlvector.pas`): Red Strings render as SVG (modern/NetSurf), VML (old IE),
  or ASCII arrows (IBrowse/Dillo/Lynx).
- Progressive enhancement (`wlenhanc.pas`, `docs/enhance.md`): no-JS form
  baseline always works; MultiDrag (from [`wami/public/multidrag`](https://github.com/wekan/wami/tree/main/public/multidrag)) auto-activates with JS+touch
  to drag many cards at once on a big touch screen, driving the same endpoints.
- Combined move component (`wlmove.pas`, `docs/move.md`): one no-JS arrows keypad
  (▲◀▼▶) moves all selected swimlanes/lists/cards via `POST /board/move` (reorder/relocate over
  `sort` / `listId` / `swimlaneId`), modeled on the combined [`tcl-tk-kanban/kanban.go`](https://github.com/wekan/tcl-tk-kanban/blob/main/kanban.go).
- Static assets (`wlstatic.pas`, `docs/static.md`): serve `public/` at a configurable URL
  (default '/'), plus the `i18n/` translations tree at `/i18n` (`i18n/langs.jsn` +
  `i18n/data/`); embedded in the binary (`-dWLEMBED`, FPC resources via `releases/genasset.py`)
  or from disk; `releases/convlang.py` regenerates `i18n/langs.jsn`.
- REST API (`wlapi.pas`, `docs/api.md`): subset of `public/api/wekan.yml` with Bearer-token auth
  (`POST /users/login` + `Authorization: Bearer`), so WeKan's Python CLI `api.py` works unchanged
  — verified login → board/swimlanes/lists → createlist → addcard → cardsbyswimlane on FPC 3.2.3.
- REST API — card editing & counts (`wlapi.pas`): `PUT .../cards/:cardId`
  (title/description/color, and `labelIds` → `card_labels`), `GET .../lists/:listId/cards`, and
  `.../cards_count` / board `.../cards_count`. Verified via api.py `editcard` / `editcardcolor`
  / `get_list_cards_count` / `get_board_cards_count`.
- REST API — board title & copy (`wlapi.pas`): `PUT .../boards/:boardId/title`;
  `POST .../boards/:boardId/copy` structural deep copy (board + members + swimlanes + lists +
  cards, ids remapped). Verified via api.py `editboardtitle` / `copyboard`.
- REST API — board labels (`wlapi.pas`): `PUT .../boards/:boardId/labels` creates a label
  (nested `{label:{color,name}}` body) → `board_labels`; adding a label to a card already works
  via the card `PUT labelIds`. Verified via api.py `createlabel`.
- REST API — checklists (`wlapi.pas`): `GET`/`POST .../cards/:cardId/checklists`,
  `GET .../checklists/:checklistId` (with items), `POST .../checklists/:checklistId/items`.
  Verified via api.py `addchecklist` (title + items) and `checklistid`.
- REST API — card comments (`wlapi.pas`): `GET`/`POST .../cards/:cardId/comments`,
  `GET`/`DELETE .../comments/:commentId` → `card_comments`. Verified: post comment → `{_id}`,
  list returns it.
- REST API — create swimlane + delete operations (`wlapi.pas`): `POST .../swimlanes`, and
  `DELETE` board / swimlane / list / card. Children cascade via FK (board→swimlanes/lists/cards
  →card children; list/swimlane remove their cards first). Verified: delete card removed its
  comment, delete board removed its lists+cards.
- REST API — card members & assignees (`wlapi.pas`): `POST`/`DELETE .../cards/:cardId/members/:member`
  and `.../assignees/:assignee` → `card_members` / `card_assignees`; the card JSON now includes
  `members` and `assignees`. Verified: add/remove reflected in the returned card.
- REST API — custom fields (`wlapi.pas`): `GET`/`POST .../boards/:boardId/custom-fields`,
  `GET .../custom-fields/:customField`, and `POST .../cards/:cardId/customFields/:customField`
  (set card value → `card_custom_field_values`). Verified via curl: create → list → get → set
  value. (api.py's own `addcustomfieldtoboard` has a `json.loads('')` bug on empty settings.)
- REST API — card JSON now includes `customFields` (`[{_id,value}]`) alongside `labelIds`,
  `members`, `assignees`. Verified: getcard returns the set custom-field value.
- REST API — attachments (`wlapi.pas`, new `attachments` table in `schema.sql`): `POST
  /api/attachment/upload` (JSON + base64), `GET .../download/:id`, `.../info/:id`,
  `DELETE .../delete/:id`, and `GET /api/boards/:boardId/attachments`. Bytes are stored on disk
  in `data/domains/<domain>/files/attachments/<id>` (`storageBackend: filesystem`). Verified
  end-to-end via api.py: upload → info → download (base64 round-trip) → list → delete (row + file
  removed).
- REST API — list card attachments (`wlapi.pas`): `GET /api/attachment/list/:b/:s/:l/:cardId`
  returns `{success, attachments:[{attachmentId,fileName,fileType,fileSize,…}]}`. Verified via
  api.py `listcardattachments`.
- REST API — checklist items (`wlapi.pas`): `GET`/`PUT`/`DELETE
  .../checklists/:checklistId/items/:item`; PUT toggles `isFinished` and/or edits the title.
  Verified: get (false) → toggle (true) → delete.
- REST API — card archive (`wlapi.pas`): `POST .../cards/:cardId/archive` sets `archived=1`
  (+`archivedAt`); body `isArchive=false` unarchives. Verified: archive → 1, unarchive → 0.

### Security

- Password hashing (`wlpasswd.pas`): real PBKDF2-HMAC-SHA1 (RTL-only, salt from
  `/dev/urandom`) replaces the placeholder "any non-empty password". The stored hash lives in
  `users.services_json.password`; web sign-in and API `POST /users/login` both verify it, and
  accounts without a real hash can't be logged into. Seed/set with `welite hashpw <plain>`.
  Verified: correct password → token, wrong/empty → 401.
- Authorization (`wlapi.pas` `ApiAuthBoard`): board-scoped API endpoints now require the token's
  user to be an active `board_members` row (writes blocked for `isReadOnly`); public boards are
  read-only to non-members; site admins (`users.isAdmin`) bypass; `/api/users` is admin-only,
  `/api/users/:id/boards` self-or-admin. Verified: member read private → 200, outsider → 403,
  outsider write (even public) → 403, public read → 200.

### Fixes

- `wldesign.pas`: replaced an SQL-style `--` comment inside a Pascal record (compile error
  "END expected but - found") with a `//` comment.
- `wldesign.pas` zip import: `TUnZipper.UnZipAllFiles(stream)` is not available in
  FreePascal 3.2.x — spool the uploaded archive into a per-operation `data/temp/` dir and unzip
  via `UnZipper.FileName`, removing the dir afterwards.
- `docs/contract.md`: reverted a path-rewrite false positive — the prose "([wami](https://github.com/wekan/wami)/[omi](https://github.com/wekan/omi))
  reimplementation" was turned into a `../wami/omi` path and is now restored.
- `wldb.pas`: `journal_mode` is now `DELETE` under `{$IF DEFINED(AMIGA) or MORPHOS or AROS}`
  (WAL needs shared-memory/mmap that classic Amiga filesystems lack), WAL elsewhere.
- `wlhttp.lpr`: call `Randomize` at startup — without it `NewId` (api/designer) produced the
  same id sequence on every run, so restarts collided on board/list/card ids.
- `wlhttp.lpr`: dropped `cmem` — FPC's `hmac` unit (used by password hashing) corrupts the heap
  under `cmem` ("free(): invalid pointer"); the default FPC memory manager is already
  thread-safe, so `cmem` was unnecessary.
- `wldb.pas` (CLI backend): pass `-cmd "PRAGMA foreign_keys=ON"` to `sqlite3` so `ON DELETE
  CASCADE` fires (the CLI opens each connection with foreign keys off by default).

### Known TODO (carried forward)

Board/list `dataview` renderers; `wlmdrag.js`; password hashing into
`users.services_json`; Domain-Global-Admin role checks; list↕-across-swimlanes and the
Edit/Clone/Delete/Export move actions.

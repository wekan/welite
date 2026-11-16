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
exposes `InstallRootModels`, currently called only by the SQL test harness. It is
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

## Remaining before the checklist can be checked

- Map child relations through live SQL views/triggers, preserving parent arrays and
  implementing required cascades, reference checks and account uniqueness rules.
- Reconcile existing Meteor password/session formats and file-store metadata/bytes.
- Activate the adapter for fresh and existing stores without silently creating a separate
  normalized database; adapt cloning/export and private authentication-table references.
- Verify shared-database HTTP/Mongo-wire workflows, including permissions, restart and
  rollback with both Welite SQLite backends.
- Resolve shared database filename/8.3 policy and document target-specific limitations
  from actual tests. Never share a file through aliases with different WAL names.

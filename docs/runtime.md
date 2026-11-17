# Runtime files and DOS 8.3 names

`WELITE_DATA` selects the data root (default `data`). Generated components beneath
it use eight-character names and extensions of at most three characters:

```
data/admin/files/db/wekan.db
data/local/files/db/wekan.db
data/domains/d0000001/files/db/wekan.db
data/domains/d0000001/files/attachme/...
data/domains/d0000001/files/avatars/...
data/certs/d0000001/...
data/temp/t0000001/
```

This follows Weddy's per-domain `files/db`, attachment and avatar layout, adapted
to short names. The reserved Global Admin database stores full domain names,
aliases and settings. Its supplemental `tenantdirs` table assigns each domain a
persistent unique positive integer, rendered as `d` and seven hexadecimal digits.
Aliases retain the canonical domain's directory. Disabling a domain retains its
mapping and data. No truncated-domain or truncated-hash collision can select a
neighboring tenant. Admin and loopback tenants keep the reserved `admin`/`local` keys.

File IDs and original display names stay unchanged in SQL/API responses. Physical
attachment/avatar paths use the complete SHA-256 of the UTF-8 ID: seven directories
of eight hex digits followed by the final eight digits plus `.bin`. This avoids
long filenames and preserves distinctions between case-sensitive IDs on
case-insensitive filesystems. `wlstore.pas` defines the mapping; uploads, downloads,
selection export/clone/delete all use it. Empty hash directories may remain after
file deletion. The shared `wltmp.pas` allocator uses atomic create-and-retry with short counters;
existing directories from another process or an earlier run are skipped.
The RTL temporary-file hook also routes framework multipart uploads into private
short directories under this root. Router cleanup removes uploaded files and their
private directories in a try/finally, including denied requests and handler failures.
Other empty scratch directories can remain. CLI SQL input uses a private `query.sql`
inside a reserved directory, removed after each command. Unix directories/files have
0700/0600 permissions; the script and user values are absent from process arguments.

## SQLite auxiliary files

SQLite normally appends `-wal`, `-shm` or `-journal`, which violates 8.3 even when
the database filename fits. On a filesystem that enforces short names, set
`WELITE_SHORT_NAMES=1` and use SQLite compiled with
`SQLITE_ENABLE_8_3_NAMES=2`. Welite refuses a library/CLI missing that exact build
option and refuses non-8.3 database leaf names (including entropy stocks). SQLite then uses `wekan.wal`, `wekan.shm` and `wekan.nal`. Temporary SQL
storage is in memory in this mode. Native long-filename hosts can leave strict
mode off while using the same tenant/file layout.

Existing FerretDB stores can be opened explicitly with `WELITE_SHARED=1`; see
[shared activation](ferret.md#opt-in-http-activation-of-existing-stores). That mode
uses the existing canonical `wekan.sqlite` without renaming it and refuses it in
strict 8.3 mode. It does not create fresh shared stores; the admin registry remains
native. Never alias a shared database to obtain a different filename.

**Every program accessing the database must use the same naming policy**, including
backup utilities, Python, FerretDB and CLI maintenance tools. Mixing policies can
miss a live WAL or hot journal and corrupt data. Stop all clients and checkpoint
before transferring between builds. See SQLite's authoritative
[short-filename instructions](https://www.sqlite.org/shortnames.html).

For a native test build from an official SQLite amalgamation directory:

```
cc -shared -fPIC -O2 -DSQLITE_ENABLE_8_3_NAMES=2 sqlite3.c -o libsqlite3.so.0 -lm -ldl -lpthread
cc -O2 -DSQLITE_ENABLE_8_3_NAMES=2 shell.c sqlite3.c -o sqlite3 -lm -ldl -lpthread
```

Use that library via the loader's library path and that CLI first on `PATH` for
all test clients. `tests/short.py` inspects live paths and reopens data after a
process restart; `admin.py` with strict mode scans every generated component while
the server is running. Verified on native Linux with official SQLite 3.54.1;
actual DOS/Amiga filesystems remain in the cross-platform verification checklist.

## Offline migration from the previous layout

Stop Welite and all other database clients. On a modern host with Python/SQLite:

```
python3 releases/pathmove.py data datanew
```

`datanew` must not exist. The tool copies each database with SQLite's backup API,
checks integrity, assigns short tenant keys, remaps attachment/avatar bytes and
registered certificate directories, and verifies every destination component.
It publishes the new tree only when preparation succeeds. The source is retained
unchanged. Symlinks, unknown source entries, nested legacy file stores and
nonconforming certificate names require review and cause refusal rather than loss.
The migration's Python SQLite must match the source's auxiliary-file policy; the
previous ordinary builds used the default long-filename policy.

Verify the copy, then restart with `WELITE_DATA` pointing at the new tree, or switch
the directory names while the server remains stopped. Retain the original backup.
Fresh sign-in is required because authentication tokens are bound to database paths.
The current server refuses detected legacy paths instead of silently provisioning
an empty parallel database. Python is needed only for this offline migration.

## Unix process shutdown

SIGTERM and SIGINT request an orderly HTTP stop. The handlers only set a flag;
accept-loop callbacks handle it within the 100 ms idle poll or before accepting
a new connection. The server stops admission, gives active requests one second
to finish, then shuts down remaining sockets to wake blocked/incomplete reads.
Connection tracking holds a lifecycle lock while using socket handles, preventing
closed descriptor reuse. Framework threads finish before tenant database handles
are finalized. Maintenance then joins, previous signal handlers are restored, and
`WeKan-Lite stopped` is printed after worker cleanup. Repeated stop signals during
cleanup remain requests rather than interrupting the join.

`tests/stop.py` verifies linked/CLI idle, busy and incomplete HTTP connections,
repeated signals, exit status zero, immediate restart and database integrity on
Linux. Unix targets use this signal path; native Windows console control handling
and retro-platform lifecycle behavior still need platform verification.

## HTTP connection lifetime

The pinned FPC 3.2.3 source (`12e49a77d1c5b801fe8e4a2f77df27aa3dce848b`)
dispatches one request in `TFPHTTPConnection.HandleRequest` and frees its socket
when the connection thread finishes. Its response writer emits HTTP/1.1. The
common application handler therefore sets `Connection: close` when initializing
responses, following [RFC 9112 section 9.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.3).
Clients/proxies reconnect instead of pooling a socket the server is closing.
This header policy is shared across targets; Unix tracked draining remains intact,
and other targets retain the framework's default server implementation.

`tests/conn.py` checks linked/CLI HTML/static/JSON/error/redirect responses, actual
wire EOF, repeated requests through one Python client and rapid pooled Node
GET/POST requests. Both backends pass alongside shutdown/restart/integrity checks.
An isolated snapshot of committed source plus only the transport patch also passes
all eight Windows x86/amd64 backend/resource build variants. Windows and retro
runtime acceptance remain unverified; a PE build alone does not establish them.

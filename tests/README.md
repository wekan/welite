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

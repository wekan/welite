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

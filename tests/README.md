# Welite regression tests

Set `TMPDIR` to an existing writable directory under the parent checkout's `.tools/tmp`.
Set `FPC` to your FreePascal compiler and, if needed, `PPC_CONFIG_PATH` to its configuration.
No system installs or changes to production databases are needed. Each runner creates
and removes its own temporary directory.

- `python3 tests/dbtext.py`: test text fidelity, SQL failures, foreign-key enforcement
  and large query results with both SQLite backends.
- `python3 tests/movelist.py`: compile actual Pascal movement code and test canonical
  schema fixtures against linked and CLI SQLite (the latter needs `sqlite3` on PATH).
- `python3 tests/admin.py`: compile the server, run it on an ephemeral local port with
  a temporary data root, and test all Designer gates and page management over HTTP.
- `WELITE_UI=1 python3 tests/admin.py`: also drive Designer forms in Chromium with
  JavaScript disabled and Cookie request headers removed. Set `NODE` to Node.js and
  `WELITE_PLAYWRIGHT` to an installed Playwright module path if absent on module search
  paths. `PLAYWRIGHT_BROWSERS_PATH` selects an existing browser installation.

Server processes and test databases are removed on success or failure. Browser tests
use no persistent profile and assert the cookie store remains empty.

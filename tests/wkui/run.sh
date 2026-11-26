#!/usr/bin/env bash
# Run WeKan's own browser tests against WeLite's HTML5 view - locally only.
#
#   bash tests/wkui/run.sh [playwright args...]
#
# Builds WeLite (linked SQLite), starts FerretDB on a fresh data directory -
# the local tenant's files/db, where WeLite in shared mode reads the same
# SQLite store - and runs Playwright with tests/wkui/pwconf.js. WeKan's
# helpers/db.js seeds users and boards through FerretDB, and Weddy's
# helpers/auth.js signs in with the meteor_login_token cookie.
#
# Tools (WeKan's .tools, two levels above this checkout): node-*/bin,
# ms-playwright, ferretdb-test/ferretdb (FERRETDB), Weddy's prepared
# tests/wekan (WEDDY_WEKAN_TESTS) and FPC (default: the fpcupdeluxe compiler
# through the same fpc.cfg rebase build.sh does).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOLS="${TOOLS:-$(cd "$ROOT/../.." && pwd)}"
export TMPDIR="${TMPDIR:-$TOOLS/tmp}"; mkdir -p "$TMPDIR"
for n in "$TOOLS"/node-v*/bin; do [ -x "$n/node" ] && PATH="$n:$PATH"; done
export PATH
command -v node >/dev/null || { echo "run.sh: Node.js is needed to run the tests" >&2; exit 1; }
export WEDDY_WEKAN_TESTS="${WEDDY_WEKAN_TESTS:-$TOOLS/w/weddy/tests/wekan}"
[ -d "$WEDDY_WEKAN_TESTS/node_modules/@playwright/test" ] || {
  echo "run.sh: $WEDDY_WEKAN_TESTS has no node_modules: run Weddy's tests/wekan/run.sh once" >&2; exit 1; }
FERRETDB="${FERRETDB:-$TOOLS/ferretdb-test/ferretdb}"
[ -x "$FERRETDB" ] || { echo "run.sh: no FerretDB at $FERRETDB (FERRETDB)" >&2; exit 1; }
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$TOOLS/ms-playwright}"

WORK="$(mktemp -d "$TMPDIR/welite-wkui.XXXXXX")"
LOG_DIR="${LOG_DIR:-$TOOLS/log/welite-wkui/$(date +%Y-%m-%d_%H-%M-%S)}"; mkdir -p "$LOG_DIR"

# Build.
if [ -z "${FPC:-}" ]; then
  FPC="$WORK/fpc"; cfg="$TOOLS/bin/fpcupdeluxe/fpc/bin/$(uname -m)-linux/fpc.cfg"
  orig="$(sed -n 's#^-FM\(.*\)/fpc/share/unicode/$#\1#p' "$cfg" | head -n 1)"
  sed "s#$orig#$TOOLS/bin/fpcupdeluxe#g" "$cfg" > "$WORK/fpc.cfg"
  printf '#!/bin/sh\nexec "%s" -n "@%s" "$@"\n' "${cfg%/fpc.cfg}/fpc" "$WORK/fpc.cfg" > "$FPC"; chmod +x "$FPC"
fi
mkdir -p "$WORK/build"
"$FPC" -B -FU"$WORK/build" -FE"$WORK/build" "$ROOT/src/wlhttp.lpr" > "$LOG_DIR/welite-build.log" 2>&1 || {
  tail -n 20 "$LOG_DIR/welite-build.log" >&2; exit 1; }

free_port() { node -e 'const s=require("net").createServer().listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'; }
PORT="$(free_port)"; DBPORT="$(free_port)"; DEBUGPORT="$(free_port)"
DB="$WORK/data/local/files/db"; mkdir -p "$DB" "$WORK/state"
"$FERRETDB" --handler=sqlite --sqlite-url="file://$DB/" --state-dir="$WORK/state" \
  --listen-addr="127.0.0.1:$DBPORT" --debug-addr="127.0.0.1:$DEBUGPORT" --log-level=ERROR --telemetry=disable \
  > "$LOG_DIR/ferretdb.log" 2>&1 &
FPID=$!
# FerretDB first, and its collections (the same as tests/shrhttp.py creates):
# FerretDB makes the store, and WeLite installs its projections on it.
node -e '
const { MongoClient } = require(process.argv[1]);
(async () => {
  const c = new MongoClient(process.argv[2], { serverSelectionTimeoutMS: 20000 });
  for (let i = 0; ; i++) { try { await c.connect(); break; } catch (e) { if (i > 100) throw e; await new Promise(r => setTimeout(r, 100)); } }
  const db = c.db("wekan");
  for (const name of ["boards","swimlanes","lists","cards","card_comments","checklists","checklistItems","customFields","users","activities","attachments",
                      "rules","triggers","actions","integrations","eventlog","savedCardFilters","scrumSnapshotRows","org","team","settings"])
    await db.createCollection(name).catch(e => { if (!/already exists/i.test(e.message)) throw e; });
  // WeKan collectionBootstrap.js, as WeKan (and Weddy) run it when they make
  // the store WeLite shares: the Admin Panel account switches, off.
  for (const [i, id] of ["accounts-allowEmailChange", "accounts-allowUserNameChange", "accounts-allowUserDelete"].entries())
    await db.collection("accountSettings").updateOne({ _id: id }, { $setOnInsert: { booleanValue: false, sort: i === 1 ? 1 : 0 } }, { upsert: true });
  await c.close();
})().catch(e => { console.error(e.message); process.exit(1); });
' "$WEDDY_WEKAN_TESTS/node_modules/mongodb" "mongodb://127.0.0.1:$DBPORT/wekan" >> "$LOG_DIR/ferretdb.log" 2>&1 || {
  echo "run.sh: FerretDB did not create the collections:" >&2; tail -n 20 "$LOG_DIR/ferretdb.log" >&2; kill "$FPID"; exit 1; }
export WELITE_DATA="$WORK/data" WELITE_SHARED=1 WELITE_PORT="$PORT" \
  WELITE_SCHEMA="$ROOT/src/schema.sql" WELITE_DESIGNER="$ROOT/src/designer.sql" \
  WELITE_PUBLIC="$ROOT/public" WELITE_I18N="$ROOT/i18n"
( cd "$WORK" && exec "$WORK/build/wlhttp" ) > "$LOG_DIR/welite-server.log" 2>&1 &
WPID=$!
cleanup() { kill "$WPID" "$FPID" 2>/dev/null || true; wait "$WPID" "$FPID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
for _ in $(seq 1 100); do
  curl -fsS -o /dev/null "http://127.0.0.1:$PORT/sign-in" 2>/dev/null && break
  kill -0 "$WPID" 2>/dev/null || { echo "run.sh: WeLite exited:" >&2; tail -n 20 "$LOG_DIR/welite-server.log" >&2; exit 1; }
  sleep 0.2
done

export WEKAN_BASE_URL="http://127.0.0.1:$PORT" WEKAN_MONGO_URL="mongodb://127.0.0.1:$DBPORT/wekan"
export WELITE_TEST_RESULTS="$LOG_DIR/test-results"
cd "$WEDDY_WEKAN_TESTS"
set +e
npx playwright test -c "$ROOT/tests/wkui/pwconf.js" --project=chromium "$@" 2>&1 | tee "$LOG_DIR/welite-wkui-playwright.log"
status=${PIPESTATUS[0]}
echo "===== WeKan tests against WeLite's HTML5 view finished: exit $status (logs in $LOG_DIR) ====="
exit "$status"

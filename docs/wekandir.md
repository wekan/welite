# Reading WeKan data folders

WeLite can show the data of a Node.js WeKan, a Weddy or a WeKan Docker or Snap
install as HTML4 kanban pages, straight from its folders: the FerretDB SQLite
database and the attachment files. Nothing in those folders is written. The
code is `src/wlwkdir.pas` (reading) and `src/wlwkweb.pas` (pages).

## Configure

Set `WELITE_WEKAN_ROOTS` to one or more folders, separated by `;` or newlines:

```sh
WELITE_WEKAN_ROOTS="/data;/srv/weddy;/var/snap/wekan/common/files" ./build/bin/wcurrent.exe
```

Sign in as the Global Admin on the reserved `admin` host. Its navigation then
has a **WeKan: Domains** button that opens `/wekan`.

## What WeLite finds in a root

A root is a WeKan `WRITABLE_PATH`, a folder of many domains, or both. These are
the layouts of WeKan's own code and scripts:

| Layout | Where it comes from | Files folder |
| --- | --- | --- |
| `<root>/files/db/wekan.sqlite`, `<root>/files/attachments/` | Docker, bundle and dev: `WRITABLE_PATH=/data`, WeKan appends `files` (`server/initializeDirs.js`, `models/lib/attachmentStoragePath.js`); FerretDB gets `--sqlite-url=file:$WRITABLE_PATH/files/db/` (`releases/ferretdb/wekan-entrypoint.sh`, `docker-compose.yml`) | `<root>/files` |
| `<root>/db/wekan.sqlite`, `<root>/attachments/` when the root is named `files` or `wekan-files` | Snap (`WRITABLE_PATH=$SNAP_COMMON/files`, `snap-src/bin/wekan-control`) and single-file WeKan (`models/lib/filesRoot.js`) | `<root>` |
| `<root>/domains/<domain>/files/...` | Weddy and caddy-wekan-plugin with many domains (`cloud.go`): one WeKan per customer domain | `<root>/domains/<domain>/files` |
| `<root>/cloud/domains.json` | the Cloud Panel's domain list with start and end dates (`cloud.go`) | shown beside each listed domain |

The Docker multi-tenant compose file (`docker-compose-multitenancy.yml`) gives
each tenant its own `/data` volume; configure each volume as its own root.
WeKan's Cloud Panel domains that have "their own WeKan and database" are
separate containers with their own volumes in the same way.

A domain folder must have a lowercase host name (letters, digits, dots and
hyphens) and must not be a symbolic link; anything else under `domains/` is
not listed.

## The database

FerretDB v1's SQLite backend (`internal/backends/sqlite/metadata` in
wekan/FerretDB) keeps:

- one file per database in the `files/db` folder: `<name>.sqlite`, or
  `<name>.db` with `dbext=db`. WeKan's database is `wekan` (from `MONGO_URL`);
  `local.sqlite` is the oplog's and is not listed;
- the collection registry `_ferretdb_collections(name, table_name, settings)`;
  a collection's table is `<lowercased name>_<FNV-32a hex>`, so WeLite always
  looks the table up rather than computing it;
- one row per document in the `_ferretdb_sjson` column: typed SJSON as TEXT in
  older tables, SQLite JSONB as a STRICT BLOB in newer ones. WeLite reads both
  with `json(_ferretdb_sjson)` and decodes the SJSON with the same `wlsjson`
  codec its FerretDB adapter is tested with. Dates are epoch milliseconds and
  are shown in UTC.

The collections read are WeKan's: `boards`, `swimlanes`, `lists`, `cards`,
`checklists`, `checklistItems`, `card_comments`, `customFields`, `users` and
`attachments`. WeKan has no second SQLite mode of its own: MongoDB data is
read through FerretDB-written SQLite only.

### Read-only, and never a file created

The file must start with the SQLite header and have a `_ferretdb_collections`
table, or the domain shows "No readable WeKan database was found."

- While FerretDB runs, its WAL files `<db>-wal` and `<db>-shm` exist. WeLite
  opens `file:...?mode=ro`, a read-only SQLite reader sharing them like any
  other reader: it takes read locks in the existing `-shm` and writes no data.
- When there is no WAL, nobody is writing, and WeLite opens
  `file:...?immutable=1`, which reads the file without locks and without
  creating any file beside it.
- A hot rollback journal (`<db>-journal`) and 8.3 short-name WAL files
  (`wekan.wal`, FerretDB's `shortnames=1`) are refused: reading past them needs
  the writer's recovery or a matching SQLite build.
- The linked build also sets `PRAGMA query_only` and refuses any statement
  `sqlite3_stmt_readonly` does not call read-only. The CLI build runs
  `sqlite3 -readonly -json` with `-init` pointed at an empty file, and needs
  SQLite 3.45 or newer for JSONB tables.

## Attachments

Attachments are Meteor-Files documents in `attachments`. A document whose
`versions.original.storage` is not `fs` (GridFS, S3 and other object storage)
has no file in the folder and is shown with its storage name. For the others,
WeLite looks for the bytes the way WeKan's `fileStoreStrategy.js`
`candidatePaths()` does, but only as **one file name inside
`<files>/attachments`**:

1. the base name of `versions.original.path` (the origin server's absolute
   path, usually `/data/files/attachments/<id>.<ext>`), and of `path`;
2. `<id>.<ext>` and `<id>` (current naming: the file is named by its id);
3. `<id>-original-<name>` and any `<id>-original-*` (older naming).

A name containing `/`, `\`, `:` or a control character, `.` or `..`, a
symbolic link and anything that is not a regular file are refused, and the
expanded path must stay inside the attachments folder. An attachment is served
only for a card of the board in the URL, and its id in the URL only selects a
database document; the file name always comes from the steps above. Soft-deleted
attachments (`deletedAt` set) are not shown.

## Pages

All pages are HTML 4.01 tables with no JavaScript and no cookies; links carry
the session and language the way the rest of WeLite does.

| Page | Shows |
| --- | --- |
| `/wekan` | each root, its domains, the database, and per domain the boards, cards, attachments, their recorded bytes and the database bytes (file plus WAL), with the Cloud Panel's start and end dates |
| `/wekan/boards` | the boards of a domain with type, archived mark, members, cards, attachments and bytes; other databases of the domain as links |
| `/wekan/board` | the board as a kanban: swimlanes by lists, each card with its labels in their colors, title, members, assignees, received/start/due/end dates and checklist, comment and attachment counts. Archived swimlanes, lists and cards are left out; a list that belongs to one swimlane has cards only in that row |
| `/wekan/card` | swimlane, list, labels, members, assignees, dates, the description as escaped text with its line breaks, custom fields (text, dropdown names, dates, checkboxes), checklists, comments and attachments with download links |
| `/wekan/file` | `view=1`: an attachment's type, sizes and a preview (raster images inline, text as escaped `<pre>` up to 64 KiB); otherwise the download, as `Content-Disposition: attachment` except a raster `preview=1` |

Every value from the database is HTML-escaped; a card title of
`<script>alert(1)</script>` shows as that text.

## Access

The data is another server's, with its own users and board members, and
WeLite's accounts are not WeKan's. So WeLite's board roles cannot decide who
may see a WeKan board, and every `/wekan` page requires the **Global Admin of
the reserved admin tenant**. Without a session the pages redirect to sign-in;
a Domain Global Admin or any other account gets 403.

## Sizes

Per domain and per board: cards (all, archived included), attachments that are
not soft-deleted and the sum of their recorded `versions.original.size` (or
`size`). Per domain also the database file and its WAL in bytes.

## Tests

`python3 tests/wkdir.py` (see [tests/README.md](../tests/README.md#wekan-data-folders))
writes the fixture with a real FerretDB v1 and checks the reader and the pages
on linked and CLI SQLite, while FerretDB runs and after it stopped, including
path traversal, symbolic links, malformed and missing databases, HTML escaping
and that no file in the data folders changes.

## Not done

- Zip archives (WeKan exports, Sandstorm grain backups with
  `data/files/db/wekan.sqlite`) are not opened.
- GridFS and object-storage attachments are listed but not downloaded.
- Avatars are not shown.
- FerretDB 8.3 short-name sidecars need an SQLite built with
  `SQLITE_ENABLE_8_3_NAMES=2` and are refused for now.
- Only native Linux aarch64 builds were run; other targets and retro browsers
  are unverified for these pages.

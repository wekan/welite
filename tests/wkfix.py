"""WeKan data-folder fixture for the read-only WeKan viewer (tests/wkdir.py).

The databases are written by FerretDB itself, through the MongoDB wire protocol,
into the same `files/db/wekan.sqlite` layout WeKan's start scripts give FerretDB
(`--sqlite-url=file:$WRITABLE_PATH/files/db/`). Documents follow WeKan's models:
boards, swimlanes, lists, cards, checklists, checklistItems, card_comments,
customFields, users and Meteor-Files `attachments` (fields of ostrio:files
_dataToSchema plus WeKan's `versions.original.storage`).

`python3 tests/wkfix.py --dump` refreshes tests/wkdir/*.sql with `sqlite3 .dump`
of FerretDB's output, so tests can rebuild the databases when no FerretDB binary
is available. With FERRETDB (default: the parent .tools/ferretdb-test/ferretdb)
present, tests write the databases with FerretDB on every run instead.
"""
import os
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from wire import Client, DateMs

ROOT = Path(__file__).resolve().parents[1]
DUMPS = ROOT / 'tests' / 'wkdir'
TOOLS = ROOT.parents[1]
T0 = 1794832496789  # 2026-11-16T12:34:56.789Z
DAY = 86400000
PNG = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
                    '1f15c4890000000d49444154789c6360f8cfc0f01f0005000201e2'
                    '21bc330000000049454e44ae426082')
TEXT = b'Garden notes\nline two & <tags>\n'


def ferretdb():
    path = Path(os.environ.get('FERRETDB', str(TOOLS / 'ferretdb-test' / 'ferretdb')))
    return path if path.is_file() and os.access(path, os.X_OK) else None


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def attachment(fid, name, ext, kind, size, board, card, recorded, storage='fs', **extra):
    """The Meteor-Files document shape (ostrio:files _dataToSchema) WeKan stores."""
    doc = {
        '_id': fid, 'name': name, 'extension': ext, 'ext': ext, 'extensionWithDot': '.' + ext,
        'path': recorded, 'meta': {'boardId': board, 'cardId': card, 'listId': 'L1', 'swimlaneId': 's1'},
        'type': kind, 'mime': kind, 'mime-type': kind, 'size': size, 'userId': 'u1',
        'versions': {'original': {'path': recorded, 'size': size, 'type': kind, 'extension': ext, 'storage': storage}},
        '_downloadRoute': '/cdn/storage', '_collectionName': 'attachments',
        'isVideo': False, 'isAudio': False, 'isImage': kind.startswith('image/'), 'isText': kind.startswith('text/'),
        'isJSON': False, 'isPDF': False, '_storagePath': '/data/files/attachments', 'public': False,
        'uploadedAt': DateMs(T0),
    }
    doc.update(extra)
    return doc


def one_documents():
    """Domain one.example: a board with every element the viewer shows."""
    return {
        'users': [
            {'_id': 'u1', 'username': 'alice', 'profile': {'fullname': 'Alice Example'}, 'isAdmin': True, 'createdAt': DateMs(T0)},
            {'_id': 'u2', 'username': 'bob', 'profile': {'fullname': 'Bob <Builder>'}, 'createdAt': DateMs(T0)},
        ],
        'boards': [
            {'_id': 'b1', 'title': 'Garden <b>&</b> board', 'slug': 'garden', 'archived': False, 'type': 'board',
             'permission': 'private', 'color': 'belize', 'sort': 0, 'createdAt': DateMs(T0),
             'members': [{'userId': 'u1', 'isAdmin': True, 'isActive': True, 'isNoComments': False, 'isCommentOnly': False, 'isWorker': False},
                         {'userId': 'u2', 'isAdmin': False, 'isActive': True, 'isNoComments': False, 'isCommentOnly': False, 'isWorker': False}],
             'labels': [{'_id': 'l1', 'name': 'Urgent', 'color': 'red'}, {'_id': 'l2', 'name': '', 'color': 'green'}]},
            {'_id': 'b2', 'title': 'Old archive', 'slug': 'old', 'archived': True, 'type': 'board', 'permission': 'private',
             'sort': 1, 'createdAt': DateMs(T0), 'members': [{'userId': 'u1', 'isAdmin': True, 'isActive': True}], 'labels': []},
            {'_id': 'b3', 'title': 'Templates', 'slug': 'templates', 'archived': False, 'type': 'template-container',
             'permission': 'private', 'sort': 2, 'createdAt': DateMs(T0), 'members': [{'userId': 'u1', 'isAdmin': True, 'isActive': True}], 'labels': []},
        ],
        'swimlanes': [
            {'_id': 's1', 'boardId': 'b1', 'title': 'Default', 'sort': 0, 'archived': False, 'type': 'swimlane', 'createdAt': DateMs(T0)},
            {'_id': 's2', 'boardId': 'b1', 'title': 'Second lane', 'sort': 1, 'archived': False, 'type': 'swimlane', 'createdAt': DateMs(T0)},
            {'_id': 's3', 'boardId': 'b1', 'title': 'Archived lane', 'sort': 2, 'archived': True, 'type': 'swimlane', 'createdAt': DateMs(T0)},
            {'_id': 's9', 'boardId': 'b2', 'title': 'Default', 'sort': 0, 'archived': False, 'type': 'swimlane', 'createdAt': DateMs(T0)},
        ],
        'lists': [
            {'_id': 'L1', 'boardId': 'b1', 'swimlaneId': '', 'title': 'To do', 'sort': 0, 'archived': False, 'type': 'list', 'createdAt': DateMs(T0)},
            {'_id': 'L2', 'boardId': 'b1', 'swimlaneId': '', 'title': 'Doing', 'sort': 1, 'archived': False, 'type': 'list', 'createdAt': DateMs(T0)},
            {'_id': 'L3', 'boardId': 'b1', 'swimlaneId': 's2', 'title': 'Lane two only', 'sort': 2, 'archived': False, 'type': 'list', 'createdAt': DateMs(T0)},
            {'_id': 'L4', 'boardId': 'b1', 'swimlaneId': '', 'title': 'Archived list', 'sort': 3, 'archived': True, 'type': 'list', 'createdAt': DateMs(T0)},
            {'_id': 'L9', 'boardId': 'b2', 'swimlaneId': '', 'title': 'Old list', 'sort': 0, 'archived': False, 'type': 'list', 'createdAt': DateMs(T0)},
        ],
        'cards': [
            {'_id': 'c1', 'boardId': 'b1', 'swimlaneId': 's1', 'listId': 'L1', 'title': '<script>alert(1)</script>',
             'description': 'Line one\n<b>bold</b> & more', 'sort': 0, 'archived': False, 'type': 'cardType-card',
             'userId': 'u1', 'labelIds': ['l1', 'l2'], 'members': ['u1'], 'assignees': ['u2'],
             'receivedAt': DateMs(T0 - 2 * DAY), 'startAt': DateMs(T0 - DAY), 'dueAt': DateMs(T0 + 3 * DAY), 'endAt': DateMs(T0 + 4 * DAY),
             'customFields': [{'_id': 'cf1', 'value': 'Text <value>'}, {'_id': 'cf2', 'value': 'dd2'}, {'_id': 'cf3', 'value': DateMs(T0 + 7 * DAY)},
                              {'_id': 'cf4', 'value': True}],
             'createdAt': DateMs(T0)},
            {'_id': 'c2', 'boardId': 'b1', 'swimlaneId': 's1', 'listId': 'L2', 'title': 'Water plants', 'description': '',
             'sort': 1, 'archived': False, 'type': 'cardType-card', 'userId': 'u2', 'labelIds': [], 'members': [], 'assignees': [],
             'createdAt': DateMs(T0)},
            {'_id': 'c3', 'boardId': 'b1', 'swimlaneId': 's2', 'listId': 'L3', 'title': 'Second lane card', 'sort': 0,
             'archived': False, 'type': 'cardType-card', 'userId': 'u1', 'createdAt': DateMs(T0)},
            {'_id': 'c4', 'boardId': 'b1', 'swimlaneId': 's1', 'listId': 'L1', 'title': 'Archived card', 'sort': 2,
             'archived': True, 'type': 'cardType-card', 'userId': 'u1', 'createdAt': DateMs(T0)},
            {'_id': 'c5', 'boardId': 'b2', 'swimlaneId': 's9', 'listId': 'L9', 'title': 'Old card', 'sort': 0,
             'archived': False, 'type': 'cardType-card', 'userId': 'u1', 'createdAt': DateMs(T0)},
        ],
        'customFields': [
            {'_id': 'cf1', 'boardIds': ['b1'], 'name': 'Notes', 'type': 'text', 'settings': {}, 'showOnCard': True, 'createdAt': DateMs(T0)},
            {'_id': 'cf2', 'boardIds': ['b1'], 'name': 'Priority', 'type': 'dropdown',
             'settings': {'dropdownItems': [{'_id': 'dd1', 'name': 'Low'}, {'_id': 'dd2', 'name': 'High'}]}, 'showOnCard': True, 'createdAt': DateMs(T0)},
            {'_id': 'cf3', 'boardIds': ['b1'], 'name': 'Deadline', 'type': 'date', 'settings': {}, 'createdAt': DateMs(T0)},
            {'_id': 'cf4', 'boardIds': ['b1'], 'name': 'Approved', 'type': 'checkbox', 'settings': {}, 'createdAt': DateMs(T0)},
        ],
        'checklists': [
            {'_id': 'k1', 'cardId': 'c1', 'boardId': 'b1', 'title': 'Steps', 'sort': 0, 'createdAt': DateMs(T0)},
        ],
        'checklistItems': [
            {'_id': 'i1', 'checklistId': 'k1', 'cardId': 'c1', 'boardId': 'b1', 'title': 'Dig', 'sort': 0, 'isFinished': True, 'createdAt': DateMs(T0)},
            {'_id': 'i2', 'checklistId': 'k1', 'cardId': 'c1', 'boardId': 'b1', 'title': 'Plant <seeds>', 'sort': 1, 'isFinished': False, 'createdAt': DateMs(T0)},
        ],
        'card_comments': [
            {'_id': 'm1', 'cardId': 'c1', 'boardId': 'b1', 'userId': 'u2', 'text': 'Looks <i>good</i>', 'createdAt': DateMs(T0 + 3600000)},
        ],
        'attachments': [
            # Current naming: <storagePath>/<fileId><extensionWithDot>, recorded at the server's own path.
            attachment('a1', 'notes.txt', 'txt', 'text/plain', len(TEXT), 'b1', 'c1', '/data/files/attachments/a1.txt'),
            # Old naming <id>-original-<name>, recorded somewhere that no longer exists.
            attachment('a2', 'photo.png', 'png', 'image/png', len(PNG), 'b1', 'c1', '/old/server/attachments/a2-original-photo.png'),
            # Traversal attempts through the recorded path and the id.
            attachment('a3', 'passwd', 'txt', 'text/plain', 7, 'b1', 'c1', '../../secret.txt'),
            attachment('../../secret', 'secret.txt', 'txt', 'text/plain', 7, 'b1', 'c1', '/data/files/attachments/../../secret.txt'),
            # On disk as a symbolic link that points out of the files folder.
            attachment('a5', 'link.txt', 'txt', 'text/plain', 7, 'b1', 'c2', '/data/files/attachments/a5.txt'),
            # In GridFS, not on the filesystem.
            attachment('a6', 'grid.txt', 'txt', 'text/plain', 11, 'b1', 'c2', '/data/files/attachments/a6.txt', storage='gridfs'),
            # Soft-deleted: not shown and not counted.
            attachment('a7', 'gone.txt', 'txt', 'text/plain', 5, 'b1', 'c1', '/data/files/attachments/a7.txt', deletedAt=DateMs(T0)),
            attachment('a9', 'old.txt', 'txt', 'text/plain', 3, 'b2', 'c5', '/data/files/attachments/a9.txt'),
        ],
    }


def two_documents():
    return {
        'users': [{'_id': 'v1', 'username': 'carol', 'profile': {'fullname': 'Carol'}, 'createdAt': DateMs(T0)}],
        'boards': [{'_id': 'tb', 'title': 'Second domain board', 'slug': 'second', 'archived': False, 'type': 'board',
                    'permission': 'public', 'sort': 0, 'createdAt': DateMs(T0),
                    'members': [{'userId': 'v1', 'isAdmin': True, 'isActive': True}], 'labels': []}],
        'swimlanes': [{'_id': 'ts', 'boardId': 'tb', 'title': 'Default', 'sort': 0, 'archived': False, 'createdAt': DateMs(T0)}],
        'lists': [{'_id': 'tl', 'boardId': 'tb', 'swimlaneId': '', 'title': 'Backlog', 'sort': 0, 'archived': False, 'createdAt': DateMs(T0)}],
        'cards': [{'_id': 'tc', 'boardId': 'tb', 'swimlaneId': 'ts', 'listId': 'tl', 'title': 'Only card in two', 'sort': 0,
                   'archived': False, 'userId': 'v1', 'createdAt': DateMs(T0)}],
        'attachments': [],
    }


DATASETS = {'one': one_documents, 'two': two_documents}


def write_with_ferretdb(ferret, dbdir, documents, keep_running=False):
    """Insert the documents through a FerretDB server whose SQLite directory is dbdir."""
    dbdir.mkdir(parents=True, exist_ok=True)
    # FerretDB's state and log stay outside the WeKan folder the tests snapshot.
    state = Path(tempfile.mkdtemp(prefix='wkferret-', dir=os.environ['TMPDIR']))
    listen = port()
    log = (state / 'ferret.log').open('w+')
    server = subprocess.Popen([str(ferret), '--handler=sqlite', '--sqlite-url=' + dbdir.as_uri() + '/',
                               '--state-dir=' + str(state), '--listen-addr=127.0.0.1:' + str(listen),
                               '--debug-addr=127.0.0.1:' + str(port()), '--log-level=error', '--telemetry=disable'],
                              stdout=log, stderr=log)
    client = Client(listen)
    try:
        for _ in range(200):
            try:
                client.command({'ping': 1})
                break
            except (OSError, EOFError):
                if server.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(.05)
        else:
            raise AssertionError('FerretDB did not start')
        for name, docs in documents.items():
            client.command({'create': name})
            if docs:
                client.command({'insert': name, 'documents': docs})
    except BaseException:
        server.terminate()
        server.wait(10)
        raise
    if keep_running:
        return server, log, state
    stop(server, log, state)
    return None


def stop(server, log, state):
    server.terminate()
    server.wait(20)
    log.close()
    shutil.rmtree(state, ignore_errors=True)


def write_from_dump(name, dbdir):
    dbdir.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(dbdir / 'wekan.sqlite') as con:
        con.executescript((DUMPS / (name + '.sql')).read_text())
    con.close()


def write_files(files, name):
    """Attachment bytes, in the layouts WeKan's fileStoreStrategy candidatePaths() finds."""
    attach = files / 'attachments'
    attach.mkdir(parents=True, exist_ok=True)
    (files / 'avatars').mkdir(exist_ok=True)
    if name != 'one':
        return
    (attach / 'a1.txt').write_bytes(TEXT)
    (attach / 'a2-original-photo.png').write_bytes(PNG)
    (attach / 'a9.txt').write_bytes(b'old')
    outside = files.parent / 'secret.txt'
    outside.write_bytes(b'SECRET!')
    os.symlink(outside, attach / 'a5.txt')


def make(base, name, ferret=None, keep_running=False):
    """Create <base>/files/db/wekan.sqlite and <base>/files/attachments for a dataset."""
    files = base / 'files'
    dbdir = files / 'db'
    running = None
    if ferret:
        running = write_with_ferretdb(ferret, dbdir, DATASETS[name](), keep_running)
    else:
        write_from_dump(name, dbdir)
    write_files(files, name)
    return running


def dump():
    ferret = ferretdb()
    assert ferret, 'Set FERRETDB to a FerretDB v1 binary to refresh the dumps'
    tmp = Path(os.environ['TMPDIR']) / ('wkfix-%d' % os.getpid())
    try:
        DUMPS.mkdir(exist_ok=True)
        for name in DATASETS:
            base = tmp / name
            make(base, name, ferret)
            db = base / 'files' / 'db' / 'wekan.sqlite'
            text = subprocess.run(['sqlite3', str(db), '.dump'], check=True, capture_output=True, text=True).stdout
            (DUMPS / (name + '.sql')).write_text(text)
            print('wrote', DUMPS / (name + '.sql'))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    if sys.argv[1:] == ['--dump']:
        dump()
    else:
        print(__doc__)

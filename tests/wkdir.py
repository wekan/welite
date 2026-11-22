"""Read-only WeKan data folders: reader harness and HTML4 pages, linked and CLI SQLite.

The databases are written by a real FerretDB v1 (FERRETDB, default the parent
.tools/ferretdb-test/ferretdb) into WeKan's files/db layout; without one, the
FerretDB-written dumps in tests/wkdir/ are loaded instead. One domain's FerretDB
keeps running during the first half, so the reader is checked against a live WAL
database as well as a stopped one. Nothing in the data folders may change.
"""
import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit, parse_qs

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wkfix  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FPC = os.environ.get('FPC', 'fpc')


def compile_program(source, out, flags):
    out.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([FPC, *flags, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(source)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, result.stdout


def snapshot(*folders):
    """Every file under the WeKan folders: name -> (size, sha256). SHM is SQLite's lock memory."""
    state = {}
    for folder in folders:
        for path in sorted(folder.rglob('*')):
            if path.name.startswith('.ferret'):
                continue
            if path.is_symlink():
                state[str(path)] = ('link', os.readlink(path))
            elif path.is_file():
                digest = 'shm' if path.name.endswith('-shm') else hashlib.sha256(path.read_bytes()).hexdigest()
                state[str(path)] = (path.stat().st_size if digest != 'shm' else 0, digest)
            else:
                state[str(path)] = ('dir',)
    return state


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def make_tree(tmp, ferret):
    """Weddy-style root with domains, a Docker-style root and a Snap-style files root."""
    weddy, single, snap = tmp / 'weddy', tmp / 'single', tmp / 'snap' / 'files'
    running = wkfix.make(weddy / 'domains' / 'one.example', 'one', ferret, keep_running=bool(ferret))
    wkfix.make(weddy / 'domains' / 'two.example', 'two', ferret)
    wkfix.make(single, 'two', ferret)
    # Snap: WRITABLE_PATH=$SNAP_COMMON/files is the files folder itself (models/lib/filesRoot.js).
    snap.mkdir(parents=True)
    wkfix.write_from_dump('two', snap / 'db')
    (snap / 'attachments').mkdir()
    # Malformed and missing databases.
    broken = weddy / 'domains' / 'broken.example' / 'files' / 'db'
    broken.mkdir(parents=True)
    (broken / 'wekan.sqlite').write_bytes(b'not a database at all' * 100)
    corrupt = weddy / 'domains' / 'corrupt.example' / 'files' / 'db'
    corrupt.mkdir(parents=True)
    (corrupt / 'wekan.sqlite').write_bytes(b'SQLite format 3\0' + b'\xff' * 8192)
    plain = weddy / 'domains' / 'plain.example' / 'files' / 'db'
    plain.mkdir(parents=True)
    import sqlite3
    con = sqlite3.connect(plain / 'wekan.sqlite')
    con.execute('CREATE TABLE boards(id TEXT)')
    con.commit()
    con.close()
    (weddy / 'domains' / 'nodb.example' / 'files' / 'attachments').mkdir(parents=True)
    # Not domains: an invalid name and a symbolic link to another domain.
    (weddy / 'domains' / 'Bad_Name' / 'files' / 'db').mkdir(parents=True)
    os.symlink(weddy / 'domains' / 'two.example', weddy / 'domains' / 'link.example')
    (weddy / 'cloud').mkdir()
    (weddy / 'cloud' / 'domains.json').write_text(json.dumps({'cloudPanelDomain': 'cloud.example', 'domains': [
        {'domain': 'one.example', 'startDate': '2026-01-01', 'endDate': '2026-12-31'},
        {'domain': 'absent.example', 'startDate': '2026-02-02'}]}))
    return [weddy, single, tmp / 'snap' / 'files'], running


def harness_checks(binary, env, live):
    def run(*args, code=0):
        result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True)
        assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
        return result.stdout.splitlines()
    sites = [line.split('|') for line in run('sites')]
    names = [(s[0], s[1]) for s in sites]
    assert names == [('0', 'broken.example'), ('0', 'corrupt.example'), ('0', 'nodb.example'), ('0', 'one.example'),
                     ('0', 'plain.example'), ('0', 'two.example'), ('1', ''), ('2', '')], names
    one = [s for s in sites if s[1] == 'one.example'][0]
    assert one[4:] == ['1', '2026-01-01', '2026-12-31'], one
    assert sites[-1][3].endswith('/snap/files') and sites[-2][3].endswith('/single/files'), sites
    assert run('dbs', '0', 'one.example') == ['wekan', 'default=wekan']
    cards = run('open', '0', 'one.example', 'wekan', 'cards')
    assert cards[0].endswith('?mode=ro' if live else '?immutable=1'), cards[0]
    assert cards[1:] == ['c1|<script>alert(1)</script>|2026-11-16 12:34 UTC', 'c2|Water plants|2026-11-16 12:34 UTC',
                         'c3|Second lane card|2026-11-16 12:34 UTC', 'c4|Archived card|2026-11-16 12:34 UTC',
                         'c5|Old card|2026-11-16 12:34 UTC', 'skipped=0'], cards
    assert run('open', '2', '', 'wekan', 'boards')[1:] == ['tb|Second domain board|2026-11-16 12:34 UTC', 'skipped=0']
    files = {}
    for fid in ['a1', 'a2', 'a3', '../../secret', 'a5', 'a6']:
        files[fid] = run('file', '0', 'one.example', 'wekan', fid)[0]
    assert files['a1'].startswith('file|') and files['a1'].endswith('/one.example/files/attachments/a1.txt'), files
    assert files['a2'].endswith('/attachments/a2-original-photo.png'), files
    # NEGATIVE: traversal in the recorded path or the id, and a symlink out of the folder.
    assert files['a3'] == files['../../secret'] == files['a5'] == 'none|missing', files
    assert files['a6'] == 'none|storage', files
    for bad in ['broken.example', 'corrupt.example', 'plain.example']:
        out = run('open', '0', bad, 'wekan', 'cards', code=3)
        assert out[0].startswith('unreadable|'), out
    assert run('dbs', '0', 'nodb.example') == ['default=']
    assert run('dbs', '0', '../weddy/domains/one.example', code=2) == ['nosite']
    assert run('dbs', '0', 'link.example', code=2) == ['nosite']
    assert run('dbs', '0', 'Bad_Name', code=2) == ['nosite']
    for leaf, ok in [('a.txt', '1'), ('..', '0'), ('.', '0'), ('a/b', '0'), ('a\\b', '0'), ('c:x', '0'), ('', '0'), ('a\tb', '0')]:
        if leaf:
            assert run('leaf', leaf) == [ok], leaf
    print('PASS: reader harness (%s FerretDB database)' % ('live' if live else 'stopped'))


def http_checks(server_bin, roots, tmp, backend, env_base):
    data = tmp / ('welite-' + backend)
    listen = port()
    env = dict(env_base, WELITE_DATA=str(data), WELITE_SHARED='0', WELITE_PORT=str(listen),
               WELITE_SCHEMA=str(ROOT / 'src/schema.sql'), WELITE_DESIGNER=str(ROOT / 'src/designer.sql'),
               WELITE_I18N=str(ROOT / 'i18n'), WELITE_WEKAN_ROOTS=';'.join(map(str, roots)))
    for variable in ['REQUIRE_2FA', 'LDAP_ENABLE', 'WELITE_ENTROPY_FILE', 'WELITE_ARGON_SECRET_FILE', 'WELITE_SHORT_NAMES']:
        env.pop(variable, None)
    boot = subprocess.run([str(server_bin), 'initadmin', 'global-admin'], cwd=tmp,
                          env=dict(env, WELITE_ADMIN_PASSWORD='global-test-password'), capture_output=True)
    assert boot.returncode == 0, boot.stderr
    log = (tmp / ('server-' + backend + '.log')).open('w+')
    proc = subprocess.Popen([str(server_bin)], cwd=tmp, env=env, stdout=log, stderr=log)

    def request(method, path, data=None, host='admin'):
        conn = http.client.HTTPConnection('127.0.0.1', listen, timeout=20)
        headers = {'Host': host, 'User-Agent': 'Welite-test'}
        body = None
        if data is not None:
            headers['Content-Type'] = 'application/x-www-form-urlencoded'
            body = urlencode(data)
        conn.request(method, path, body, headers)
        resp = conn.getresponse()
        result = resp.status, dict(resp.getheaders()), resp.read()
        conn.close()
        return result
    try:
        for _ in range(200):
            try:
                request('GET', '/sign-in')
                break
            except (OSError, http.client.HTTPException):
                if proc.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(.05)
        def session(response):
            # Sign-in answers with the signed-in page (or a redirect) carrying the session.
            status, headers, body = response
            if status == 302:
                return parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
            assert status == 200, (status, body[-400:])
            return re.search(rb'name="sessionId" value="([0-9a-f]+)"', body).group(1).decode()
        admin = session(request('POST', '/sign-in', {'username': 'global-admin', 'password': 'global-test-password'}))
        local = session(request('POST', '/register', {'username': 'local-admin', 'password': 'test-password',
                                                      'confirm': 'test-password'}, host='localhost'))

        def page(path, **query):
            status, headers, body = request('GET', path + '?' + urlencode(dict(query, sessionId=admin)))
            return status, headers, body.decode('utf-8')

        # Access: the Global Admin only. NEGATIVE: no session, a Domain Global Admin.
        assert request('GET', '/wekan')[0] == 302
        assert request('GET', '/wekan/board?root=0&domain=one.example&board=b1')[0] == 302
        assert request('GET', '/wekan?sessionId=' + local, host='localhost')[0] == 403
        assert request('GET', '/wekan/file?root=0&domain=one.example&board=b1&card=c1&file=a1&sessionId=' + local,
                       host='localhost')[0] == 403
        status, _, home = request('GET', '/admin?sessionId=' + admin)
        assert status == 200 and b'action="/wekan"' in home, home
        status, _, home = request('GET', '/admin?sessionId=' + local, host='localhost')
        assert status == 200 and b'action="/wekan"' not in home

        status, headers, body = page('/wekan')
        assert status == 200 and headers.get('Cache-Control') == 'no-store' and 'Set-Cookie' not in headers, headers
        assert body.startswith('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"'), body[:80]
        assert '<script' not in body.lower()
        for name in ['one.example', 'two.example', 'broken.example', 'corrupt.example', 'plain.example', 'nodb.example',
                     '>single<', '>files<', '2026-01-01', '2026-12-31']:
            assert name in body, name
        assert 'Bad_Name' not in body and 'link.example' not in body
        row = re.search(r'<tr><td><a [^>]*>one\.example</a></td>(.*?)</tr>', body).group(1)
        cells = re.findall(r'<td[^>]*>(.*?)</td>', row)
        sizes = len(wkfix.TEXT) + len(wkfix.PNG) + 7 + 7 + 7 + 11 + 3
        assert cells[:5] == ['wekan', '3', '5', '7', str(sizes)], cells
        assert body.count('No readable WeKan database was found.') == 4, body
        # The new message in another language, from the shared WeKan catalogs.
        fi = json.loads((ROOT / 'i18n/data/fi.jsn').read_text())['wekan-data-no-database']
        status, _, finnish = page('/wekan', lang='fi')
        assert status == 200 and finnish.count(fi) == 4 and 'lang="fi"' in finnish, fi

        status, _, body = page('/wekan/boards', root='0', domain='one.example')
        assert status == 200
        assert 'Garden &lt;b&gt;&amp;&lt;/b&gt; board' in body and '<b>&</b>' not in body
        row = re.search(r'board=b1[^>]*>Garden.*?</tr>', body).group(0)
        assert re.findall(r'<td>([^<]*)</td>', row)[-4:] == ['2', '4', '6', str(sizes - 3)], row
        assert 'Old archive</a> <small>(Archived)</small>' in body and 'template-container' in body

        status, _, board = page('/wekan/board', root='0', domain='one.example', board='b1')
        assert status == 200
        assert '&lt;script&gt;alert(1)&lt;/script&gt;' in board and '<script' not in board.lower(), board
        heads = re.findall(r'<th valign="top">([^<]*)</th>', board)
        assert heads == ['To do (1)', 'Doing (1)', 'Lane two only (1)'], heads
        lanes = re.findall(r'<tr><th align="left" valign="top">([^<]*)</th>', board)
        assert lanes == ['Default', 'Second lane'], lanes
        for gone in ['Archived card', 'Archived list', 'Archived lane', 'Old card']:
            assert gone not in board, gone
        assert '<font color="#' in board and '[Urgent]' in board and '[green]' in board
        assert 'Members: alice' in board and 'Assignees: bob' in board
        assert 'Due: 2026-11-19 12:34 UTC' in board and 'Checklists 1/2' in board and 'Comments 1' in board
        assert 'Attachments 4' in board and 'Attachments 2' in board
        assert 'Cards: 4 &nbsp; Attachments: 6' in board
        # Second-lane list only in its own lane: the first row has an empty cell under it.
        first = board.split('<tr><th align="left" valign="top">Default</th>')[1].split('<tr><th align="left" valign="top">')[0]
        assert first.endswith('<td valign="top">&nbsp;</td></tr>') and 'Second lane card' not in first, first

        status, _, card = page('/wekan/card', root='0', domain='one.example', board='b1', card='c1')
        assert status == 200
        assert '<h1>&lt;script&gt;alert(1)&lt;/script&gt;</h1>' in card and '<script' not in card.lower()
        assert 'Line one<br>&lt;b&gt;bold&lt;/b&gt; &amp; more' in card
        assert '<th align="left">Notes</th><td>Text &lt;value&gt;</td>' in card
        assert '<th align="left">Priority</th><td>High</td>' in card
        assert '<th align="left">Deadline</th><td>2026-11-23 12:34 UTC</td>' in card
        assert '<th align="left">Approved</th><td>[x] Yes</td>' in card
        assert '<li>[x] Dig</li>' in card and '<li>[ ] Plant &lt;seeds&gt;</li>' in card
        assert '<b>bob</b>' in card and 'Looks &lt;i&gt;good&lt;/i&gt;' in card
        assert 'gone.txt' not in card and 'notes.txt' in card and 'photo.png' in card
        assert card.count('>Download</a>') == 2, card
        assert '>Not found</td>' in card

        def file(fid, card='c1', **extra):
            return request('GET', '/wekan/file?' + urlencode(dict(root='0', domain='one.example', board='b1', card=card,
                                                                 file=fid, sessionId=admin, **extra)))
        status, headers, raw = file('a1')
        assert status == 200 and raw == wkfix.TEXT, (status, raw)
        assert headers['Content-Disposition'].startswith('attachment;') and headers['Content-Type'] == 'application/octet-stream'
        status, headers, raw = file('a2', preview='1')
        assert status == 200 and raw == wkfix.PNG and headers['Content-Type'] == 'image/png'
        assert headers['Content-Disposition'].startswith('inline;')
        status, _, raw = file('a1', view='1')
        assert status == 200 and b'<pre>Garden notes\nline two &amp; &lt;tags&gt;\n</pre>' in raw, raw
        status, _, raw = file('a2', view='1')
        assert status == 200 and b'<img src="/wekan/file?' in raw and b'preview=1' in raw
        status, _, raw = file('a6', card='c2', view='1')
        assert status == 200 and b'gridfs' in raw
        # NEGATIVE: path traversal, symlinks and ids that do not belong together.
        for fid, cid in [('a3', 'c1'), ('../../secret', 'c1'), ('a5', 'c2'), ('a6', 'c2'), ('a1', 'c2'), ('a7', 'c1'),
                         ('a9', 'c1'), ('a9', 'c5'), ('missing', 'c1'), ('../../../etc/passwd', 'c1')]:
            status, _, raw = file(fid, card=cid)
            assert status == 404 and b'SECRET' not in raw and b'root:' not in raw, (fid, cid, status, raw[:200])
        for query in [dict(domain='../weddy/domains/one.example'), dict(domain='one.example/../two.example'),
                      dict(domain='link.example'), dict(domain='Bad_Name'), dict(root='99'), dict(root='-1'),
                      dict(db='../wekan'), dict(db='wekan.sqlite'), dict(db='local'), dict(board='tb'),
                      dict(board='../b1')]:
            args = dict(dict(root='0', domain='one.example', board='b1', card='c1', file='a1'), **query)
            status, _, raw = request('GET', '/wekan/file?' + urlencode(dict(args, sessionId=admin)))
            assert status == 404 and raw != wkfix.TEXT, (query, status)
            status, _, raw = request('GET', '/wekan/board?' + urlencode(dict(args, sessionId=admin)))
            assert status == 404 and b'Garden' not in raw, (query, status)
        status, _, raw = page('/wekan/card', root='0', domain='one.example', board='b1', card='c5')
        assert status == 404 and 'Old card' not in raw
        # NEGATIVE: malformed and missing databases.
        for domain in ['broken.example', 'corrupt.example', 'plain.example', 'nodb.example', 'absent.example']:
            status, _, raw = page('/wekan/boards', root='0', domain=domain)
            assert status == 404 and ('No readable WeKan database was found.' in raw), (domain, status)
        # The other roots: Docker-style WRITABLE_PATH and the Snap files folder.
        for root in ['1', '2']:
            status, _, raw = page('/wekan/board', root=root, domain='', board='tb')
            assert status == 200 and 'Only card in two' in raw and 'Backlog (1)' in raw, (root, raw)
        assert request('GET', '/wekan/card?' + urlencode(dict(root='0', domain='one.example', board='b1', card='c1',
                                                              sessionId=admin, lang='ar')))[0] == 200
        print('PASS: WeKan data pages over HTTP (%s SQLite)' % backend)
    finally:
        proc.terminate()
        proc.wait(20)
        log.close()


def main():
    tmpdir = os.environ.get('TMPDIR')
    assert tmpdir, 'Set TMPDIR to a directory under the parent .tools/tmp'
    ferret = wkfix.ferretdb()
    with tempfile.TemporaryDirectory(prefix='wkdir-', dir=tmpdir) as directory:
        tmp = Path(directory)
        roots, running = make_tree(tmp, ferret)
        env = dict(os.environ, WELITE_WEKAN_ROOTS=';'.join(map(str, roots)))
        env.pop('WELITE_SHORT_NAMES', None)
        builds = {}
        for backend, flags in [('linked', []), ('cli', ['-dWLDB_CLI'])]:
            compile_program(ROOT / 'tests/wkdir.lpr', tmp / 'build' / backend / 'harness', flags)
            compile_program(ROOT / 'src/wlhttp.lpr', tmp / 'build' / backend / 'server', flags)
            builds[backend] = tmp / 'build' / backend
        before = snapshot(*roots)
        try:
            if running:
                db = roots[0] / 'domains/one.example/files/db/wekan.sqlite'
                assert Path(str(db) + '-wal').exists() and Path(str(db) + '-shm').exists(), 'FerretDB keeps a WAL'
                for backend in builds:
                    harness_checks(builds[backend] / 'harness/wkdir', env, live=True)
                    http_checks(builds[backend] / 'server/wlhttp', roots, tmp, backend + '-live', env)
                live_after = snapshot(*roots)
                assert live_after == before, set(live_after.items()) ^ set(before.items())
        finally:
            if running:
                wkfix.stop(*running)
        before = snapshot(*roots)
        for backend in builds:
            harness_checks(builds[backend] / 'harness/wkdir', env, live=False)
            http_checks(builds[backend] / 'server/wlhttp', roots, tmp, backend, env)
        after = snapshot(*roots)
        assert after == before, set(after.items()) ^ set(before.items())
        print('PASS: no file in the WeKan data folders was created, changed or removed')
        if not ferret:
            print('NOTE: FerretDB not found; databases were loaded from the FerretDB-written dumps in tests/wkdir/')


if __name__ == '__main__':
    main()

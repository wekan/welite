"""HTTP regressions for every Designer administrator gate; no cookies or JS."""
import http.client
from html.parser import HTMLParser
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import time
from urllib.parse import urlencode, urlsplit, parse_qs

ROOT = Path(__file__).resolve().parents[1]
GETS = ['/designer', '/designer/page', '/designer/page/export', '/designer/export']
POSTS = ['/designer/page/save', '/designer/widget/move', '/designer/widget/save', '/designer/page/import', '/designer/import']

with tempfile.TemporaryDirectory(prefix='wladmin-', dir=os.environ['TMPDIR']) as tmp:
    tmp = Path(tmp)
    build = tmp / 'build'
    build.mkdir()
    result = subprocess.run([os.environ.get('FPC', 'fpc'), '-B', '-FU'+str(build), '-FE'+str(build), str(ROOT/'src/wlhttp.lpr')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, WELITE_PORT=str(port), WELITE_SCHEMA=str(ROOT/'src/schema.sql'), WELITE_DESIGNER=str(ROOT/'src/designer.sql'))
    with (tmp/'server.log').open('w+') as log:
        proc = subprocess.Popen([str(build/'wlhttp')], cwd=tmp, env=env, stdout=log, stderr=log)
        def request(method, path, data=None, agent='Welite-test'):
            conn = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
            headers = {'Host': 'localhost', 'User-Agent': agent}
            if data is not None:
                headers['Content-Type'] = 'application/x-www-form-urlencoded'
            conn.request(method, path, urlencode(data) if data is not None else None, headers)
            resp = conn.getresponse()
            result = resp.status, dict(resp.getheaders()), resp.read()
            conn.close()
            return result
        try:
            for attempt in range(100):
                try:
                    request('GET', '/sign-in')
                    break
                except (OSError, http.client.HTTPException):
                    if proc.poll() is not None:
                        log.seek(0)
                        raise RuntimeError(log.read())
                    time.sleep(.05)
            else:
                raise RuntimeError('Server did not start')
            def register(name):
                status, headers, _ = request('POST', '/register', {'username':name, 'password':'test-password', 'confirm':'test-password'})
                assert status == 302, (status, headers)
                return parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
            admin = register('administrator')
            member = register('member')
            db = tmp/'data/local/db/data.db'
            assert request('GET', '/designer?sessionId='+admin)[0] == 200
            with sqlite3.connect(db) as con:
                con.execute("INSERT INTO pages(id,url,title,createdAt,modifiedAt) VALUES('p','/demo','Secret page','now','now')")
            if os.environ.get('WELITE_UI') == '1':
                subprocess.run([os.environ.get('NODE', 'node'), str(ROOT/'tests/pages.js'), 'http://localhost:'+str(port), admin], check=True)
            for path in GETS + POSTS:
                method = 'POST' if path in POSTS else 'GET'
                for session, expected in [('', 302), (member, 403), ('invalid', 302)]:
                    data = {'sessionId':session} if method == 'POST' else None
                    target = path + '?' + urlencode({'sessionId':session, 'url':'/demo'})
                    status, _, body = request(method, target, data)
                    assert status == expected, (path, session, status, body)
                # A session with the wrong client binding must never authorize an admin.
                status, _, _ = request(method, path+'?'+urlencode({'sessionId':admin, 'url':'/demo'}), {'sessionId':admin} if method == 'POST' else None, 'Wrong-agent')
                assert status == 302, (path, 'client binding', status)
            for path in GETS:
                status, _, body = request('GET', path+'?'+urlencode({'sessionId':admin, 'url':'/demo'}))
                assert status == 200, (path, status, body)
            for path in POSTS:
                status, _, _ = request('POST', path, {'sessionId':admin})
                assert status == 403, (path, 'missing action token', status)
            class HiddenFields(HTMLParser):
                def __init__(self):
                    super().__init__()
                    self.fields = {}
                def handle_starttag(self, tag, attrs):
                    attrs = dict(attrs)
                    if tag == 'form':
                        self.fields = {}
                    if tag == 'input' and attrs.get('type') == 'hidden':
                        self.fields[attrs['name']] = attrs.get('value', '')
            def page_action(fields):
                status, _, body = request('GET', '/designer?sessionId='+admin)
                assert status == 200
                parser = HiddenFields()
                parser.feed(body.decode())
                data = dict(parser.fields, **fields)
                return request('POST', '/designer/page/save', data)
            base = dict(action='save', url='/example', title='<Example & title>', cols='2', doctype='html4', dir='rtl', minRole='admin')
            assert page_action(base)[0] == 302
            with sqlite3.connect(db) as con:
                page_id = con.execute("SELECT id FROM pages WHERE url='/example'").fetchone()[0]
            assert page_action(base)[0] == 409
            for bad in ['//example.com', '/designer', '/admin/domains', '/api/test', '/a/../b', '/bad?x=1', '/bad#fragment']:
                assert page_action(dict(base, url=bad))[0] == 400, bad
            assert page_action(dict(base, cols='0', url='/badcols'))[0] == 400
            assert page_action(dict(base, dir='invalid', url='/baddir'))[0] == 400
            status, _, body = request('GET', '/designer/page?'+urlencode({'id':page_id, 'sessionId':admin}))
            assert status == 200 and b'&lt;Example &amp; title&gt;' in body
            assert request('GET', '/example?sessionId='+member)[0] == 404
            assert request('GET', '/example?sessionId='+admin)[0] == 200
            assert page_action(dict(base, pageId=page_id, title='Changed', url='/changed'))[0] == 302
            assert request('GET', '/example?sessionId='+admin)[0] == 404
            assert request('GET', '/changed?sessionId='+admin)[0] == 200
            assert page_action(dict(pageId=page_id, action='disable'))[0] == 302
            assert request('GET', '/changed?sessionId='+admin)[0] == 404
            assert request('GET', '/designer/page?'+urlencode({'id':page_id, 'sessionId':admin}))[0] == 200
            assert page_action(dict(pageId=page_id, action='enable'))[0] == 302
            assert request('GET', '/changed?sessionId='+admin)[0] == 200
            with sqlite3.connect(db) as con:
                con.execute("INSERT INTO page_widgets(id,pageId,col,type,createdAt,modifiedAt) VALUES('widget',?,1,'label','now','now')", (page_id,))
            assert page_action(dict(base, pageId=page_id, cols='1'))[0] == 400
            assert page_action(dict(pageId=page_id, action='delete'))[0] == 302
            with sqlite3.connect(db) as con:
                assert con.execute("SELECT COUNT(*) FROM page_widgets WHERE id='widget'").fetchone()[0] == 0
            assert request('GET', '/designer/page?id='+page_id+'&sessionId='+admin)[0] == 404
            print('PASS: page creation/edit/enable/disable/delete, schema provisioning, validation, access roles and widget cascade')
            with sqlite3.connect(db) as con:
                con.execute("UPDATE users SET isAdmin=0 WHERE username='administrator'")
            assert request('GET', '/designer?sessionId='+admin)[0] == 403
            with sqlite3.connect(db) as con:
                con.execute("UPDATE users SET isAdmin=1,loginDisabled=1 WHERE username='administrator'")
            assert request('GET', '/designer?sessionId='+admin)[0] == 403
            with sqlite3.connect(db) as con:
                con.execute('DELETE FROM login_tokens')
            assert request('GET', '/designer?sessionId='+admin)[0] == 302
            print('PASS: all Designer gates, role changes, disabled users, revoked tokens, client binding')
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

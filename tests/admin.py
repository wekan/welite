"""HTTP regressions for every Designer administrator gate; no cookies or JS."""
import http.client
import json
import hashlib
from apiscope import run as check_api_scope
from tiers import run as check_admin_tiers
from layout import run as check_layout
from imports import run as check_imports
from actions import run as check_actions
from clone import run as check_clone
from bodyids import run as check_body_ids
from sessions import run as check_sessions
from tokens import run as check_tokens
from drop import run as check_drop
from store import run as check_store
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
POSTS = ['/designer/widget/sort', '/designer/widget/delete', '/designer/page/save', '/designer/widget/move', '/designer/widget/save', '/designer/page/import', '/designer/import']

with tempfile.TemporaryDirectory(prefix='wladmin-', dir=os.environ['TMPDIR']) as tmp:
    tmp = Path(tmp)
    build = tmp / 'build'
    build.mkdir()
    (tmp/'public').symlink_to(ROOT/'public',target_is_directory=True)
    result = subprocess.run([os.environ.get('FPC', 'fpc'), *(['-dWLNOOSRAND'] if os.environ.get('WELITE_NO_OS_RNG')=='1' else []), *(['-dWLDB_CLI'] if os.environ.get('WELITE_DB_CLI')=='1' else []), '-B', '-FU'+str(build), '-FE'+str(build), str(ROOT/'src/wlhttp.lpr')], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, WELITE_DATA=str(tmp/'data'),WELITE_SHARED='0',WELITE_PORT=str(port), WELITE_SCHEMA=str(ROOT/'src/schema.sql'), WELITE_DESIGNER=str(ROOT/'src/designer.sql'),WELITE_I18N=str(ROOT/'i18n'))
    for variable in ['WELITE_ARGON_MEMORY_KIB','WELITE_ARGON_PASSES','WELITE_ARGON_LANES','REQUIRE_2FA','LDAP_ENABLE','LDAP_LOGIN_FALLBACK','LDAP_MIGRATION_ALLOW_PASSWORD_LOGIN','WELITE_ARGON_KEY_BYTES','WELITE_ARGON_SECRET_FILE']:env.pop(variable,None)
    env.pop('WELITE_ENTROPY_FILE',None)  # Never consume an operator's stock in tests.
    if os.environ.get('WELITE_NO_OS_RNG')=='1':
        import secrets
        stock=tmp/'random.db'
        with sqlite3.connect(stock) as db:
            db.execute('CREATE TABLE entropy(id INTEGER PRIMARY KEY,value BLOB CHECK(length(value)=32))')
            db.executemany('INSERT INTO entropy(value) VALUES(?)',[(secrets.token_bytes(32),) for _ in range(2048)])
        env['WELITE_ENTROPY_FILE']=str(stock)
    bootstrap_env = dict(env, WELITE_ADMIN_PASSWORD='global-test-password')
    bootstrap = subprocess.run([str(build/'wlhttp'),'initadmin','global-admin'],cwd=tmp,env=bootstrap_env,capture_output=True)
    assert bootstrap.returncode == 0, bootstrap.stderr
    repeat = subprocess.run([str(build/'wlhttp'),'initadmin','second-admin'],cwd=tmp,env=bootstrap_env,capture_output=True)
    assert repeat.returncode != 0 and b'already initialized' in repeat.stderr
    with (tmp/'server.log').open('w+') as log:
        proc = subprocess.Popen([str(build/'wlhttp')], cwd=tmp, env=env, stdout=log, stderr=log)
        def request(method, path, data=None, agent='Welite-test', host='localhost', content_type=None, extra_headers=None):
            # Independent credential/policy scenarios get a fresh attempt window.
            # otphttp.py tests shared web/API allowances without this fixture reset.
            if method=='POST' and path in ('/sign-in','/users/login'):
                database=tmp/'data/local/files/db/wekan.db'
                if database.is_file():
                    with sqlite3.connect(database) as con:
                        if con.execute("SELECT 1 FROM sqlite_master WHERE name='_wl_attempt'").fetchone():
                            con.execute('UPDATE _wl_attempt SET started=0')
            conn = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
            headers = {'Host': host, 'User-Agent': agent}
            if data is not None:
                headers['Content-Type'] = content_type or ('application/json' if isinstance(data, bytes) else 'application/x-www-form-urlencoded')
            headers.update(extra_headers or {})
            conn.request(method, path, data if isinstance(data, bytes) else urlencode(data) if data is not None else None, headers)
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
                status, headers, body = request('POST', '/register', {'username':name, 'password':'test-password', 'confirm':'test-password'})
                assert status == 302, (status, headers, body)
                return parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
            admin = register('administrator')
            member = register('member')
            check_admin_tiers(request,tmp,admin)
            db = tmp/'data/local/files/db/wekan.db'
            with sqlite3.connect(db) as con:
                passwords=[json.loads(row[0])['password'] for row in con.execute("SELECT services_json FROM users WHERE username IN ('administrator','member') ORDER BY username")]
            with sqlite3.connect(tmp/'data/admin/files/db/wekan.db') as con:
                bootstrap_password=json.loads(con.execute('SELECT services_json FROM users').fetchone()[0])['password']
            for value in passwords+[bootstrap_password]:
                assert isinstance(value,dict) and value['bcrypt'].startswith('$2b$10$'),value
            assert passwords[0]!=passwords[1],'New accounts must receive independent salts'
            # Long UTF-8 plaintext works through registration and the CLI seed contract.
            seeded_password='日本語 🔑 '+('long-password-'*8)
            response=request('POST','/register',dict(username='credential-format',password=seeded_password,confirm=seeded_password))
            assert response[0]==302,response
            original_session=parse_qs(urlsplit(response[1]['Location']).query)['sessionId'][0]
            assert request('GET','/api/user?token='+original_session)[0]==200
            generated=subprocess.run([str(build/'wlhttp'),'hashpw',seeded_password],cwd=tmp,env=env,capture_output=True,text=True,check=True)
            seed=json.loads(generated.stdout)
            assert isinstance(seed,dict) and seed['bcrypt'].startswith('$2b$10$')
            with sqlite3.connect(db) as con:
                con.execute('UPDATE users SET services_json=? WHERE username=?',(json.dumps(dict(password=seed)),'credential-format'))
            assert request('GET','/api/user?token='+original_session)[0]==401
            assert request('POST','/sign-in',dict(username='credential-format',password=seeded_password))[0]==302
            assert request('POST','/users/login',dict(username='credential-format',password=seeded_password))[0]==200
            assert request('POST','/users/login',dict(username='credential-format',password=seeded_password+'wrong'))[0]==401
            # Existing PBKDF2 records still authenticate; login never rewrites them.
            legacy_salt=bytes(range(16))
            legacy='pbkdf2_sha1$50000$'+legacy_salt.hex()+'$'+hashlib.pbkdf2_hmac('sha1',seeded_password.encode(),legacy_salt,50000).hex()
            legacy_services=json.dumps(dict(password=legacy))
            with sqlite3.connect(db) as con:con.execute('UPDATE users SET services_json=? WHERE username=?',(legacy_services,'credential-format'))
            assert request('POST','/sign-in',dict(username='credential-format',password=seeded_password))[0]==302
            assert request('POST','/users/login',dict(username='credential-format',password=seeded_password))[0]==200
            with sqlite3.connect(db) as con:
                assert con.execute('SELECT services_json FROM users WHERE username=?',('credential-format',)).fetchone()[0]==legacy_services
            print('PASS: default registration/bootstrap Meteor bcrypt objects, fresh salts, long UTF-8 passwords, CLI JSON seeding, legacy login and credential revocation')
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
            from gatelang import run as check_gate_language
            check_gate_language(request,db,admin,member)
            for path in GETS:
                status, _, body = request('GET', path+'?'+urlencode({'sessionId':admin, 'url':'/demo'}))
                assert status == 200, (path, status, body)
            for path in POSTS:
                status, _, _ = request('POST', path, {'sessionId':admin})
                assert status == 403, (path, 'missing action token', status)
            with sqlite3.connect(db) as con:
                uid = con.execute("SELECT id FROM users WHERE username='member'").fetchone()[0]
                con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('protected','Private title','protected','now')")
                con.execute("INSERT INTO board_members(boardId,userId) VALUES('protected',?)", (uid,))
            assert request('PUT', '/api/boards/protected/title?token='+member, {'title':'Updated'})[0] == 200
            with sqlite3.connect(db) as con:
                con.execute("UPDATE board_members SET isReadOnly=1 WHERE boardId='protected'")
            assert request('PUT', '/api/boards/protected/title?token='+member, {'title':'Forbidden'})[0] == 403
            assert request('GET', '/api/boards/protected?token='+member)[0] == 200
            with sqlite3.connect(db) as con:
                con.execute("UPDATE board_members SET isReadOnly=0,isCommentOnly=1 WHERE boardId='protected'")
            assert request('PUT', '/api/boards/protected/title?token='+member, {'title':'Forbidden'})[0] == 403
            assert b'Private title' not in request('GET', '/')[2]
            assert request('POST', '/board/move', {'sessionId':member, 'boardId':'protected', 'sel_card':'foreign'})[0] == 403
            print('PASS: shared API board policy, private home visibility and move guard')
            with sqlite3.connect(db) as con:
                con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('lane','protected','Swimlane <one>',0,'now')")
                for lid, title, order in [('todo','To do',0), ('doing','Doing',1)]:
                    con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'protected','lane',?,?,'now')", (lid,title,order))
                con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,title,userId,createdAt,modifiedAt,dateLastActivity) VALUES('card','protected','todo','lane','Card <test>',?,'now','now','now')", (uid,))
            assert request('GET', '/board?id=protected')[0] == 404
            status, _, body = request('GET', '/board?id=protected&sessionId='+member)
            assert status == 200 and b'Card &lt;test&gt;' in body and b'sel_card' not in body
            status, _, body = request('GET', '/board?id=protected&sessionId='+admin)
            assert status == 200 and b'sel_card' in body and b'Swimlane &lt;one&gt;' in body
            if os.environ.get('WELITE_UI') == '1':
                subprocess.run([os.environ.get('NODE', 'node'), str(ROOT/'tests/board.js'), 'http://localhost:'+str(port), admin], check=True)
                with sqlite3.connect(db) as con:
                    assert con.execute("SELECT listId FROM cards WHERE id='card'").fetchone()[0] == 'doing'
            status, _, body = request('GET', '/board?id=protected&x=999&y=-5&sessionId='+admin)
            assert status == 200 and b'X 2 Y 1' in body and b'data-list="doing"' in body
            assert b'data-list="todo"' not in body
            check_api_scope(request, db, admin)
            from langhttp import check_language
            check_language(request,db,admin)
            from homelang import run as check_home_language
            check_home_language(request,db,admin,member,'http://localhost:'+str(port))
            from viewlang import run as check_view_language
            check_view_language(request,db,admin,member,'http://localhost:'+str(port))
            from boardtxt import run as check_board_text
            check_board_text(request,db,admin,'http://localhost:'+str(port))
            from keyhttp import run as check_keypad_protocol
            check_keypad_protocol(request,db,admin)
            from editlang import run as check_edit_language
            check_edit_language(request,db,admin,'http://localhost:'+str(port))
            print('PASS: authorized board renderer, escaped content and read-only controls')
            from notlang import run as check_not_found_language
            check_not_found_language(request,tmp/'data',admin)
            class HiddenFields(HTMLParser):
                def __init__(self):
                    super().__init__()
                    self.fields = {}
                    self.forms = []
                    self.action = None
                def handle_starttag(self, tag, attrs):
                    attrs = dict(attrs)
                    if tag == 'form':
                        self.fields = {}
                        self.action = attrs.get('action')
                    if tag == 'input' and attrs.get('type') == 'hidden':
                        self.fields[attrs['name']] = attrs.get('value', '')
                def handle_endtag(self, tag):
                    if tag == 'form':
                        self.forms.append((self.action, dict(self.fields)))
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
            assert page_action(dict(base, doctype='invalid', url='/baddoc'))[0] == 400
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
            with sqlite3.connect(db) as con:
                con.execute("DELETE FROM page_widgets WHERE id='widget'")
            def widget_action(path, fields, widget_id=''):
                target = '/designer/page?'+urlencode({'id':page_id, 'sessionId':admin, 'widgetId':widget_id})
                status, _, body = request('GET', target)
                assert status == 200
                parser = HiddenFields()
                parser.feed(body.decode())
                forms = [data for action, data in parser.forms if action == path and (not widget_id or data.get('widgetId') == widget_id)]
                assert forms, (path, widget_id)
                return request('POST', path, dict(forms[-1], **fields))
            widget = dict(type='select', label='<Choices>', name='choice', value='two', target='/sign-in', binding='', row='0', col='0', rowspan='1', colspan='1', sort='0.5', options_json='{"options":[{"value":"one","label":"<One>"},{"value":"two","label":"Two"}]}', fgColor='', bgColor='', required='1')
            assert widget_action('/designer/widget/save', widget)[0] == 302
            with sqlite3.connect(db) as con:
                widget_id = con.execute('SELECT id FROM page_widgets WHERE pageId=?', (page_id,)).fetchone()[0]
            status, _, body = request('GET', '/changed?sessionId='+admin)
            assert status == 200 and b'&lt;One&gt;' in body and b'value="two" selected' in body
            for bad in [dict(row='100'), dict(col='2'), dict(colspan='3'), dict(rowspan='0'), dict(type='unknown'), dict(options_json='[]'), dict(sort='NaN'), dict(target='javascript:alert(1)'), dict(bgColor='not-a-color')]:
                assert widget_action('/designer/widget/save', dict(widget, **bad), widget_id)[0] == 400, bad
            for direction in ['right', 'right', 'up', 'left', 'left']:
                assert widget_action('/designer/widget/move', {'dir':direction}, widget_id)[0] == 302
                with sqlite3.connect(db) as con:
                    row, col = con.execute('SELECT row,col FROM page_widgets WHERE id=?', (widget_id,)).fetchone()
                    assert row == 0 and 0 <= col < 2
            assert widget_action('/designer/widget/move', {'dir':'invalid'}, widget_id)[0] == 400
            assert widget_action('/designer/widget/save', dict(widget, label='Edited'), widget_id)[0] == 302
            with sqlite3.connect(db) as con:
                assert con.execute('SELECT label FROM page_widgets WHERE id=?', (widget_id,)).fetchone()[0] == 'Edited'
            assert widget_action('/designer/widget/delete', {}, widget_id)[0] == 302
            with sqlite3.connect(db) as con:
                assert con.execute('SELECT COUNT(*) FROM page_widgets WHERE id=?', (widget_id,)).fetchone()[0] == 0
            print('PASS: widget add/edit/delete, options escaping/selection, input validation and movement bounds')
            assert page_action(dict(pageId=page_id, action='delete'))[0] == 302
            with sqlite3.connect(db) as con:
                assert con.execute("SELECT COUNT(*) FROM page_widgets WHERE id='widget'").fetchone()[0] == 0
            assert request('GET', '/designer/page?id='+page_id+'&sessionId='+admin)[0] == 404
            print('PASS: page creation/edit/enable/disable/delete, schema provisioning, validation, access roles and widget cascade')
            layout_editor = check_layout(request,db,admin)
            if os.environ.get('WELITE_UI') == '1':
                subprocess.run([os.environ.get('NODE','node'), str(ROOT/'tests/layout.js'), 'http://localhost:'+str(port), admin, layout_editor],check=True)
            from langnav import check_navigation
            check_navigation(request,db,admin)
            from frames import check_frames
            check_frames(request,db,admin,layout_editor,member)
            from widgetrt import run as check_widget_direction
            check_widget_direction(request,db,admin,member,'http://localhost:'+str(port))
            from tabrtl import run as check_table_direction
            check_table_direction(request,db,admin,'http://localhost:'+str(port))
            if os.environ.get('WELITE_UI')=='1':
                subprocess.run([os.environ.get('NODE','node'),str(ROOT/'tests/langnav.js'),'http://localhost:'+str(port),admin,layout_editor],check=True)
            check_imports(request,db,admin)
            if os.environ.get('WELITE_UI') == '1':
                subprocess.run([os.environ.get('NODE','node'),str(ROOT/'tests/imports.js'),'http://localhost:'+str(port),admin],check=True)
            check_body_ids(request,db,admin,member)
            check_clone(request,db,admin)
            check_actions(request,db,admin)
            if os.environ.get('WELITE_UI') == '1':
                subprocess.run([os.environ.get('NODE','node'),str(ROOT/'tests/actions.js'),'http://localhost:'+str(port),admin],check=True)
            check_sessions(request,db,admin)
            check_store(request,db,admin)
            check_drop(request,db,admin)
            if os.environ.get('WELITE_UI')=='1':
                subprocess.run([os.environ.get('NODE','node'),str(ROOT/'tests/drag.js'),'http://localhost:'+str(port),admin],check=True)
            check_tokens(request,db,admin)
            with sqlite3.connect(db) as con:
                con.execute("UPDATE users SET isAdmin=0 WHERE username='administrator'")
            assert request('GET', '/designer?sessionId='+admin)[0] == 403
            with sqlite3.connect(db) as con:
                con.execute("UPDATE users SET isAdmin=1,loginDisabled=1 WHERE username='administrator'")
            assert request('GET', '/designer?sessionId='+admin)[0] == 302
            with sqlite3.connect(db) as con:
                con.execute('DELETE FROM login_tokens')
            assert request('GET', '/designer?sessionId='+admin)[0] == 302
            if os.environ.get('WELITE_SHORT_NAMES')=='1':
                import re
                for path in (tmp/'data').rglob('*'):
                    assert re.fullmatch(r'[A-Za-z0-9_-]{1,8}(\.[A-Za-z0-9_-]{1,3})?',path.name),path
                assert not list((tmp/'data/temp').rglob('upload.tmp')),'Framework upload bytes were not cleaned up'
                print('PASS: every live generated runtime component, including SQLite sidecars and attachment bytes, is DOS 8.3')
            print('PASS: all Designer gates, role changes, disabled users, revoked tokens, client binding')
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

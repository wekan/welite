import re
"""HTTP role and host isolation checks, called by admin.py."""
from autherr import check as check_auth_error
from frames import Document
from html.parser import HTMLParser
from urllib.parse import parse_qs, urlsplit
import sqlite3
from paths import domain_db

class Fields(HTMLParser):
    def __init__(self):
        super().__init__()
        self.fields = {}
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'form':
            self.fields = {}
        if tag == 'input' and attrs.get('type') == 'hidden':
            self.fields[attrs['name']] = attrs.get('value', '')

def run(request, tmp, local_admin):
    assert request('GET', '/admin/domains?sessionId='+local_admin)[0] == 403
    assert request('POST', '/admin/domains', {'sessionId':local_admin,'action':'add','host':'forbidden.example'})[0] == 403
    status, _, body = request('GET', '/admin?sessionId='+local_admin)
    assert status == 200 and b'Domain Global Admin' in body and b'href="/admin/domains' not in body
    for host in ['unknown.example', '127.0.0.1.evil.example', 'x127.0.0.1x', 'fake::1.example']:
        assert request('GET', '/sign-in', host=host)[0] == 404, host
    assert request('GET', '/sign-in', host='[::1]:5500')[0] == 200
    denied=request('POST','/register',dict(username='attacker',password='x',confirm='x',lang='ar'),host='admin')
    assert denied[0]==403;check_auth_error(denied,'ar',title_key='register')
    assert '<p>تُنشأ حسابات المسؤولين العامّين محليًا. التسجيل العام معطّل.</p>'.encode() in denied[2]
    assert 'Location' not in denied[1]
    # Signed in, the home page comes at once with the session in its forms
    # (fd5f992: the session no longer travels in a redirect's URL).
    status, headers, body = request('POST', '/sign-in', {'username':'global-admin','password':'global-test-password'}, host='admin')
    assert status == 200 and 'Location' not in headers, (status,headers)
    global_admin = re.search(rb'name="sessionId" value="([0-9a-f]{64})"', body).group(1).decode()
    assert request('GET', '/admin/domains?sessionId='+global_admin, host='admin')[0] == 200
    assert request('GET', '/admin/domains?sessionId='+local_admin, host='admin')[0] == 302
    assert request('GET', '/admin/domains?sessionId='+global_admin)[0] == 302
    registry = tmp/'data/admin/files/db/wekan.db'
    def action(host,verb='add',language=''):
        source='/admin/domains?sessionId='+global_admin
        if language:source+='&lang='+language
        status,_,body=request('GET',source,host='admin')
        assert status == 200
        parser = Fields()
        parser.feed(body.decode())
        return request('POST','/admin/domains',dict(parser.fields,host=host,action=verb),host='admin')
    def error_frame(result,status,tag):
        code,headers,body=result;assert code==status
        doc=Document();doc.feed(body.decode())
        assert headers['Content-Language']==tag and 'Accept-Language' in headers['Vary']
        assert doc.html['lang']==tag and (doc.html.get('dir')=='rtl')==(tag=='ar')
        assert (doc.body.get('dir')=='rtl')==(tag=='ar')
    error_frame(request('POST','/admin/domains',dict(sessionId=global_admin,lang='ar'),host='admin'),403,'ar')
    for bad in ['../escape','admin','local','localhost','127.0.0.1','bad/host','bad..host','-bad.example','bad-.example']:
        error_frame(action(bad,language='ar'),400,'ar')
    error_frame(action('unknown-action.example',verb='unknown',language='fi'),400,'fi')
    with sqlite3.connect(registry) as con:
        con.execute("CREATE TRIGGER frameprov BEFORE INSERT ON domains BEGIN SELECT RAISE(ABORT,'forced'); END")
    try:
        error_frame(action('failed.example',language='fi'),500,'fi')
        with sqlite3.connect(registry) as con:
            assert con.execute("SELECT 1 FROM domains WHERE host='failed.example'").fetchone() is None
    finally:
        with sqlite3.connect(registry) as con:con.execute('DROP TRIGGER frameprov')
    assert action('team.example')[0] == 302
    db = domain_db(tmp/'data','team.example')
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 0
    # Registered, the home page comes at once with the session in its forms (fd5f992).
    status, headers, body = request('POST','/register',{'username':'team-admin','password':'test-password','confirm':'test-password'},host='team.example')
    assert status == 200 and 'Location' not in headers, (status,headers)
    team_admin = re.search(rb'name="sessionId" value="([0-9a-f]{64})"', body).group(1).decode()
    assert request('GET','/admin/people?sessionId='+team_admin,host='team.example')[0] == 200
    assert request('GET','/designer?sessionId='+team_admin,host='team.example')[0] == 200
    assert request('GET','/admin/domains?sessionId='+team_admin,host='team.example')[0] == 403
    assert request('GET','/admin/people?sessionId='+team_admin)[0] == 302
    with sqlite3.connect(registry) as con:
        assert con.execute("SELECT host FROM domains ORDER BY host").fetchall() == [('team.example',)]
    assert action('team.example','disable')[0] == 302
    assert request('GET','/admin/people?sessionId='+team_admin,host='team.example')[0] == 404
    assert action('team.example','enable')[0] == 302
    assert request('GET','/admin/people?sessionId='+team_admin,host='team.example')[0] == 200
    with sqlite3.connect(registry) as con:
        assert con.execute('SELECT username,isAdmin FROM users').fetchall() == [('global-admin',1)]
    print('PASS: local-only Global Admin bootstrap, tenant admin separation, domain provision/enable/disable and host isolation')

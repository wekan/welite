"""HTTP role and host isolation checks, called by admin.py."""
from html.parser import HTMLParser
from urllib.parse import parse_qs, urlsplit
import sqlite3

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
    assert request('POST', '/register', {'username':'attacker','password':'x','confirm':'x'}, host='admin')[0] == 403
    status, headers, _ = request('POST', '/sign-in', {'username':'global-admin','password':'global-test-password'}, host='admin')
    assert status == 302, (status,headers)
    global_admin = parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
    assert request('GET', '/admin/domains?sessionId='+global_admin, host='admin')[0] == 200
    assert request('GET', '/admin/domains?sessionId='+local_admin, host='admin')[0] == 302
    assert request('GET', '/admin/domains?sessionId='+global_admin)[0] == 302
    registry = tmp/'data/admin/db/data.db'
    def action(host, verb='add'):
        status, _, body = request('GET','/admin/domains?sessionId='+global_admin,host='admin')
        assert status == 200
        parser = Fields()
        parser.feed(body.decode())
        return request('POST','/admin/domains',dict(parser.fields,host=host,action=verb),host='admin')
    for bad in ['../escape','admin','local','localhost','127.0.0.1','bad/host','bad..host','-bad.example','bad-.example']:
        assert action(bad)[0] == 400, bad
    assert action('team.example')[0] == 302
    db = tmp/'data/domains/team.example/db/data.db'
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT COUNT(*) FROM users").fetchone()[0] == 0
    status, headers, _ = request('POST','/register',{'username':'team-admin','password':'test-password','confirm':'test-password'},host='team.example')
    assert status == 302
    team_admin = parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
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

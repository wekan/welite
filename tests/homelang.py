"""Native home captions follow viewer language without exposing private boards."""
from html.parser import HTMLParser
import json
import os
import subprocess
from pathlib import Path
import sqlite3
from urllib.parse import parse_qs, urlencode, urlsplit

root = Path(__file__).resolve().parents[1]
english = json.loads((root / 'i18n/data/en.jsn').read_text())
catalog = json.loads((root / 'i18n/locales.jsn').read_text())

class Page(HTMLParser):
    def __init__(self, body):
        super().__init__(); self.parts = []; self.items = []
        self.feed(body.decode())
    def handle_starttag(self, tag, attrs):
        if tag in ('h2', 'a', 'b'):
            self.parts.append((tag, dict(attrs), []))
    def handle_data(self, text):
        for _, _, parts in self.parts:
            parts.append(text)
    def handle_endtag(self, tag):
        if self.parts and self.parts[-1][0] == tag:
            name, attrs, parts = self.parts.pop()
            self.items.append((name, attrs, ''.join(parts)))
    def captions(self, path):
        return [text for tag, attrs, text in self.items
                if tag == 'a' and urlsplit(attrs['href']).path == path]
    def board_ids(self):
        return [parse_qs(urlsplit(attrs['href']).query).get('id', [''])[0]
                for tag, attrs, _ in self.items
                if tag == 'a' and urlsplit(attrs['href']).path == '/board']

def run(request, database, administrator, member, base):
    def words(tag):
        row = next(row for row in catalog if row['tag'] == tag)
        local = json.loads((root / 'i18n/data' / row['file']).read_text())
        return row, {key: local.get(key) or value for key, value in english.items()}
    def check(tag, session='', query=None, header='', agent='Welite-test'):
        row, local = words(tag)
        fields = {} if query is None else dict(query)
        if session: fields['sessionId'] = session
        status, headers, body = request('GET', '/?' + urlencode(fields), agent=agent,
                                        extra_headers={'Accept-Language': header})
        assert status == 200 and 'Set-Cookie' not in headers
        assert headers['Content-Language'] == tag.replace('_', '-')
        assert 'Accept-Language' in headers['Vary']
        assert ('dir="rtl"' in body.decode()) == row['rtl'], tag
        page = Page(body)
        assert ('h2', {}, local['boards']) in page.items, (tag, 'boards', page.items)
        assert page.captions('/sign-in') == [local['log-in']], (tag, 'log-in')
        assert page.captions('/register') == [local['register']], (tag, 'register')
        assert b'<script' not in body.lower()
        return page, body, local
    with sqlite3.connect(database) as con:
        originals = con.execute("SELECT id,profile_json FROM users WHERE username IN ('administrator','member')").fetchall()
        uid = con.execute("SELECT id FROM users WHERE username='member'").fetchone()[0]
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('homelang','Home <safe>','homelang','now')")
        con.execute("INSERT INTO board_members(boardId,userId) VALUES('homelang',?)", (uid,))
        public = con.execute("SELECT count(*) FROM boards WHERE permission='public' AND archived=0").fetchone()[0]
    try:
        for row in catalog:
            tag = row['tag']
            guest, body, local = check(tag, query={'lang': tag})
            assert 'homelang' not in guest.board_ids()
            assert b'Home &lt;safe&gt;' not in body
            if not public:
                assert local['no-items-message'].encode() in body, (tag, 'empty')
            signed, body, _ = check(tag, member, {'lang': tag})
            assert 'homelang' in signed.board_ids()
            assert b'Home &lt;safe&gt;' in body and b'Home <safe>' not in body
            assert not signed.captions('/admin')
        with sqlite3.connect(database) as con:
            con.execute("UPDATE users SET profile_json=? WHERE username='administrator'", (json.dumps({'language': 'ar'}),))
            con.execute("UPDATE users SET profile_json=? WHERE username='member'", (json.dumps({'language': 'he'}),))
        page, _, local = check('ar', administrator, header='fi')
        assert page.captions('/admin') == [local['admin-panel']]
        assert ('b', {}, local['admin']) in page.items
        assert check('he', member, header='fi')[0].captions('/admin') == []
        check('fi', administrator, {'lang': 'fi'}, header='he')
        check('he', member, {'lang': 'unknown'}, header='fi')
        check('he', header='fi;q=0.1,he;q=0.9')
        for session, agent in [('invalid', 'Welite-test'), (administrator, 'Wrong-agent')]:
            page, _, _ = check('fi', session, header='fi', agent=agent)
            assert not page.captions('/admin') and 'homelang' not in page.board_ids()
        # An earlier explicit choice must not leak to a later anonymous request.
        check('en')
        if os.environ.get('WELITE_UI') == '1':
            subprocess.run([os.environ.get('NODE', 'node'), str(root / 'tests/homelang.js'),
                            base, administrator, member], check=True)
    finally:
        with sqlite3.connect(database) as con:
            con.execute("DELETE FROM board_members WHERE boardId='homelang'")
            con.execute("DELETE FROM boards WHERE id='homelang'")
            con.executemany('UPDATE users SET profile_json=? WHERE id=?', [(profile, uid) for uid, profile in originals])
    print('PASS: all installed home captions/empty states, profile/query/header precedence, role and private-board isolation, escaped titles and request isolation')

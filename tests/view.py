"""The HTML4 and HTML5 views on one backend (src/wlview.pas, src/wlh5.pas).

A modern browser gets the HTML5 view - Weddy's markup, which is WeKan's - and a
retro or unknown one the HTML4 view. ?ui=html4|html5 switches and is kept in
the welite-ui cookie. The HTML5 view signs in with WeKan's meteor_login_token
cookie. Linked and CLI SQLite.
"""
import html
import http.client
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
FPC = os.environ.get('FPC', 'fpc')

CHROME = 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
HEADLESS = 'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/140.0.7339.16 Safari/537.36'
FIREFOX = 'Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0'
SAFARI = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15'
IBROWSE = 'IBrowse/3.0 (Amiga; MorphOS 3.19; Build 30.8 68K)'
NETSURF = 'Mozilla/5.0 (X11; Linux) NetSurf/3.11'
DILLO = 'Dillo/3.0.5'
OLD_CHROME = 'Mozilla/5.0 (Windows NT 6.1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.112 Safari/537.36'
IE = 'Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko'


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def pure_checks(tmp):
    src = tmp / 'vwcheck.lpr'
    agents = [CHROME, HEADLESS, FIREFOX, SAFARI, IBROWSE, NETSURF, DILLO, OLD_CHROME, IE, 'Welite-test', '']
    lines = ['program vwcheck;', '{$mode objfpc}{$H+}', 'uses SysUtils, wlview;', 'begin']
    for agent in agents:
        lines.append("  WriteLn(ViewName(DefaultView('%s')));" % agent.replace("'", "''"))
    lines += [
        "  WriteLn(ViewSwitchUrl('/b/x/y?view=all', wvHtml5));",
        "  WriteLn(ViewSwitchUrl('/b/x/y?ui=html4&a=1', wvHtml5));",
        "  WriteLn(ViewSwitchUrl('', wvHtml4));",
        "  WriteLn(ViewSwitchUrl('//evil.example/x', wvHtml4));",
        "  WriteLn(ViewSwitchUrl('http://evil.example/', wvHtml4));",
        'end.']
    src.write_text('\n'.join(lines) + '\n')
    build = tmp / 'vw-build'
    build.mkdir(exist_ok=True)
    result = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(build), '-FE' + str(build), str(src)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, result.stdout
    out = subprocess.run([str(build / 'vwcheck')], capture_output=True, text=True, check=True).stdout.splitlines()
    assert out[:len(agents)] == ['html5', 'html5', 'html5', 'html5',
                                 # Negative: retro, old and unknown browsers get HTML4.
                                 'html4', 'html4', 'html4', 'html4', 'html4', 'html4', 'html4'], out
    assert out[len(agents):] == [
        '/b/x/y?view=all&ui=html5',
        '/b/x/y?a=1&ui=html5',            # one ui=, the new one
        '/?ui=html4',
        '/?ui=html4',                     # negative: never another host
        '/?ui=html4',
    ], out
    print('PASS: view choice and toggle URL')
    # Negative, the whole source: LiveAttachmentSQL names the attachments
    # table unaliased and aliases its own as a, so no query that uses it may
    # alias attachments (in a shared store every such query failed).
    import re as _re
    for pas in sorted((ROOT / 'src').glob('*.pas')):
        text = pas.read_text(encoding='utf-8', errors='replace')
        for m in _re.finditer(r'LiveAttachmentSQL\(', text):
            before = text[max(0, m.start() - 600):m.start()]
            stmt = before[before.rfind(';') + 1:]
            # FROM or JOIN attachments a ... - the WHERE form and the JOIN form both.
            assert not _re.search(r'\b(?:FROM|JOIN)\s+attachments\s+(?:AS\s+)?(?!WHERE\b|JOIN\b|ON\b|LEFT\b|INNER\b)[a-z]\w*',
                                  stmt, _re.I), (pas.name, stmt[-200:])
    print('PASS: no aliased attachments beside LiveAttachmentSQL')
    # Negative: the server is linked without a widestring manager, so a
    # WideString case or compare function fails at run time on every page.
    for pas in sorted((ROOT / 'src').glob('*.pas')):
        text = pas.read_text(encoding='utf-8', errors='replace')
        bad = _re.findall(r'\b(?:Wide(?:Upper|Lower)Case|WideCompare(?:Str|Text)|WideSameText|UnicodeUpperCase|UnicodeLowerCase)\s*\(', text)
        assert not bad, (pas.name, bad)
    print('PASS: no widestring manager needed')
    # Negative: a transaction is one Exec. The CLI backend runs each Exec as
    # its own sqlite3 process, so a BEGIN in an Exec of its own commits nothing
    # it was meant to guard.
    for pas in sorted((ROOT / 'src').glob('*.pas')):
        text = pas.read_text(encoding='utf-8', errors='replace')
        bad = _re.findall(r"Exec\('(?:BEGIN(?: IMMEDIATE)?|COMMIT);?'\)", text)
        assert not bad, (pas.name, bad)
    print('PASS: every transaction is one Exec')


def http_checks(server, tmp, backend):
    data = tmp / ('data-' + backend)
    listen = free_port()
    env = dict(os.environ, WELITE_DATA=str(data), WELITE_SHARED='0', WELITE_PORT=str(listen),
               WELITE_SCHEMA=str(ROOT / 'src/schema.sql'), WELITE_DESIGNER=str(ROOT / 'src/designer.sql'),
               WELITE_I18N=str(ROOT / 'i18n'), WELITE_PUBLIC=str(ROOT / 'public'),
               # WeKan's password policy from the environment, enforced.
               PASSWORD_MIN_LENGTH='9', PASSWORD_MIN_LENGTH_ENFORCE='true')
    for variable in ['REQUIRE_2FA', 'LDAP_ENABLE', 'WELITE_ENTROPY_FILE', 'WELITE_ARGON_SECRET_FILE', 'WELITE_SHORT_NAMES']:
        env.pop(variable, None)
    log = (tmp / ('server-' + backend + '.log')).open('w+')
    proc = subprocess.Popen([str(server)], cwd=tmp, env=env, stdout=log, stderr=log)

    def request(method, path, data=None, agent=CHROME, cookie=None, headers=None, as_json=False):
        conn = http.client.HTTPConnection('127.0.0.1', listen, timeout=20)
        h = {'Host': 'localhost', 'User-Agent': agent}
        if cookie:
            h['Cookie'] = cookie
        h.update(headers or {})
        body = None
        if isinstance(data, bytes):
            body = data
        elif data is not None:
            if as_json:
                h['Content-Type'] = 'application/json'
                body = json.dumps(data)
            else:
                h['Content-Type'] = 'application/x-www-form-urlencoded'
                body = urlencode(data)
        conn.request(method, path, body, h)
        resp = conn.getresponse()
        cookies = [v for k, v in resp.getheaders() if k.lower() == 'set-cookie']
        result = resp.status, dict(resp.getheaders()), resp.read(), cookies
        conn.close()
        return result

    def cookie_value(cookies, name):
        for c in cookies:
            m = re.match(r'\s*%s=([^;]*)' % re.escape(name), c)
            if m:
                return m.group(1)
        return None

    try:
        for _ in range(200):
            try:
                request('GET', '/sign-in', agent='Welite-test')
                break
            except (OSError, http.client.HTTPException):
                if proc.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                time.sleep(.05)
        # Accounts and a board, through the HTML4 view and the REST API.
        for name in ['owner', 'stranger', 'commenter', 'silent', 'worker']:
            status, _, _, _ = request('POST', '/sign-up', {'username': name, 'password': 'test-password',
                                                          'confirm': 'test-password'}, agent='Welite-test')
            assert status == 200
        status, _, body, _ = request('POST', '/users/login', {'username': 'owner', 'password': 'test-password'})
        login = json.loads(body)
        auth = {'Authorization': 'Bearer ' + login['token']}
        board = json.loads(request('POST', '/api/boards', {'title': 'View Board', 'owner': login['id']},
                                   headers=auth, as_json=True)[2])
        board_id, lane = board['_id'], board['defaultSwimlaneId']
        list_id = json.loads(request('POST', '/api/boards/%s/lists' % board_id, {'title': 'Todo'},
                                     headers=auth, as_json=True)[2])['_id']
        card_id = json.loads(request('POST', '/api/boards/%s/lists/%s/cards' % (board_id, list_id),
                                     {'title': 'View Card', 'description': 'The card <b>text</b>',
                                      'authorId': login['id'], 'swimlaneId': lane},
                                     headers=auth, as_json=True)[2])['_id']
        route = '/b/%s/view-board' % board_id

        # The User-Agent chooses: Chromium gets WeKan's sign-in form, IBrowse
        # and an unknown agent the HTML4 one.
        status, _, page, _ = request('GET', '/sign-in')
        assert status == 200 and page.startswith(b'<!DOCTYPE html>') and b'id="at-pwd-form"' in page
        assert b'href="/static/wekan.css"' in page and b'js-html-view-toggle' in page
        assert b'href="/sign-in?ui=html4"' in page, 'the toggle goes to the same page in HTML4'
        for agent in [IBROWSE, 'Welite-test']:
            status, _, page, _ = request('GET', '/sign-in', agent=agent)
            assert status == 200 and b'HTML 3.2' in page and b'id="at-pwd-form"' not in page, agent
            assert b'href="/sign-in?ui=html5"' in page, 'the HTML4 toggle'
        # Weddy's static files, under 8.3 names.
        for name in ['wekan.css', 'weddy.js', 'unpoly.js', 'unpoly.css', 'interact.js', 'welite.css', 'welite.js']:
            status, _, body, _ = request('GET', '/static/' + name)
            assert status == 200 and len(body) > 200, name

        # Signed out, the HTML5 view sends to its sign-in page.
        status, headers, _, _ = request('GET', '/')
        assert status == 302 and headers['Location'] == '/sign-in'
        # Signing in in the HTML5 view keeps the session in WeKan's cookie.
        status, headers, _, cookies = request('POST', '/sign-in', {'username': 'owner', 'password': 'test-password'})
        assert status == 302 and headers['Location'] == '/', status
        token = cookie_value(cookies, 'meteor_login_token')
        assert token and any('HttpOnly' in c for c in cookies), cookies
        owner = 'meteor_login_token=' + token

        # All Boards: WeKan's sections and a li.js-board.<id> under Remaining.
        status, _, page, _ = request('GET', '/', cookie=owner)
        assert status == 200 and b'class="board-list-menu js-board-sections"' in page
        assert re.search(rb'<li class="menu-item[^"]*"><a class="js-select-menu" href="/allboards/remaining"', page)
        status, _, page, _ = request('GET', '/allboards/remaining', cookie=owner)
        assert ('class="js-board %s"' % board_id).encode() in page, page[-600:]
        assert ('href="%s"' % route).encode() in page
        # The board: WeKan's .board-wrapper, lists and minicards.
        status, _, page, _ = request('GET', route, cookie=owner)
        assert status == 200 and b'class="board-wrapper' in page and b'class="board-canvas"' in page
        assert ('id="js-list-%s"' % list_id).encode() in page and b'class="minicard-wrapper js-minicard"' in page
        assert ('up-href="%s/%s"' % (route, card_id)).encode() in page
        assert b'View Card' in page and b'card-details' not in page
        # The card: its details inside the board's wrapper, escaped.
        status, _, page, _ = request('GET', '%s/%s' % (route, card_id), cookie=owner)
        assert status == 200 and b'class="card-details js-card-details"' in page
        assert re.search(rb'<div class="board-wrapper[^>]*>.*<div class="card-details js-card-details"', page, re.S)
        assert b'The card &lt;b&gt;text&lt;/b&gt;' in page and b'<b>text</b>' not in page
        assert ('class="js-close-card-details" href="%s"' % route).encode() in page

        # weddy.js's callAsync: toggleCardMaximized, WeKan's own Meteor method.
        card_path = '%s/%s' % (route, card_id)
        status, _, body, _ = request('POST', '/_methods/toggleCardMaximized', [], cookie=owner, as_json=True)
        assert status == 200 and json.loads(body) == {'result': 1}, body
        page = request('GET', card_path, cookie=owner)[2]
        assert b'card-details js-card-details card-details-maximized' in page and b'js-minimize-card-details' in page
        request('POST', '/_methods/toggleCardMaximized', [], cookie=owner, as_json=True)
        page = request('GET', card_path, cookie=owner)[2]
        assert b'card-details-maximized' not in page and b'js-maximize-card-details' in page
        # Negative: no cookie is refused as Meteor refuses it, and changes nothing;
        # an unknown method is not found, its name safely in the JSON answer.
        status, _, body, _ = request('POST', '/_methods/toggleCardMaximized', [], as_json=True)
        assert status == 401 and json.loads(body)['error'] == 401
        assert b'card-details-maximized' not in request('GET', card_path, cookie=owner)[2]
        status, _, body, _ = request('POST', '/_methods/no%22such%0Amethod', [], cookie=owner, as_json=True)
        assert status == 404 and json.loads(body)['error'] == 404, body

        # Negative: a user who is no member does not see the board, nor the card.
        status, headers, _, cookies = request('POST', '/sign-in', {'username': 'stranger', 'password': 'test-password'})
        stranger = 'meteor_login_token=' + cookie_value(cookies, 'meteor_login_token')
        for path in [route, '%s/%s' % (route, card_id)]:
            status, _, page, _ = request('GET', path, cookie=stranger)
            assert status == 404 and b'<div class="big-message quiet board-not-found js-board-not-found"><h1>Board not found</h1>' in page
            assert b'board-canvas' not in page and b'View Card' not in page, path
        status, _, page, _ = request('GET', '/allboards/remaining', cookie=stranger)
        assert board_id.encode() not in page
        # Negative: a forged cookie is no session.
        status, headers, _, _ = request('GET', '/', cookie='meteor_login_token=' + 'f' * 64)
        assert status == 302 and headers['Location'] == '/sign-in'

        # Meteor's client update of a card: its title and description, with
        # WeKan's a-changedTitle / a-changedDescription activities, which the
        # board's rules read (wlrules); anything else is 403.
        def activities(kind):
            n = 0
            for path in data.glob('**/files/db/wekan.db'):
                with sqlite3.connect(path) as con:
                    if con.execute("SELECT 1 FROM sqlite_master WHERE name='activities'").fetchone():
                        n += con.execute('SELECT count(*) FROM activities WHERE cardId=? AND activityType=?', (card_id, kind)).fetchone()[0]
            return n
        before = activities('a-changedTitle')
        status, _, body, _ = request('POST', '/_methods/%2Fcards%2Fupdate', [{'_id': card_id}, {'$set': {'title': 'Renamed by update'}}],
                                     cookie=owner, as_json=True)
        assert status == 200 and json.loads(body) == {'result': 1}, body
        assert b'Renamed by update' in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert activities('a-changedTitle') == before + 1
        # The same title again changes nothing, and is no activity.
        request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, {'$set': {'title': 'Renamed by update'}}], cookie=owner, as_json=True)
        assert activities('a-changedTitle') == before + 1
        status, _, body, _ = request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, {'$set': {'description': 'Described by update'}}],
                                     cookie=owner, as_json=True)
        assert status == 200 and activities('a-changedDescription') == 1, body
        # Negative: a field the client may not write, an operator, a stranger.
        for modifier in [{'$set': {'boardId': 'elsewhere'}}, {'$set': {'title': 'x', 'sort': 1}}, {'$inc': {'sort': 1}},
                         {'$set': {'title': 7}}]:
            status, _, body, _ = request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, modifier], cookie=owner, as_json=True)
            assert status == 403 and json.loads(body)['reason'] == 'Access denied', (modifier, body)
        status, _, body, _ = request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, {'$set': {'title': 'Stolen'}}],
                                     cookie=stranger, as_json=True)
        assert status == 403 and b'Stolen' not in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, {'$set': {'title': 'View Card', 'description': 'The card <b>text</b>'}}],
                cookie=owner, as_json=True)
        # The live board (weddy.js' EventSource): an event stream for a member,
        # announced in the board's data-live; a change to the board is an event.
        # Negative: a stranger gets no stream, and nothing about the board.
        assert ('data-live="/b/%s/live?v=1"' % board_id).encode() in request('GET', route, cookie=owner)[2]
        conn = http.client.HTTPConnection('127.0.0.1', listen, timeout=10)
        conn.request('GET', '/b/%s/live?v=1&p=pagetest' % board_id, None, {'Host': 'localhost', 'User-Agent': CHROME, 'Cookie': owner})
        live = conn.getresponse()
        assert live.status == 200 and live.getheader('Content-Type', '').startswith('text/event-stream'), live.status
        assert live.fp.readline().startswith(b'retry:')
        request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, {'$set': {'title': 'Live change'}}], cookie=owner, as_json=True)
        seen = b''
        while b'event: board-changed' not in seen:
            seen += live.fp.readline()
        conn.close()
        request('POST', '/_methods/%2Fcards%2Fupdate', [card_id, {'$set': {'title': 'View Card'}}], cookie=owner, as_json=True)
        status, headers, body, _ = request('GET', '/b/%s/live?v=1' % board_id, cookie=stranger)
        assert status == 404 and b'event' not in body, (status, body)
        # Admin Panel / Problems / Security Report: a site admin's page (the
        # owner signed up first). Negative: anybody else is not authorized;
        # a search is shown back escaped, never as markup.
        status, _, page, _ = request('GET', '/admin/problems/security-report?q=%3Cb%3Ex', cookie=owner)
        assert status == 200 and b'class="table-page-table security-report"' in page and b'value="&lt;b&gt;x"' in page, page[-400:]
        assert b'<b>x' not in page
        status, _, page, _ = request('GET', '/admin/problems/security-report', cookie=stranger)
        assert status == 404 and b'security-report"' not in page
        # createCardWithDueDate: the Calendar's card on a day. Negative: no
        # date, a date that is not one, a stranger's board (AuthBleed).
        status, _, body, _ = request('POST', '/_methods/createCardWithDueDate',
                                     [board_id, list_id, 'Due card', '2027-01-01T00:00:00.000Z', lane], cookie=owner, as_json=True)
        assert status == 200 and json.loads(body)['result'], body
        due_card = json.loads(body)['result']
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='cards'").fetchone():
                    assert con.execute('SELECT dueAt FROM cards WHERE id=?', (due_card,)).fetchone() == ('2027-01-01T00:00:00.000Z',)
                    con.execute('DELETE FROM cards WHERE id=?', (due_card,))
        for args in [[board_id, list_id, 'Due card', 'tomorrow', lane], [board_id, list_id, 'Due card', lane]]:
            status, _, body, _ = request('POST', '/_methods/createCardWithDueDate', args, cookie=owner, as_json=True)
            assert status == 400, body
        status, _, body, _ = request('POST', '/_methods/createCardWithDueDate',
                                     [board_id, list_id, 'Planted', '2027-01-01T00:00:00.000Z', lane], cookie=stranger, as_json=True)
        assert status == 403 and json.loads(body)['error'] == 'not-authorized', body
        assert b'Planted' not in request('GET', route, cookie=owner)[2]
        # An uploaded avatar in the members widget, at the path WeKan is served
        # under now (avatarDisplayUrl): no old host or prefix survives, and a
        # stored value that is not an avatar is escaped, never markup.
        def set_avatar(value):
            for path in data.glob('**/files/db/wekan.db'):
                with sqlite3.connect(path) as con:
                    if con.execute("SELECT 1 FROM sqlite_master WHERE name='board_members'").fetchone():
                        con.execute("UPDATE users SET profile_json=json_set(COALESCE(profile_json,'{}'),'$.avatarUrl',?) "
                                    "WHERE id IN (SELECT userId FROM board_members WHERE boardId=?)", (value, board_id))
        set_avatar('https://old-name.example/wekan/cdn/storage/avatars/subPathAvatar1')
        page = request('GET', route, cookie=owner)[2]
        assert b'<img class="avatar avatar-image" src="/cdn/storage/avatars/subPathAvatar1"' in page, page[-600:]
        assert b'old-name.example' not in page
        set_avatar('"><script>alert(1)</script>')
        page = request('GET', route, cookie=owner)[2]
        assert b'<script>alert(1)' not in page and b'src="&quot;&gt;&lt;script&gt;' in page
        set_avatar('')
        assert b'class="avatar avatar-image"' not in request('GET', route, cookie=owner)[2]
        # isAvatarUploadBlocked (#4740): off without Admin Panel's setting.
        # Negative: it needs a login, as every method.
        status, _, body, _ = request('POST', '/_methods/isAvatarUploadBlocked', [], cookie=owner, as_json=True)
        assert status == 200 and json.loads(body) == {'result': False}, body
        assert request('POST', '/_methods/isAvatarUploadBlocked', [], as_json=True)[0] == 401
        # The date format a date is drawn in (wldatef): the member's own while
        # their override is on, the board's while its own is on, else
        # YYYY-MM-DD; refused for a format that is not one of WeKan's six.
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='cards'").fetchone():
                    con.execute("UPDATE cards SET dueAt='2026-03-21T12:00:00.000Z' WHERE id=?", (card_id,))
        def shown():
            return request('GET', route, cookie=owner)[2]
        def method(name, args, cookie=owner):
            status, _, body, _ = request('POST', '/_methods/' + name, args, cookie=cookie, as_json=True)
            return status, json.loads(body)
        assert b'>2026-03-21 12:00</time>' in shown()
        assert method('changeDateFormat', ['DD-MM-YYYY', True]) == (200, {'result': True})
        assert b'>21-03-2026 12:00</time>' in shown() and b'datetime="2026-03-21T12:00:00.000Z"' in shown()
        assert method('changeDateFormat', ['MM-DD-YYYY', False])[0] == 200
        assert b'>2026-03-21 12:00</time>' in shown(), 'not while the override is off'
        assert method('setBoardDateFormat', [board_id, 'DD-MM-YYYY-date-only', True])[0] == 200
        assert b'>21-03-2026</time>' in shown()
        for args in [[board_id, 'invalid', True], [board_id, 'DD-MM-YYYY', 'yes'], [board_id, 'DD-MM-YYYY']]:
            assert method('setBoardDateFormat', args)[0] == 400, args
        status, answer = method('setBoardDateFormat', [board_id, 'MM-DD-YYYY', True], cookie=stranger)
        assert status == 403 and answer['error'] == 'not-authorized', answer
        assert b'>21-03-2026</time>' in shown(), 'a stranger changes nothing'
        for args in [['invalid', True], ['DD-MM-YYYY', 'yes'], [7]]:
            assert method('changeDateFormat', args)[0] == 400, args
        assert method('changeStartDayOfWeek', [7])[0] == 400 and method('changeStartDayOfWeek', [1.5])[0] == 400
        assert method('changeStartDayOfWeek', [0])[0] == 200
        assert method('changeCalendarSystem', ['nope']) == (400, {'error': 'invalid-calendar-system', 'reason': 'invalid-calendar-system'})
        assert method('changeCalendarSystem', ['jalali'])[0] == 200
        assert method('setBoardDateFormat', [board_id, 'YYYY-MM-DD', False])[0] == 200
        assert b'>2026-03-21 12:00</time>' in shown()
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='cards'").fetchone():
                    con.execute('UPDATE cards SET dueAt=NULL WHERE id=?', (card_id,))
        # Member Settings / Date shows the board's line; Change Settings each
        # toggle, its check mark while on.
        page = shown()
        assert b'class="js-member-date-settings"' in page and b'class="js-change-settings"' in page
        assert b'data-popup="memberDateSettingsPopup"' in page and b'class="js-board-date-format-status"' in page
        assert b'class="pop-over-list change-settings-list"' in page and b'js-open-board-date-settings' in page
        assert b'data-method="toggleKeepTitleTags"' in page
        assert method('toggleKeepTitleTags', [])[0] == 200
        assert method('toggleKeepTitleTags', [1])[0] == 400
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='users'").fetchone():
                    profile = json.loads(con.execute("SELECT profile_json FROM users WHERE username='owner'").fetchone()[0])
                    assert profile['keepTitleTags'] is True and profile['startDayOfWeek'] == 0 and profile['calendarSystem'] == 'jalali'
                    assert profile['dateFormat'] == 'MM-DD-YYYY' and profile['dateFormatOverride'] is False, profile
        assert method('toggleKeepTitleTags', [])[0] == 200
        # The date pop-overs as they stand: for whoever is signed in, of a
        # board they may read. Negative: none without a login, none of a
        # stranger's board.
        status, _, body, _ = request('GET', '/date-settings?scope=member&board=' + board_id, cookie=owner)
        assert status == 200 and b'js-board-date-format-status' in body and b'js-member-date-format-heading' in body
        status, _, body, _ = request('GET', '/date-settings?scope=board&board=' + board_id, cookie=owner)
        assert status == 200 and b'data-board="' + board_id.encode() + b'"' in body and b'start-day-of-week' not in body
        assert request('GET', '/date-settings?scope=board&board=' + board_id, cookie=stranger)[0] == 404
        assert b'js-date-format-form' not in request('GET', '/date-settings?scope=member')[2]
        # Admin Panel / Settings / Appearance: the site admin's. Negative:
        # nobody else's, and /settings/update writes only what it may, for the
        # site admin only - here there is no shared settings document at all.
        status, _, page, _ = request('GET', '/admin/settings/appearance', cookie=owner)
        assert status == 200 and b'id="global-date-format"' in page and b'id="global-date-format-enabled"' in page
        status, _, page, _ = request('GET', '/admin/settings/appearance', cookie=stranger)
        assert status == 404 and b'id="global-date-format"' not in page and b'js-visibility-date-save' not in page
        assert method('/settings/update', [{'_id': 'x'}, {'$set': {'hideDateFormat': True}}], cookie=stranger)[0] == 403
        assert method('/settings/update', [{'_id': 'x'}, {'$set': {'hideDateFormat': True}}])[0] == 404
        # A guest's page of a public board follows it live; a private board's
        # stream is nobody's without a login.
        status, headers, body, _ = request('GET', '/b/%s/live?v=1' % board_id)
        assert not headers.get('Content-Type', '').startswith('text/event-stream') and b'event:' not in body, (status, headers)
        # Board Settings / Card (wlcardst): the two panes, a board admin's to
        # change. /boards/update writes Card Settings' own fields only, as
        # they are to be stored; /users/update the user's own split and
        # labels text; setCollapsedCardSection the user's own fold.
        page = shown()
        assert b'data-popup="boardCardSettingsPopup"' in page and b'js-open-board-card-settings' in page
        assert page.count(b'js-card-settings-pane"') == 0 and page.count(b'js-card-settings-pane ') >= 2
        assert b'data-side="minicard"' in page and b'js-card-settings-sections-sortable' in page
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'cardSettingsSectionOrder': ['comments', 'nope', 'labels', 'comments']}}])[0] == 200
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'cardSettingsHiddenOnCard': ['vote', 'labels']}}])[0] == 200
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'allowsReceivedDate': False, 'cardFieldOrder': ['dueDate', 'receivedDate']}}])[0] == 200
        for args, code in [([{'_id': board_id}, {'$set': {'title': 'Renamed'}}], 403),
                           ([{'_id': board_id}, {'$set': {'allowsReceivedDate': 'no'}}], 403),
                           ([{'_id': board_id}, {'$set': {'cardSettingsHiddenOnCard': ['nope']}}], 403),
                           ([{'_id': board_id}, {'$unset': {'allowsLabels': ''}}], 400),
                           ([{'_id': board_id}], 400)]:
            assert method('/boards/update', args)[0] == code, args
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'allowsLabels': False}}], cookie=stranger)[0] == 403
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='boards'").fetchone():
                    settings, title = con.execute('SELECT settings_json,title FROM boards WHERE id=?', (board_id,)).fetchone()
                    settings = json.loads(settings)
                    assert title == 'View Board' and settings['allowsReceivedDate'] is False and 'allowsLabels' not in settings
                    assert settings['cardSettingsSectionOrder'][:3] == ['comments', 'labels', 'date'], settings
                    assert len(settings['cardSettingsSectionOrder']) == 14
                    assert settings['cardSettingsHiddenOnCard'] == ['labels', 'vote']
                    order = settings['cardFieldOrder']
                    assert order.index('dueDate') < order.index('receivedDate') and 'nope' not in order, order
        page = shown()
        assert page.index(b'data-card-section="comments"') < page.index(b'data-card-section="date"') if b'data-card-section="comments"' in page else True
        assert b'data-card-section="labels"' not in page and b'data-card-section="vote"' not in page
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'cardSettingsHiddenOnCard': [], 'cardSettingsSectionOrder': [],
                                                                      'allowsReceivedDate': True, 'cardFieldOrder': []}}])[0] == 200
        owner_id = json.loads(request('GET', '/api/user', cookie=owner)[2])['_id']
        assert method('/users/update', [{'_id': owner_id}, {'$set': {'profile.cardSettingsSplit': 0.3}}])[0] == 200
        for args, code in [([{'_id': owner_id}, {'$set': {'profile.cardSettingsSplit': 3}}], 403),
                           ([{'_id': owner_id}, {'$set': {'username': 'evil'}}], 403),
                           ([{'_id': owner_id}, {'$set': {'profile.isAdmin': True}}], 403),
                           ([{'_id': 'someone-else'}, {'$set': {'profile.cardSettingsSplit': 0.5}}], 403)]:
            assert method('/users/update', args)[0] == code, args
        assert b'--card-settings-split: 0.3' in shown()
        assert method('setCollapsedCardSection', [board_id, 'card-settings-date', True])[0] == 200
        assert method('setCollapsedCardSection', [board_id, '__proto__', True])[0] == 400
        assert method('setCollapsedCardSection', [board_id, 'a b', True])[0] == 400
        assert b'is-collapsed" data-section="date"' in shown()
        assert method('setCollapsedCardSection', [board_id, 'card-settings-date', False])[0] == 200
        assert method('setShowLabelTextOverride', [False])[0] == 200 and method('setShowLabelTextOverride', [None])[0] == 200
        assert method('setShowLabelTextOverride', ['yes'])[0] == 400
        # The rows' minicard and card sides: the card colour (a class only for a
        # colour name), Requested By, the caret folding the card's details.
        def card_set(**values):
            for path in data.glob('**/files/db/wekan.db'):
                with sqlite3.connect(path) as con:
                    if con.execute("SELECT 1 FROM sqlite_master WHERE name='cards'").fetchone():
                        for column, value in values.items():
                            con.execute('UPDATE cards SET %s=? WHERE id=?' % column, (value, card_id))
        def opened():
            return request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        card_set(color='green', requestedBy='Requester <x>')
        page = shown()
        assert b'class="minicard minicard-green"' in page and b'card-details-header card-details-green' in opened()
        assert b'class="minicard-requested-by"' in page and b'Requester &lt;x&gt;' in page and b'Requester <x>' not in page
        card_set(color='green" onmouseover="x')
        page = shown()
        assert b'onmouseover' not in page and b'minicard-green' not in page
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'allowsCardColorOnMinicard': False, 'allowsRequestedByOnMinicard': False}}])[0] == 200
        card_set(color='green')
        page = shown()
        assert b'minicard-green' not in page and b'card-details-green' in opened() and b'minicard-requested-by' not in page
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'allowsCardColorOnMinicard': True, 'allowsRequestedByOnMinicard': True}}])[0] == 200
        card_set(color=None, requestedBy='')
        assert b'js-card-collapse-toggle' in opened()
        assert method('setCardCollapsed', [True])[0] == 200 and b'card-details-collapsed' in opened()
        assert method('setCardCollapsed', ['yes'])[0] == 400
        assert method('setCardCollapsed', [False])[0] == 200 and b'card-details-collapsed' not in opened()
        # Card's hamburger: whether each kind may be dragged (setBoardDragging),
        # and Subtasks Settings' deposit - a board the caller may write, a list
        # of it. Negative: a stranger, an unknown kind, a board or list that
        # is not the caller's to use (SubtaskDepositBleed).
        page = shown()
        assert b'class="board-drag-settings"' in page and b'data-kind="subtask"' in page and b'js-field-deposit-board' in page
        assert method('setBoardDragging', [board_id, 'card', False])[0] == 200
        assert b'data-kind="card" aria-label' in shown()
        assert method('setBoardDragging', [board_id, 'card', False], cookie=stranger)[0] == 403
        assert method('setBoardDragging', [board_id, 'nope', False])[0] == 400
        assert method('setBoardDragging', [board_id, 'card', 'no'])[0] == 400
        assert method('setBoardDragging', [board_id, 'card', True])[0] == 200
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'subtasksDefaultBoardId': board_id, 'subtasksDefaultListId': list_id}}])[0] == 200
        for bad in [{'subtasksDefaultBoardId': 'not-a-board'}, {'subtasksDefaultListId': 'no-such-list'},
                    {'subtasksDefaultBoardId': 'a"b'}, {'subtasksDefaultListId': 7}]:
            assert method('/boards/update', [{'_id': board_id}, {'$set': bad}])[0] == 403, bad
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='boards'").fetchone():
                    assert con.execute('SELECT subtasksDefaultBoardId,subtasksDefaultListId FROM boards WHERE id=?', (board_id,)).fetchone() == (board_id, list_id)
                    assert json.loads(con.execute('SELECT settings_json FROM boards WHERE id=?', (board_id,)).fetchone()[0])['allowsCardDragging'] is True
        assert method('/boards/update', [{'_id': board_id}, {'$set': {'subtasksDefaultBoardId': None}}])[0] == 200
        # The Rules need the shared store: here they say so, and write nothing.
        status, _, body, _ = request('POST', '/_methods/rules.createRule',
                                     [board_id, 'R', {'activityType': 'createCard'}, {'actionType': 'archive'}], cookie=owner, as_json=True)
        assert status == 501, body

        # Add card (board.pug's composer posts to /b/:id/cards): first or last in its list.
        status, _, page, _ = request('GET', route, cookie=owner)
        assert b'class="js-add-card list-header-plus-top"' in page and b'template class="js-card-composer-template"' in page
        assert ('action="/b/%s/cards"' % board_id).encode() in page and b'data-pop="list-menu"' in page
        for title, position in [('Top Card', 'top'), ('Bottom Card', 'bottom')]:
            status, headers, page, _ = request('POST', '/b/%s/cards' % board_id,
                                               {'listId': list_id, 'swimlaneId': lane, 'position': position, 'title': title},
                                               cookie=owner)
            assert status == 200 and b'class="board-wrapper' in page and title.encode() in page, (status, page[-300:])
            assert headers.get('X-Up-Location') == route
        cards = json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, list_id), headers=auth)[2])
        titles = [c['title'] for c in cards]
        assert titles[0] == 'Top Card' and titles[-1] == 'Bottom Card' and 'View Card' in titles, titles
        # Negative: no member, no title, no cookie, and an HTML4 form's POST all add nothing.
        status, _, _, _ = request('POST', '/b/%s/cards' % board_id, {'listId': list_id, 'swimlaneId': lane,
                                  'title': 'Stranger Card'}, cookie=stranger)
        assert status == 403, status
        status, _, _, _ = request('POST', '/b/%s/cards' % board_id, {'listId': list_id, 'swimlaneId': lane, 'title': ' '},
                                  cookie=owner)
        assert status == 400, status
        request('POST', '/b/%s/cards' % board_id, {'listId': list_id, 'swimlaneId': lane, 'title': 'Anonymous Card'})
        request('POST', '/b/%s/cards' % board_id, {'listId': list_id, 'swimlaneId': lane, 'title': 'Form Card',
                                                   'sessionId': token}, cookie=owner)
        cards = json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, list_id), headers=auth)[2])
        assert not {'Stranger Card', 'Anonymous Card', 'Form Card'} & {c['title'] for c in cards}, cards

        # The card title's editor (board.pug: POST /b/:id/cards/:cardId/title).
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert ('action="/b/%s/cards/%s/title"' % (board_id, card_id)).encode() in page
        status, headers, page, _ = request('POST', '/b/%s/cards/%s/title' % (board_id, card_id),
                                           {'title': 'Renamed Card'}, cookie=owner)
        assert status == 200 and b'Renamed Card' in page and b'js-card-details' in page, status
        assert headers.get('X-Up-Location') == '%s/%s' % (route, card_id)
        def card_title():
            cards = json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, list_id), headers=auth)[2])
            return [c['title'] for c in cards if c['_id'] == card_id][0]
        assert card_title() == 'Renamed Card'
        # Negative: no member, an empty title, and a card that is not on the board rename nothing.
        assert request('POST', '/b/%s/cards/%s/title' % (board_id, card_id), {'title': 'Stranger'}, cookie=stranger)[0] == 403
        assert request('POST', '/b/%s/cards/%s/title' % (board_id, card_id), {'title': ''}, cookie=owner)[0] == 400
        assert request('POST', '/b/%s/cards/no-such-card/title' % board_id, {'title': 'X'}, cookie=owner)[0] == 404
        assert card_title() == 'Renamed Card'

        # Checklists (_cardsec_checklists.pug): add one, add items, check one, delete it.
        base = '/b/%s/cards/%s/checklists' % (board_id, card_id)
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'class="add-checklist-top js-open-inlined-form"' in page and ('action="%s"' % base).encode() in page
        assert request('POST', base, {'title': 'Steps'}, cookie=owner)[0] == 200
        def checklists():
            return json.loads(request('GET', '/api/boards/%s/cards/%s/checklists' % (board_id, card_id), headers=auth)[2])
        cl = [c for c in checklists() if c['title'] == 'Steps'][0]
        for title in ['First', 'Second']:
            assert request('POST', '%s/%s/items' % (base, cl['_id']), {'title': title}, cookie=owner)[0] == 200
        cl = [c for c in checklists() if c['_id'] == cl['_id']][0]
        assert [i['title'] for i in cl['items']] == ['First', 'Second'], cl
        first = cl['items'][0]['_id']
        status, _, page, _ = request('POST', '%s/%s/items/%s/toggle' % (base, cl['_id'], first), {}, cookie=owner)
        assert status == 200 and b'checklist-progress-bar-container' in page and b'50%' in page
        assert [i['isFinished'] for i in [c for c in checklists() if c['_id'] == cl['_id']][0]['items']] == [True, False]
        # Negative: a non-member, another card's checklist and an empty title change nothing.
        assert request('POST', base, {'title': 'Stranger'}, cookie=stranger)[0] == 403
        assert request('POST', '%s/%s/items/%s/toggle' % (base, cl['_id'], first), {}, cookie=stranger)[0] == 403
        assert request('POST', '%s/%s/delete' % (base, cl['_id']), {}, cookie=stranger)[0] == 403
        other = '/b/%s/cards/%s/checklists' % (board_id, 'no-such-card')
        assert request('POST', '%s/%s/items' % (other, cl['_id']), {'title': 'X'}, cookie=owner)[0] == 404
        assert request('POST', base, {'title': ' '}, cookie=owner)[0] == 400
        assert [i['isFinished'] for i in [c for c in checklists() if c['_id'] == cl['_id']][0]['items']] == [True, False]
        # Delete, by the form and by WeKan's collection method.
        assert request('POST', '%s/%s/delete' % (base, cl['_id']), {}, cookie=owner)[0] == 200
        assert not [c for c in checklists() if c['_id'] == cl['_id']]
        request('POST', base, {'title': 'By method'}, cookie=owner)
        cl2 = [c for c in checklists() if c['title'] == 'By method'][0]['_id']
        status, _, body, _ = request('POST', '/_methods/%2Fchecklists%2Fremove', [{'title': 'By method'}],
                                     cookie=owner, as_json=True)
        assert status == 403 and 'only remove documents by ID' in json.loads(body)['reason'], 'negative: by ID only'
        status, _, body, _ = request('POST', '/_methods/%2Fchecklists%2Fremove', [{'_id': cl2}], cookie=stranger, as_json=True)
        assert status == 403 and [c for c in checklists() if c['_id'] == cl2], 'negative: a non-member removes nothing'
        status, _, body, _ = request('POST', '/_methods/%2Fchecklists%2Fremove', [{'_id': cl2}], cookie=owner, as_json=True)
        assert status == 200 and json.loads(body) == {'result': 1} and not [c for c in checklists() if c['_id'] == cl2]

        # Comments (_cardsec_comments.pug), with WeKan's comment capability:
        # Comment only may comment, No comments may not (boardRoleCapabilities.js).
        users = {u['username']: u['_id'] for u in json.loads(request('GET', '/api/users', headers=auth)[2])}
        for name, role in [('commenter', 'isCommentOnly'), ('silent', 'isNoComments'), ('worker', 'isWorker')]:
            status, _, body, _ = request('POST', '/api/boards/%s/members/%s/add' % (board_id, users[name]),
                                         {'action': 'add', 'isAdmin': False, role: True}, headers=auth, as_json=True)
            assert status == 200, body
        def cookie_of(name):
            cookies = request('POST', '/sign-in', {'username': name, 'password': 'test-password'})[3]
            return 'meteor_login_token=' + cookie_value(cookies, 'meteor_login_token')
        commenter, silent, worker = cookie_of('commenter'), cookie_of('silent'), cookie_of('worker')
        comments_path = '/b/%s/cards/%s/comments' % (board_id, card_id)
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert ('action="%s"' % comments_path).encode() in page
        status, _, page, _ = request('POST', comments_path, {'comment': 'Owner <i>note</i>'}, cookie=owner)
        assert status == 200 and b'Owner &lt;i&gt;note&lt;/i&gt;' in page and b'<i>note</i>' not in page
        assert request('POST', comments_path, {'comment': 'From comment only'}, cookie=commenter)[0] == 200
        # Comment only may comment but not change the card.
        assert request('POST', '/b/%s/cards/%s/title' % (board_id, card_id), {'title': 'X'}, cookie=commenter)[0] == 403
        # Negative: No comments, a non-member and an empty comment add nothing;
        # the No comments member gets no comment form.
        assert request('POST', comments_path, {'comment': 'From no comments'}, cookie=silent)[0] == 403
        assert b'js-new-comment-form' not in request('GET', '%s/%s' % (route, card_id), cookie=silent)[2]
        assert request('POST', comments_path, {'comment': 'From stranger'}, cookie=stranger)[0] == 403
        assert request('POST', comments_path, {'comment': '  '}, cookie=owner)[0] == 400
        texts = [c['comment'] for c in json.loads(request('GET', '/api/boards/%s/cards/%s/comments' % (board_id, card_id),
                                                          headers=auth)[2])]
        assert texts == ['Owner <i>note</i>', 'From comment only'], texts

        # Add a list: the swimlane's Add list form (last), and weddy.js's
        # createListAfter after a given list (server/models/lists.js).
        page = request('GET', route, cookie=owner)[2]
        assert b'js-add-list-here' in page and b'js-add-list-inline-template' in page
        assert request('POST', '/b/%s/lists' % board_id, {'title': 'Done', 'swimlaneId': lane}, cookie=owner)[0] == 200
        def list_titles():
            return [l['title'] for l in json.loads(request('GET', '/api/boards/%s/lists' % board_id, headers=auth)[2])]
        assert list_titles()[-1] == 'Done', list_titles()
        status, _, body, _ = request('POST', '/_methods/createListAfter', [{'title': 'Doing', 'boardId': board_id,
                                     'swimlaneId': lane, 'afterListId': list_id, 'type': 'list'}], cookie=owner, as_json=True)
        assert status == 200 and json.loads(body)['result'], body
        assert list_titles() == ['Todo', 'Doing', 'Done'], list_titles()
        # Negative: a non-member, and a list to follow that is not on the board.
        assert request('POST', '/b/%s/lists' % board_id, {'title': 'Stranger', 'swimlaneId': lane}, cookie=stranger)[0] == 403
        status, _, body, _ = request('POST', '/_methods/createListAfter', [{'title': 'Lost', 'boardId': board_id,
                                     'afterListId': 'no-such-list'}], cookie=owner, as_json=True)
        assert status == 404, body
        assert 'Stranger' not in list_titles() and 'Lost' not in list_titles()
        # weddy.js's user and session looks, with the cookie only.
        status, _, body, _ = request('GET', '/api/user', cookie=owner)
        assert status == 200 and json.loads(body)['username'] == 'owner', body
        assert request('GET', '/_session', cookie=owner)[0] == 200
        assert request('GET', '/_session')[0] == 401
        # Negative: the cookie opens no other REST route.
        assert request('GET', '/api/boards/%s' % board_id, cookie=owner)[0] == 401

        # The card's members (_cardsec_members.pug): the "+" and the pop-over of
        # board members, each a form that puts the member on the card or takes
        # them off, with the REST API's member checks and its activity.
        card_path = '/b/%s/cards/%s' % (board_id, card_id)
        def card_doc():
            return json.loads(request('GET', '/api/boards/%s/lists/%s/cards/%s' % (board_id, list_id, card_id),
                                      headers=auth)[2])
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'js-add-members' in page and b'data-pop="card-members"' in page
        assert ('action="%s/members/%s"' % (card_path, login['id'])).encode() in page
        status, _, page, _ = request('POST', '%s/members/%s' % (card_path, login['id']), {}, cookie=owner)
        assert status == 200 and b'card-member js-member' in page and card_doc()['members'] == [login['id']]
        status, _, page, _ = request('POST', '%s/members/%s' % (card_path, login['id']), {}, cookie=owner)
        assert status == 200 and card_doc()['members'] == [], 'the same form takes the member off again'
        # Negative: a user who is no member of the board cannot be put on the
        # card, and a non-member or Comment only changes nothing.
        assert request('POST', '%s/members/%s' % (card_path, users['stranger']), {}, cookie=owner)[0] == 400
        assert request('POST', '%s/members/%s' % (card_path, login['id']), {}, cookie=stranger)[0] == 403
        assert request('POST', '%s/members/%s' % (card_path, users['commenter']), {}, cookie=commenter)[0] == 403
        assert b'js-add-members' not in request('GET', '%s/%s' % (route, card_id), cookie=commenter)[2]
        assert card_doc()['members'] == []
        # The REST API's member route shares the write: on, off, and not a non-member.
        rest_member = '/api/boards/%s/lists/%s/cards/%s/members/%%s' % (board_id, list_id, card_id)
        assert request('POST', rest_member % users['commenter'], {}, headers=auth, as_json=True)[0] == 200
        assert card_doc()['members'] == [users['commenter']]
        assert request('DELETE', rest_member % users['commenter'], headers=auth)[0] == 200
        assert request('POST', rest_member % users['stranger'], {}, headers=auth, as_json=True)[0] == 400
        assert card_doc()['members'] == []

        # Labels (_cardsec_labels.pug): cardLabelsPopup puts a board label on
        # the card or takes it off; createLabelPopup, for a board admin, adds
        # one with the REST API's checks (PUT /api/boards/:id/labels, #5819).
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'js-add-labels' in page and b'data-pop="card-labels"' in page and b'data-pop="create-label"' in page
        status, _, page, _ = request('POST', '/b/%s/labels' % board_id, {'name': 'Urgent <x>', 'color': 'red', 'card': card_id},
                                     cookie=owner)
        assert status == 200 and b'card-details js-card-details' in page, 'back to the open card'
        found = re.findall(rb'/labels/([0-9a-f]+)" up-submit up-target="\.board-wrapper"><button class="card-label '
                           rb'card-label-selectable js-select-label card-label-(\w+)" type="submit">Urgent &lt;x&gt;<', page)
        assert len(found) == 1 and found[0][1] == b'red' and b'<x>' not in page, found
        urgent = found[0][0].decode()
        status, _, page, _ = request('POST', '%s/labels/%s' % (card_path, urgent), {}, cookie=owner)
        assert status == 200 and card_doc()['labelIds'] == [urgent]
        assert ('class="card-label card-label-red" data-label="%s"' % urgent).encode() in page
        assert request('POST', '%s/labels/%s' % (card_path, urgent), {}, cookie=owner)[0] == 200
        assert card_doc()['labelIds'] == [], 'the same form takes it off again'
        # The REST route shares the write: the same name and color is the same label.
        status, _, body, _ = request('PUT', '/api/boards/%s/labels' % board_id, {'label': {'name': 'Urgent <x>', 'color': 'red'}},
                                     headers=auth, as_json=True)
        assert status == 200 and json.loads(body) == urgent, body
        # Negative: not a board admin (a Worker, a non-member), a color not of
        # the palette, a label of no board, and a non-member's card change.
        assert request('POST', '/b/%s/labels' % board_id, {'name': 'W', 'color': 'red'}, cookie=worker)[0] == 403
        assert b'data-pop="create-label"' not in request('GET', '%s/%s' % (route, card_id), cookie=worker)[2]
        assert request('POST', '/b/%s/labels' % board_id, {'name': 'S', 'color': 'red'}, cookie=stranger)[0] == 403
        assert request('POST', '/b/%s/labels' % board_id, {'name': 'C', 'color': 'chartreuse'}, cookie=owner)[0] == 400
        assert request('POST', '%s/labels/no-such-label' % card_path, {}, cookie=owner)[0] == 400
        assert request('POST', '%s/labels/%s' % (card_path, urgent), {}, cookie=stranger)[0] == 403
        popup = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert popup.count(b'js-select-label') == 1 and card_doc()['labelIds'] == [], 'no label was added'

        # Dates (_cardsec_date.pug): a "+" for each date the board uses, the
        # date picker, and a set or a cleared date with its a-<field> activity.
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        for kind in ['received', 'start', 'due', 'end']:
            assert ('class="card-label add-label js-%s-date"' % kind).encode() in page, kind
        assert b'data-pop="edit-date"' in page and b'selected-calendar-picker' in page
        dates = card_path + '/dates/'
        status, _, page, _ = request('POST', dates + 'due', {'at': '2099-12-31T17:00:00.000Z', 'delete': ''}, cookie=owner)
        assert status == 200 and b'js-edit-date card-date due-date' in page and b'2099-12-31 17:00' in page
        assert b'data-date="2099-12-31T17:00:00' in page
        # The minicard shows it, and opens the date picker for whoever may set it.
        board_page = request('GET', route, cookie=owner)[2]
        assert b'minicard-date minicard-date-due date due-date js-edit-date js-due-date' in board_page
        assert b'data-pop="edit-date"' in board_page, 'the date picker without an opened card'
        worker_page = request('GET', route, cookie=worker)[2]
        assert b'<span class="badge minicard-date minicard-date-due' in worker_page and b'js-due-date' not in worker_page
        assert request('PUT', '/api/boards/%s/cardSettings' % board_id, {'allowsDueDateOnMinicard': False}, headers=auth,
                       as_json=True)[0] == 200
        assert b'minicard-date-due' not in request('GET', route, cookie=owner)[2], 'negative: not where the board hides it'
        assert request('PUT', '/api/boards/%s/cardSettings' % board_id, {'allowsDueDateOnMinicard': True}, headers=auth,
                       as_json=True)[0] == 200
        status, _, page, _ = request('POST', dates + 'due', {'at': '', 'delete': '1'}, cookie=owner)
        assert status == 200 and b'js-due-date' in page and b'js-edit-date card-date due-date' not in page and b'2099-12-31' not in page
        # Negative: a date that is not one, a year of five digits, a kind that
        # is not a date, a Worker, a non-member, a date the board does not use.
        assert request('POST', dates + 'due', {'at': 'tomorrow'}, cookie=owner)[0] == 400
        assert request('POST', dates + 'due', {'at': '12345-01-01T00:00:00.000Z'}, cookie=owner)[0] == 400
        assert request('POST', dates + 'title', {'at': '2099-12-31T17:00:00.000Z'}, cookie=owner)[0] == 404
        assert request('POST', dates + 'start', {'at': '2099-12-31T17:00:00.000Z'}, cookie=worker)[0] == 403
        assert b'data-pop="edit-date"' not in request('GET', '%s/%s' % (route, card_id), cookie=worker)[2]
        assert request('POST', dates + 'start', {'at': '2099-12-31T17:00:00.000Z'}, cookie=stranger)[0] == 403
        assert request('PUT', '/api/boards/%s/cardSettings' % board_id, {'allowsEndDate': False}, headers=auth,
                       as_json=True)[0] == 200
        assert request('POST', dates + 'end', {'at': '2099-12-31T17:00:00.000Z'}, cookie=owner)[0] == 403
        assert b'card-details-item-end' not in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert request('PUT', '/api/boards/%s/cardSettings' % board_id, {'allowsEndDate': True}, headers=auth,
                       as_json=True)[0] == 200
        assert b'card-date' not in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2], 'no date was set'

        # Swimlanes (swimlaneHeader.jade): the "+" opens swimlaneAddPopup, a
        # swimlane below or above the chosen one, and the caret folds one for
        # this user only (setSwimlaneCollapsedState).
        def lane_titles():
            return [l['title'] for l in json.loads(request('GET', '/api/boards/%s/swimlanes' % board_id, headers=auth)[2])]
        page = request('GET', route, cookie=owner)[2]
        assert b'js-open-add-swimlane-menu' in page and b'data-pop="add-swimlane"' in page and b'js-collapse-swimlane' in page
        first = lane_titles()[0]
        assert request('POST', '/b/%s/swimlanes' % board_id, {'title': 'Below', 'after': lane, 'placement': 'below'},
                       cookie=owner)[0] == 200
        assert request('POST', '/b/%s/swimlanes' % board_id, {'title': 'Above', 'after': lane, 'placement': 'above'},
                       cookie=owner)[0] == 200
        assert lane_titles() == ['Above', first, 'Below'], lane_titles()
        # Negative: a non-member, an empty title, a swimlane of no board.
        assert request('POST', '/b/%s/swimlanes' % board_id, {'title': 'S', 'after': lane}, cookie=stranger)[0] == 403
        assert request('POST', '/b/%s/swimlanes' % board_id, {'title': ' ', 'after': lane}, cookie=owner)[0] == 400
        assert request('POST', '/b/%s/swimlanes' % board_id, {'title': 'L', 'after': 'no-such-lane'}, cookie=owner)[0] == 404
        assert b'js-open-add-swimlane-menu' not in request('GET', route, cookie=commenter)[2]
        assert lane_titles() == ['Above', first, 'Below']
        status, _, body, _ = request('POST', '/_methods/setSwimlaneCollapsedState', [board_id, lane, True],
                                     cookie=owner, as_json=True)
        assert status == 200, body
        page = request('GET', route, cookie=owner)[2]
        assert ('class="swimlane swimlane-collapsed" data-swimlane="%s"' % lane).encode() in page
        assert ('id="swimlane-%s"' % lane).encode() not in page
        assert ('id="swimlane-%s"' % lane).encode() in request('GET', route, cookie=commenter)[2], 'folded for its user only'
        # Negative: a key that is not an id, a board the user cannot read, the wrong types.
        assert request('POST', '/_methods/setSwimlaneCollapsedState', [board_id, 'a"b', True], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setSwimlaneCollapsedState', [board_id, lane, True], cookie=stranger, as_json=True)[0] == 403
        assert request('POST', '/_methods/setSwimlaneCollapsedState', [board_id, lane, 'yes'], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setSwimlaneCollapsedState', [board_id, lane, False], cookie=owner, as_json=True)[0] == 200
        assert ('id="swimlane-%s"' % lane).encode() in request('GET', route, cookie=owner)[2], 'unfolded again'

        # Custom fields (_cardsec_customFields.pug): a field created from the
        # card's picker, put on the card, its value saved for its type, and
        # taken off again - with the REST API's field policy.
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'js-open-custom-fields-settings' in page and b'data-pop="create-custom-field"' in page
        assert request('POST', '/b/%s/custom-fields' % board_id, {'name': 'Budget', 'type': 'currency', 'card': card_id},
                       cookie=owner)[0] == 200
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        field_id = re.search(rb'/custom-fields/([^/"]+)/toggle"', page).group(1).decode()
        fields = card_path + '/custom-fields/' + field_id
        assert request('POST', fields + '/toggle', {}, cookie=owner)[0] == 200
        status, _, page, _ = request('POST', fields, {'value': '123,45'}, cookie=owner)
        assert status == 200 and b'card-details-item-customfield' in page and b'>123.45<' in page, page[-400:]
        # Negative: a value that is no number, a field of no board, a
        # non-member, a type that is not one, an empty name.
        assert request('POST', fields, {'value': '1.2.3'}, cookie=owner)[0] == 400
        assert request('POST', card_path + '/custom-fields/no-such-field', {'value': '1'}, cookie=owner)[0] == 404
        assert request('POST', fields, {'value': '9'}, cookie=stranger)[0] == 403
        assert request('POST', '/b/%s/custom-fields' % board_id, {'name': 'X', 'type': 'script'}, cookie=owner)[0] == 400
        assert request('POST', '/b/%s/custom-fields' % board_id, {'name': ' ', 'type': 'text'}, cookie=owner)[0] == 400
        assert request('POST', '/b/%s/custom-fields' % board_id, {'name': 'S', 'type': 'text'}, cookie=stranger)[0] == 403
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'>123.45<' in page and page.count(b'js-select-field') == 1, 'nothing else was written'
        # The Filter sidebar's Advanced Filter (src/wladvf.pas): by the field's
        # name; one that does not parse keeps the last that did (?last=).
        from urllib.parse import quote
        shown = lambda q: ('data-card-id="%s"' % card_id).encode() in request('GET', route + '?' + q, cookie=owner)[2]
        assert shown('advanced=' + quote('Budget > 100')) and not shown('advanced=' + quote('Budget < 100'))
        assert shown('advanced=' + quote('Budget == 123.45')) and not shown('advanced=' + quote('not Budget == 123.45'))
        page = request('GET', route + '?advanced=' + quote('Budget <') + '&last=' + quote('Budget < 100'), cookie=owner)[2]
        assert ('data-card-id="%s"' % card_id).encode() not in page and b'data-applied="Budget &lt; 100"' in page
        assert b'class="js-field-advanced-filter" type="text" value="Budget &lt;"' in page, 'the typed one stays in the field'
        # Negative: no field of that name, a regex that does not compile, text
        # that is SQL - none filters, and none reaches the database as SQL.
        for bad in ("Nope == 1", "Budget == /(/", "Budget == x' OR 1=1 --", "' OR 1=1 --"):
            page = request('GET', route + '?advanced=' + quote(bad), cookie=owner)[2]
            assert ('data-card-id="%s"' % card_id).encode() in page and b'data-applied=""' in page, bad
        assert request('POST', fields + '/toggle', {}, cookie=owner)[0] == 200
        assert b'card-details-item-customfield' not in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        # The layout, the user's own (toggleCustomFieldsGrid).
        assert request('POST', '/_methods/toggleCustomFieldsGrid', [], cookie=owner, as_json=True)[0] == 200
        assert request('POST', '/_methods/toggleCustomFieldsGrid', [], as_json=True)[0] == 401

        # Attachments (_cardsec_attachments.pug): a file uploaded onto the card,
        # served by WeKan's file route - a raster image inline, anything else
        # as a download with nosniff - and deleted.
        def upload(name, mime, content, cookie):
            boundary = 'welitetestboundary'
            body = ('--%s\r\nContent-Disposition: form-data; name="file"; filename="%s"\r\nContent-Type: %s\r\n\r\n'
                    % (boundary, name, mime)).encode() + content + ('\r\n--%s--\r\n' % boundary).encode()
            return request('POST', card_path + '/attachments', body, cookie=cookie,
                           headers={'Content-Type': 'multipart/form-data; boundary=' + boundary})
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'js-add-attachment' in page and b'data-pop="card-attachments"' in page and b'id="pdf-viewer"' in page
        png = bytes.fromhex('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
                            '1f15c4890000000d49444154789c6360000000000500010d0a2db40000000049454e44ae426082')
        status, _, page, _ = upload('dot.png', 'image/png', png, owner)
        assert status == 200 and b'attachment-name">dot.png<' in page, page[-300:]
        att = re.search(rb'data-attachment="([^"]+)"', page).group(1).decode()
        status, headers, body, _ = request('GET', '/cdn/storage/attachments/%s/original/dot.png' % att, cookie=owner)
        assert status == 200 and body == png and headers.get('Content-Type') == 'image/png', headers
        assert headers.get('Content-Disposition', '').startswith('inline') and headers.get('X-Content-Type-Options') == 'nosniff'
        status, headers, body, _ = request('GET', '/cdn/storage/attachments/%s/original/dot.png?download=true' % att, cookie=owner)
        assert status == 200 and headers.get('Content-Disposition', '').startswith('attachment'), headers
        status, _, page, _ = upload('page.html', 'text/html', b'<script>alert(1)</script>', owner)
        html_att = [a for a in re.findall(rb'data-attachment="([^"]+)"', page) if a.decode() != att][0].decode()
        status, headers, body, _ = request('GET', '/cdn/storage/attachments/%s' % html_att, cookie=owner)
        assert status == 200 and headers.get('Content-Type') == 'application/octet-stream', 'negative: HTML is never shown'
        assert headers.get('Content-Disposition', '').startswith('attachment') and headers.get('X-Content-Type-Options') == 'nosniff'
        # An SVG is an image again (svgResponse.js): stored sanitized, served
        # sanitized again, inline, under a policy that lets nothing run or load.
        known = lambda page: [a.decode() for a in re.findall(rb'data-attachment="([^"]+)"', page)]
        evil = (b'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4" onload="window.ran=1">'
                b'<script>window.ran=2</script><rect width="4" height="4" fill="#2b6cb0"/></svg>')
        before = known(request('GET', '%s/%s' % (route, card_id), cookie=owner)[2])
        status, _, page, _ = upload('evil.svg', 'image/svg+xml', evil, owner)
        assert status == 200, page[-300:]
        svg_att = [a for a in known(page) if a not in before][0]
        for query in ('', '?download=true'):
            status, headers, body, _ = request('GET', '/cdn/storage/attachments/%s%s' % (svg_att, query), cookie=owner)
            assert status == 200 and headers.get('Content-Type') == 'image/svg+xml', headers
            assert "default-src 'none'" in headers.get('Content-Security-Policy', '') and 'sandbox' in headers['Content-Security-Policy']
            assert b'<rect width="4" height="4" fill="#2b6cb0"></rect>' in body and b'script' not in body and b'onload' not in body
        assert request('GET', '/cdn/storage/attachments/%s' % svg_att, cookie=owner)[1]['Content-Disposition'] == 'inline'
        assert ('data-pop="attachment-actions-%s"' % svg_att).encode() in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2], \
            'an image: a cover and a background'
        stored = [f for f in data.glob('**/attachme/**/*.bin') if b'#2b6cb0' in f.read_bytes()]
        assert stored and all(b'script' not in f.read_bytes() for f in stored), 'stored sanitized'
        # Negative: an SVG that is not well-formed is only downloaded, never shown.
        before = known(page)
        page = upload('broken.svg', 'image/svg+xml', b'<svg xmlns="http://www.w3.org/2000/svg"><g><script>x()</script></svg>', owner)[2]
        broken = [a for a in known(page) if a not in before][0]
        status, headers, body, _ = request('GET', '/cdn/storage/attachments/%s' % broken, cookie=owner)
        assert headers.get('Content-Type') == 'application/octet-stream' and headers['Content-Disposition'].startswith('attachment')
        assert ('data-pop="attachment-actions-%s"' % broken).encode() not in page, 'no image'
        for a in (svg_att, broken):
            assert request('POST', '%s/attachments/%s/delete' % (card_path, a), {}, cookie=owner)[0] == 200
        # Negative: no file to a non-member, nor without the cookie; no upload by
        # Comment only or a non-member; no delete by a non-member.
        assert request('GET', '/cdn/storage/attachments/%s' % att, cookie=stranger)[0] == 404
        assert request('GET', '/cdn/storage/attachments/%s' % att)[0] == 404
        assert upload('x.txt', 'text/plain', b'x', commenter)[0] == 403
        assert upload('x.txt', 'text/plain', b'x', stranger)[0] == 403
        assert request('POST', card_path + '/attachments', {'file': 'x'}, cookie=owner)[0] == 400, 'no file, no upload'
        assert request('POST', '%s/attachments/%s/delete' % (card_path, att), {}, cookie=stranger)[0] == 403
        assert request('POST', '%s/attachments/no-such/delete' % card_path, {}, cookie=owner)[0] == 404
        # attachmentActionsPopup: an image as the card's cover and the board's
        # background, and off again; nothing else is either.
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert ('data-pop="attachment-actions-%s"' % att).encode() in page and b'js-add-background-image' in page
        assert ('data-pop="attachment-actions-%s"' % html_att).encode() not in page, 'only an image'
        cover_img = ('<div class="minicard-cover"><img src="/cdn/storage/attachments/%s"' % att).encode()
        background = ('style="background-image: url(/cdn/storage/attachments/%s); background-size: cover;"' % att).encode()
        status, _, page, _ = request('POST', '%s/attachments/%s/cover' % (card_path, att), {}, cookie=owner)
        assert status == 200 and cover_img in page and b'js-remove-cover' in page
        assert request('POST', '%s/attachments/%s/cover' % (card_path, att), {}, cookie=owner)[0] == 200
        assert cover_img not in request('GET', route, cookie=owner)[2], 'the same image again takes it off'
        status, _, page, _ = request('POST', '%s/attachments/%s/background' % (card_path, att), {}, cookie=owner)
        assert status == 200 and background in page and b'js-remove-background-image' in page
        assert background in request('GET', route, cookie=worker)[2], "the board's, for every member"
        # Negative: no HTML file as either, no background by a member who is
        # not an admin, nothing by a non-member, and no attachment of another card.
        assert request('POST', '%s/attachments/%s/cover' % (card_path, html_att), {}, cookie=owner)[0] == 400
        assert request('POST', '%s/attachments/%s/background' % (card_path, html_att), {}, cookie=owner)[0] == 400
        assert request('POST', '%s/attachments/%s/background' % (card_path, att), {}, cookie=worker)[0] == 403
        assert b'js-add-background-image' not in request('GET', '%s/%s' % (route, card_id), cookie=worker)[2]
        assert request('POST', '%s/attachments/%s/cover' % (card_path, att), {}, cookie=stranger)[0] == 403
        assert request('POST', '/b/%s/cards/%s/attachments/%s/cover' % (board_id, 'other-card', att), {}, cookie=owner)[0] == 404
        assert background in request('GET', route, cookie=owner)[2]
        assert request('POST', '%s/attachments/%s/background' % (card_path, att), {}, cookie=owner)[0] == 200
        assert background not in request('GET', route, cookie=owner)[2]
        assert request('POST', '%s/attachments/%s/background' % (card_path, att), {}, cookie=owner)[0] == 200
        assert request('POST', '%s/attachments/%s/cover' % (card_path, att), {}, cookie=owner)[0] == 200

        for a in (att, html_att):
            assert request('POST', '%s/attachments/%s/delete' % (card_path, a), {}, cookie=owner)[0] == 200
        assert b'minicard-cover' not in request('GET', route, cookie=owner)[2] and b'background-image' not in \
            request('GET', route, cookie=owner)[2], 'a deleted image is neither'
        assert b'class="attachment-name"' not in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert request('GET', '/cdn/storage/attachments/%s' % att, cookie=owner)[0] == 404

        # The card's menu (cardDetailsActionsPopup): move to another list of the
        # board, copy, the other board's places, archive - and the negatives.
        second_list = json.loads(request('POST', '/api/boards/%s/lists' % board_id, {'title': 'Second', 'swimlaneId': lane}, headers=auth,
                                         as_json=True)[2])['_id']
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'js-open-card-details-menu' in page and b'data-pop="card-actions"' in page and b'card-details-list-picker' in page
        status, _, page, _ = request('POST', card_path + '/move-to', {'boardId': board_id, 'swimlaneId': lane,
                                                                      'listId': second_list}, cookie=owner)
        assert status == 200, page[-400:]
        assert json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, second_list), headers=auth)[2])[0]['_id'] == card_id
        # Negative: a list of no board, another board, a non-member, Comment only.
        assert request('POST', card_path + '/move-to', {'listId': 'no-such-list'}, cookie=owner)[0] == 400
        assert request('POST', card_path + '/move-to', {'boardId': 'other', 'listId': list_id}, cookie=owner)[0] == 400
        assert request('POST', card_path + '/move-to', {'listId': list_id}, cookie=stranger)[0] == 403
        assert request('POST', card_path + '/move-to', {'listId': list_id}, cookie=commenter)[0] == 403
        assert request('POST', card_path + '/move-to', {'listId': list_id, 'swimlaneId': lane}, cookie=owner)[0] == 200
        status, _, page, _ = request('POST', card_path + '/copy-to', {'boardId': board_id, 'swimlaneId': lane,
                                                                      'listId': second_list, 'title': 'The copy'}, cookie=owner)
        assert status == 200
        copies = json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, second_list), headers=auth)[2])
        assert [c['title'] for c in copies] == ['The copy'], copies
        assert request('POST', card_path + '/copy-to', {'swimlaneId': lane, 'listId': second_list}, cookie=stranger)[0] == 403
        status, _, body, _ = request('GET', '/b/%s/places' % board_id, cookie=owner)
        assert status == 200 and second_list in [l['_id'] for l in json.loads(body)['lists']]
        assert request('GET', '/b/%s/places' % board_id, cookie=stranger)[0] == 403
        copy_path = '/b/%s/cards/%s' % (board_id, copies[0]['_id'])
        assert request('POST', copy_path + '/archive', {}, cookie=stranger)[0] == 403
        status, _, page, _ = request('POST', copy_path + '/archive', {}, cookie=owner)
        assert status == 200 and ('data-card-id="%s"' % copies[0]['_id']).encode() not in page
        assert json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, second_list), headers=auth)[2]) == []
        assert request('POST', copy_path + '/archive', {}, cookie=owner)[0] == 404, 'an archived card is not archived again'

        # The board's header and sidebar: rename (its admin), star, the
        # sidebar's Archive and restore, and the archived boards.
        page = request('GET', route, cookie=owner)[2]
        assert b'js-edit-board-title' in page and b'data-pop="board-title"' in page and b'js-star-board' in page
        assert b'js-toggle-page-sidebar' in page and b'js-open-board-menu' in page and b'data-pop="member-menu"' in page
        assert b'js-edit-board-title' not in request('GET', route, cookie=worker)[2], 'only its admin renames the board'
        status, headers, _, _ = request('POST', '/b/%s/title' % board_id, {'title': 'Renamed <Board>'}, cookie=owner)
        assert status == 303 and headers.get('Location', '').startswith('/b/%s/' % board_id), (status, headers)
        assert json.loads(request('GET', '/api/boards/%s' % board_id, headers=auth)[2])['title'] == 'Renamed <Board>'
        assert request('POST', '/b/%s/title' % board_id, {'title': 'W'}, cookie=worker)[0] == 403
        assert request('POST', '/b/%s/title' % board_id, {'title': 'S'}, cookie=stranger)[0] == 403
        assert request('PUT', '/api/boards/%s/title' % board_id, {'title': 'View Board'}, headers=auth, as_json=True)[0] == 200
        assert json.loads(request('GET', '/api/boards/%s' % board_id, headers=auth)[2])['title'] == 'View Board'
        status, _, body, _ = request('POST', '/_methods/toggleBoardStar', [board_id], cookie=owner, as_json=True)
        assert status == 200 and b'js-star-board is-active' in request('GET', route, cookie=owner)[2]
        assert request('POST', '/_methods/toggleBoardStar', [board_id], cookie=owner, as_json=True)[0] == 200
        assert b'js-star-board is-active' not in request('GET', route, cookie=owner)[2]
        assert request('POST', '/_methods/toggleBoardStar', [board_id], cookie=stranger, as_json=True)[0] == 404
        # Archive: the card archived earlier is in the sidebar, and comes back.
        page = request('GET', route, cookie=owner)[2]
        assert ('data-kind="cards" data-id="%s"' % copies[0]['_id']).encode() in page
        assert request('POST', '/b/%s/archive/restore' % board_id, {'kind': 'cards', 'id': copies[0]['_id']}, cookie=stranger)[0] == 403
        assert request('POST', '/b/%s/archive/restore' % board_id, {'kind': 'users', 'id': copies[0]['_id']}, cookie=owner)[0] == 404
        assert request('POST', '/b/%s/archive/restore' % board_id, {'kind': 'cards', 'id': copies[0]['_id']}, cookie=owner)[0] == 200
        assert [c['_id'] for c in json.loads(request('GET', '/api/boards/%s/lists/%s/cards' % (board_id, second_list),
                                                     headers=auth)[2])] == [copies[0]['_id']]
        assert request('POST', '/b/%s/archive/restore' % board_id, {'kind': 'cards', 'id': copies[0]['_id']}, cookie=owner)[0] == 404, \
            'a card that is not archived is not restored'
        # The archived boards: a member's, and not a non-member's.
        archived = json.loads(request('POST', '/api/boards', {'title': 'Old Board', 'owner': login['id']}, headers=auth, as_json=True)[2])['_id']
        # The REST API has no board archive route: archived in its database, as WeKan's Archive would.
        for path in data.glob('**/files/db/wekan.db'):
            with sqlite3.connect(path) as con:
                if con.execute("SELECT 1 FROM sqlite_master WHERE name='boards'").fetchone():
                    con.execute('UPDATE boards SET archived=1 WHERE id=?', (archived,))
        assert ('js-board %s archived' % archived).encode() in request('GET', '/allboards/archive', cookie=owner)[2]
        assert ('js-board %s' % archived).encode() not in request('GET', '/allboards/archive', cookie=stranger)[2]
        assert ('js-board %s' % archived).encode() not in request('GET', '/allboards/remaining', cookie=owner)[2]

        # Requested By and Assigned By: Edit when set, Add when empty; free text.
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'card-details-item-requested-by' in page and b'card-details-item-assigned-by' in page
        status, _, page, _ = request('POST', card_path + '/people', {'field': 'requestedBy', 'value': ' Customer <One> '},
                                     cookie=owner)
        assert status == 200 and b'Customer &lt;One&gt;' in page and b'<One>' not in page
        card_page = lambda: request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'<div class="viewer">Customer &lt;One&gt;</div>' in card_page(), 'stored trimmed'
        # Negative: no other field by this form, no Worker, no non-member, and
        # not on a board that does not show it.
        assert request('POST', card_path + '/people', {'field': 'title', 'value': 'X'}, cookie=owner)[0] == 403
        assert request('POST', card_path + '/people', {'field': 'assignedBy', 'value': 'W'}, cookie=worker)[0] == 403
        assert request('POST', card_path + '/people', {'field': 'assignedBy', 'value': 'S'}, cookie=stranger)[0] == 403
        assert request('POST', card_path + '/people', {'field': 'assignedBy', 'value': 'x' * 1001}, cookie=owner)[0] == 400
        status, _, body, _ = request('PUT', '/api/boards/%s/cardSettings' % board_id, {'allowsAssignedBy': False},
                                     headers=auth, as_json=True)
        assert status == 200, body
        assert request('POST', card_path + '/people', {'field': 'assignedBy', 'value': 'Off'}, cookie=owner)[0] == 403
        assert b'card-details-item-assigned-by' not in request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        status, _, body, _ = request('PUT', '/api/boards/%s/cardSettings' % board_id, {'allowsAssignedBy': True},
                                     headers=auth, as_json=True)
        page = card_page()
        assert status == 200, body
        assert card_doc()['title'] == 'Renamed Card' and b'card-details-item-assigned-by' in page
        assert b'>W<' not in page and b'>S<' not in page and b'>Off<' not in page and b'fa-plus' in page

        # The description's editor.
        page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2]
        assert b'data-opens="edit-description"' in page and ('action="%s/description"' % card_path).encode() in page
        status, _, page, _ = request('POST', card_path + '/description', {'description': 'New <b>words</b>'}, cookie=owner)
        assert status == 200 and b'New &lt;b&gt;words&lt;/b&gt;' in page and card_doc()['description'] == 'New <b>words</b>'
        # Negative: a Worker sees it without the editor and cannot change it, nor can a non-member.
        assert b'data-opens="edit-description"' not in request('GET', '%s/%s' % (route, card_id), cookie=worker)[2]
        assert request('POST', card_path + '/description', {'description': 'Worker'}, cookie=worker)[0] == 403
        assert request('POST', card_path + '/description', {'description': 'Stranger'}, cookie=stranger)[0] == 403
        assert card_doc()['description'] == 'New <b>words</b>'

        # The card's vote (cardDetails.jade, WeKan's cards.vote), set in the
        # database as WeKan's vote popup would set it.
        def card_db(sql, *args):
            out = None
            for path in data.glob('**/files/db/wekan.db'):
                with sqlite3.connect(path) as con:
                    if con.execute("SELECT 1 FROM sqlite_master WHERE name='cards'").fetchone():
                        out = con.execute(sql, args).fetchone()
            return out
        vote_of = lambda: json.loads(card_db("SELECT json_extract(extra_json,'$.vote') FROM cards WHERE id=?", card_id)[0])
        card_page = lambda who=owner: request('GET', '%s/%s' % (route, card_id), cookie=who)[2]
        assert b'card-details-group-vote' not in card_page(), 'no vote, no section'
        assert request('POST', card_path + '/vote', {'vote': 'positive'}, cookie=owner)[0] == 403, 'no vote to vote in'
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.vote',json(?)) WHERE id=?",
                json.dumps({'question': 'Ship <it>?', 'public': True, 'positive': [], 'negative': []}), card_id)
        page = card_page()
        assert b'<div class="viewer">Ship &lt;it&gt;?</div>' in page and b'js-show-positive-votes">0<' in page
        assert b'js-vote js-vote-positive"' in page and ('action="%s/vote"' % card_path).encode() in page
        status, _, page, _ = request('POST', card_path + '/vote', {'vote': 'positive'}, cookie=owner)
        assert status == 200 and b'js-vote-positive voted' in page and b'js-show-positive-votes">1<' in page
        assert vote_of()['positive'] == [login['id']] and vote_of()['negative'] == []
        # The other side moves the vote; the same side again takes it back.
        assert request('POST', card_path + '/vote', {'vote': 'negative'}, cookie=owner)[0] == 200
        assert vote_of()['positive'] == [] and vote_of()['negative'] == [login['id']]
        assert b'js-vote-negative voted' in card_page() and b'js-vote-positive voted' not in card_page()
        assert request('POST', card_path + '/vote', {'vote': 'negative'}, cookie=owner)[0] == 200
        assert vote_of()['positive'] == [] and vote_of()['negative'] == [], 'withdrawn'
        # Any member votes, a Worker too, and two votes count as two.
        assert request('POST', card_path + '/vote', {'vote': 'positive'}, cookie=worker)[0] == 200
        assert request('POST', card_path + '/vote', {'vote': 'positive'}, cookie=owner)[0] == 200
        assert len(vote_of()['positive']) == 2 and b'js-show-positive-votes">2<' in card_page()
        # Negative: no other answer, no non-member, and nobody after the end.
        assert request('POST', card_path + '/vote', {'vote': 'maybe'}, cookie=owner)[0] == 400
        assert request('POST', card_path + '/vote', {'vote': 'positive'}, cookie=stranger)[0] == 404
        assert b'card-details-group-vote' not in card_page(stranger)
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.vote.allowNonBoardMembers',json('true')) WHERE id=?", card_id)
        assert request('POST', card_path + '/vote', {'vote': 'negative'}, cookie=stranger)[0] == 404, \
            'a vote open to non-members is still on a board they cannot see'
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.vote.end','2001-01-01T00:00:00.000Z') WHERE id=?", card_id)
        assert request('POST', card_path + '/vote', {'vote': 'negative'}, cookie=owner)[0] == 403
        assert b'js-vote-form' not in card_page() and b'js-show-positive-votes">2<' in card_page(), 'the result stays'
        assert len(vote_of()['positive']) == 2 and vote_of()['negative'] == []
        # A private vote shows the counts without the voters' names to open.
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.vote.public',json('false')) WHERE id=?", card_id)
        assert b'js-show-positive-votes' not in card_page() and b'card-label card-label-green">2<' in card_page()
        # setLanguage (server/models/users.js): a supported language, the user's own.
        assert request('POST', '/_methods/setLanguage', ['la'], cookie=owner, as_json=True)[0] == 200
        assert b'Quaestio suffragii' in card_page() and b'Voting question' in card_page(worker)
        assert request('POST', '/_methods/setLanguage', ['xx-nope'], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setLanguage', [1], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setLanguage', ['fi'], as_json=True)[0] == 401
        assert b'Quaestio suffragii' in card_page()
        # The same with WeKan's own login token in the cookie (a REST login's).
        assert b'Quaestio suffragii' in card_page('meteor_login_token=' + login['token'])
        assert request('POST', '/_methods/setLanguage', ['en'], cookie=owner, as_json=True)[0] == 200
        assert b'Voting question' in card_page()

        # Watching (server/notifications/watch.js): the card, the user's own,
        # and the board's level, the user's own; muted is no watcher at all.
        def board_db(sql, *args):
            out = None
            for path in data.glob('**/files/db/wekan.db'):
                with sqlite3.connect(path) as con:
                    if con.execute("SELECT 1 FROM sqlite_master WHERE name='boards'").fetchone():
                        out = con.execute(sql, args).fetchone()
            return out
        card_watchers = lambda: json.loads(card_db("SELECT COALESCE(json_extract(extra_json,'$.watchers'),'[]') FROM cards WHERE id=?", card_id)[0])
        board_watchers = lambda: json.loads(board_db("SELECT COALESCE(json_extract(settings_json,'$.watchers'),'[]') FROM boards WHERE id=?", board_id)[0])
        page = card_page()
        assert ('class="js-toggle-watch-card" href="%s/watch"' % card_path).encode() in page
        status, _, page, _ = request('POST', card_path + '/watch', {}, cookie=owner)
        assert status == 200 and b'js-toggle-watch-card is-checked' in page and card_watchers() == [login['id']]
        assert request('POST', card_path + '/watch', {}, cookie=worker)[0] == 200
        assert len(card_watchers()) == 2 and b'js-toggle-watch-card is-checked' in card_page(worker)
        assert request('POST', card_path + '/watch', {}, cookie=owner)[0] == 200
        assert card_watchers() == [users['worker']], 'unwatched, the other watcher kept'
        assert b'js-toggle-watch-card is-checked' not in card_page()
        # Negative: no non-member, and an assigned-only member only their own cards.
        assert request('POST', card_path + '/watch', {}, cookie=stranger)[0] == 404
        assert request('POST', '/b/%s/cards/%s/watch' % (board_id, 'nope'), {}, cookie=owner)[0] == 404
        board_db('UPDATE board_members SET isNormalAssignedOnly=1 WHERE boardId=? AND userId=?', board_id, users['commenter'])
        assert request('POST', card_path + '/watch', {}, cookie=commenter)[0] == 404
        board_db('UPDATE board_members SET isNormalAssignedOnly=0 WHERE boardId=? AND userId=?', board_id, users['commenter'])
        assert users['commenter'] not in card_watchers()
        # The board: muted by default, a level by the popup, muted again.
        page = request('GET', route, cookie=owner)[2]
        assert b'js-watch-board' in page and b'data-pop="watch"' in page and b'Muted &#10003;' in page
        status, _, page, _ = request('POST', '/b/%s/watch?level=watching' % board_id, {}, cookie=owner)
        assert status == 200 and b'Watching &#10003;' in page
        assert request('POST', '/b/%s/watch?level=tracking' % board_id, {}, cookie=worker)[0] == 200
        assert request('POST', '/b/%s/watch?level=tracking' % board_id, {}, cookie=owner)[0] == 200
        assert sorted((w['userId'], w['level']) for w in board_watchers()) == \
            sorted([(login['id'], 'tracking'), (users['worker'], 'tracking')]), 'one entry each'
        assert request('POST', '/b/%s/watch?level=muted' % board_id, {}, cookie=owner)[0] == 200
        assert board_watchers() == [{'userId': users['worker'], 'level': 'tracking'}]
        assert b'Muted &#10003;' in request('GET', route, cookie=owner)[2]
        # Negative: no other level, and no non-member.
        assert request('POST', '/b/%s/watch?level=loud' % board_id, {}, cookie=owner)[0] == 400
        assert request('POST', '/b/%s/watch?level=watching' % board_id, {}, cookie=stranger)[0] == 404
        assert board_watchers() == [{'userId': users['worker'], 'level': 'tracking'}]

        # Planning Poker (cardDetails.jade, WeKan's cards.pokerVote), on a board
        # that allows it: the user's card is one card, and no other.
        poker_of = lambda: json.loads(card_db("SELECT COALESCE(json_extract(extra_json,'$.poker'),'{}') FROM cards WHERE id=?", card_id)[0])
        assert b'card-details-group-poker' not in card_page()
        assert request('POST', card_path + '/poker', {'state': 'five'}, cookie=owner)[0] == 403, 'no Planning Poker'
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.poker',json(?)) WHERE id=?",
                json.dumps({'question': 'Size <it>', 'end': {'$date': '2999-01-01T00:00:00.000Z'}}), card_id)
        page = card_page()
        assert b'<div class="viewer">Size &lt;it&gt;</div>' in page and b'js-poker-vote-one-hundred" type="submit" name="state" value="oneHundred">100<' in page
        status, _, page, _ = request('POST', card_path + '/poker', {'state': 'five'}, cookie=owner)
        assert status == 200 and b'js-poker-vote-five poker-voted' in page and poker_of()['five'] == [login['id']]
        assert request('POST', card_path + '/poker', {'state': 'eight'}, cookie=owner)[0] == 200
        assert request('POST', card_path + '/poker', {'state': 'eight'}, cookie=worker)[0] == 200
        assert poker_of()['five'] == [] and sorted(poker_of()['eight']) == sorted([login['id'], users['worker']])
        assert sum(len(v) for v in poker_of().values() if isinstance(v, list)) == 2, 'one card each'
        # Negative: no card outside the deck, no non-member, not after the end,
        # and not on a board that turned Planning Poker off.
        assert request('POST', card_path + '/poker', {'state': 'seven'}, cookie=owner)[0] == 400
        assert request('POST', card_path + '/poker', {'state': 'one'}, cookie=stranger)[0] == 404
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.poker.end',json(?)) WHERE id=?",
                json.dumps({'$date': '2001-01-01T00:00:00.000Z'}), card_id)
        assert request('POST', card_path + '/poker', {'state': 'one'}, cookie=owner)[0] == 403
        assert b'js-poker-vote-one' not in card_page() and b'Size &lt;it&gt;' in card_page()
        card_db("UPDATE cards SET extra_json=json_remove(extra_json,'$.poker.end') WHERE id=?", card_id)
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.allowsPoker',json('false')) WHERE id=?", board_id)
        assert b'card-details-group-poker' not in card_page()
        assert request('POST', card_path + '/poker', {'state': 'one'}, cookie=owner)[0] == 403
        board_db("UPDATE boards SET settings_json=json_remove(settings_json,'$.allowsPoker') WHERE id=?", board_id)
        assert poker_of()['one'] == [] and len(poker_of()['eight']) == 2

        # The Filter sidebar (client/lib/filter.js): card text and labels in the
        # board's URL, the board drawn with only the cards they match.
        def shown(query=''):
            page = request('GET', route + query, cookie=owner)[2]
            return set(x.decode() for x in re.findall(rb'class="minicard-wrapper js-minicard" up-href="[^"]*" up-follow '
                                                     rb'up-clickable up-target="\.board-wrapper" data-card="([^"]+)"', page)), page
        everything, page = shown()
        assert card_id in everything and len(everything) >= 2
        assert b'js-open-filter-view"' in page and b'js-filter-active' not in page and b'js-filter-view is-hidden' in page
        assert request('POST', '%s/labels/%s' % (card_path, urgent), {}, cookie=owner)[0] == 200
        status, _, body, _ = request('PUT', '/api/boards/%s/labels' % board_id, {'label': {'name': 'Second', 'color': 'blue'}},
                                     headers=auth, as_json=True)
        assert status == 200, body
        second = json.loads(body)
        second = second.get('_id', second) if isinstance(second, dict) else second
        assert shown('?labels=' + urgent)[0] == {card_id}
        assert shown('?xlabels=' + urgent)[0] == everything - {card_id}, 'exclusion'
        assert card_id not in shown('?labels=__none__')[0]
        assert shown('?labels=%s,__none__' % urgent)[0] == everything
        assert shown('?labels=%s,%s' % (urgent, second))[0] == {card_id}, 'any'
        assert shown('?labels=%s,%s&labelMode=and' % (urgent, second))[0] == set(), 'every one'
        assert shown('?labels=%s&xlabels=%s' % (urgent, urgent))[0] == set(), 'exclusion wins'
        assert request('POST', comments_path, {'comment': 'Zebra quartz'}, cookie=owner)[0] == 200
        found, page = shown('?text=ZEBRA%20Quartz')
        assert found == {card_id}, 'a comment, case-insensitive'
        assert b'js-filter-active' in page and b'js-filter-reset' in page and b'value="ZEBRA Quartz"' in page
        assert ('data-filter-id="%s" data-state="in"' % urgent).encode() in shown('?labels=' + urgent)[1]
        assert ('data-filter-id="%s" data-state="out"' % urgent).encode() in shown('?xlabels=' + urgent)[1]
        # Negative: no label of another board or none at all filters, a quote is
        # text and nothing more, and the filter is the viewer's display only.
        found, page = shown('?labels=nolabel&xlabels=%27')
        assert found == everything and b'js-filter-active' not in page
        assert shown('?text=%27)%20OR%201%3D1%20--')[0] == set()
        assert shown('?text=' + 'x' * 2000)[0] == set()
        assert request('GET', route + '?labels=' + urgent, cookie=stranger)[0] == 404
        assert card_doc()['labelIds'] == [urgent]
        assert request('POST', '%s/labels/%s' % (card_path, urgent), {}, cookie=owner)[0] == 200

        # Sort Cards (cardsSortPopup): a display order of each list's cards by
        # ?sort=, ties in the manual order, and no card's sort changed.
        sort_list = json.loads(request('POST', '/api/boards/%s/lists' % board_id, {'title': 'Sorting', 'swimlaneId': lane},
                                       headers=auth, as_json=True)[2])['_id']
        sorted_ids = {}
        for i, title in enumerate(['Cherry', 'Apple', 'Banana', 'Damson']):
            made = json.loads(request('POST', '/api/boards/%s/lists/%s/cards' % (board_id, sort_list),
                                      {'title': title, 'authorId': login['id'], 'swimlaneId': lane},
                                      headers=auth, as_json=True)[2])
            assert '_id' in made, made
            sorted_ids[title] = made['_id']
            card_db('UPDATE cards SET sort=?, createdAt=? WHERE id=?', float(i), '2030-01-%02dT12:00:00.000Z' % (10 + i), sorted_ids[title])
        card_db("UPDATE cards SET dueAt='2030-01-05T12:00:00.000Z' WHERE id=?", sorted_ids['Cherry'])
        card_db("UPDATE cards SET dueAt='2030-01-03T12:00:00.000Z' WHERE id=?", sorted_ids['Apple'])
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.vote',json(?)) WHERE id=?",
                json.dumps({'positive': ['x', 'y'], 'negative': []}), sorted_ids['Banana'])
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.vote',json(?)) WHERE id=?",
                json.dumps({'positive': ['x'], 'negative': ['y', 'z']}), sorted_ids['Damson'])
        assert request('POST', '/b/%s/cards/%s/labels/%s' % (board_id, sorted_ids['Damson'], second), {}, cookie=owner)[0] == 200
        assert request('POST', '/b/%s/cards/%s/labels/%s' % (board_id, sorted_ids['Apple'], urgent), {}, cookie=owner)[0] == 200
        title_of = {v: k for k, v in sorted_ids.items()}
        def sort_order(query=''):
            page = request('GET', route + query, cookie=owner)[2]
            body = page[page.index(('id="js-list-%s"' % sort_list).encode()):]
            body = body[:body.index(b'class="list js-list"')] if b'class="list js-list"' in body else body
            return ','.join(title_of[x.decode()] for x in re.findall(rb'class="minicard-wrapper js-minicard" up-href="[^"]*" up-follow '
                                                                      rb'up-clickable up-target="\.board-wrapper" data-card="([^"]+)"', body)), page
        manual, page = sort_order()
        assert manual == 'Cherry,Apple,Banana,Damson', manual
        # The board's label order is the one the board shows its labels in.
        shown_labels = [x.decode() for x in re.findall(rb'js-toggle-label-filter" data-filter-id="([^"]+)"', page)]
        label_order = 'Apple,Damson' if shown_labels.index(urgent) < shown_labels.index(second) else 'Damson,Apple'
        label_order += ',Cherry,Banana'
        assert b'js-sort-cards"' in page and b'js-sort-reset' not in page and b'data-pop="cards-sort"' in page
        for query, want in [('due', 'Banana,Damson,Apple,Cherry'), ('title', 'Apple,Banana,Cherry,Damson'),
                            ('created-desc', 'Damson,Banana,Apple,Cherry'), ('created-asc', 'Cherry,Apple,Banana,Damson'),
                            ('votes', 'Banana,Cherry,Apple,Damson'), ('label-order', label_order)]:
            got, page = sort_order('?sort=' + query)
            assert got == want, (query, got, want)
            assert b'js-sort-cards emphasis' in page and b'js-sort-reset' in page
            assert ('class="js-sort-card-order js-sort-%s is-active" href="#" data-sort="%s"' % (query, query)).encode() in page
            assert page.count(b' is-active" href="#" data-sort=') == 1
        # Negative: an order WeKan does not have is no order, markup is no
        # order, and no card's sort changed.
        got, page = sort_order('?sort=sort')
        assert got == manual and b'js-sort-reset' not in page
        assert sort_order('?sort=%22%3E%3Cscript%3E')[0] == manual
        assert [card_db('SELECT sort FROM cards WHERE id=?', sorted_ids[t])[0] for t in ['Cherry', 'Apple', 'Banana', 'Damson']] == [0, 1, 2, 3]

        # #6423: PUT .../cards/:id with a listId moves the card within its board,
        # with WeKan's moveCard activity.
        moved = sorted_ids['Cherry']
        status, _, body, _ = request('PUT', '/api/boards/%s/lists/%s/cards/%s' % (board_id, sort_list, moved),
                                     {'listId': list_id}, headers=auth, as_json=True)
        assert status == 200, body
        assert card_db('SELECT listId FROM cards WHERE id=?', moved)[0] == list_id
        assert card_db("SELECT count(*) FROM activities WHERE cardId=? AND activityType='moveCard'", moved)[0] == 1
        status, _, body, _ = request('PUT', '/api/boards/%s/lists/%s/cards/%s' % (board_id, list_id, moved),
                                     {'listId': sort_list}, headers=auth, as_json=True)
        assert status == 200 and card_db('SELECT listId FROM cards WHERE id=?', moved)[0] == sort_list, body
        # Negative: no list of another board, no other board, and no non-member.
        other = json.loads(request('POST', '/api/boards', {'title': 'Elsewhere', 'owner': login['id']}, headers=auth, as_json=True)[2])['_id']
        other_list = json.loads(request('POST', '/api/boards/%s/lists' % other, {'title': 'There'}, headers=auth, as_json=True)[2])['_id']
        assert request('PUT', '/api/boards/%s/lists/%s/cards/%s' % (board_id, sort_list, moved), {'listId': other_list},
                       headers=auth, as_json=True)[0] == 400
        assert request('PUT', '/api/boards/%s/lists/%s/cards/%s' % (board_id, sort_list, moved), {'listId': other_list, 'boardId': other},
                       headers=auth, as_json=True)[0] == 400
        stranger_login = json.loads(request('POST', '/users/login', {'username': 'stranger', 'password': 'test-password'})[2])
        assert request('PUT', '/api/boards/%s/lists/%s/cards/%s' % (board_id, sort_list, moved), {'listId': list_id},
                       headers={'Authorization': 'Bearer ' + stranger_login['token']}, as_json=True)[0] in (401, 403, 404)
        assert card_db('SELECT listId FROM cards WHERE id=?', moved)[0] == sort_list

        # The sidebar's members (membersWidget): a board admin searches, adds
        # and removes one, with the REST API's own membership checks.
        active = lambda uid: card_db('SELECT isActive FROM board_members WHERE boardId=? AND userId=?', board_id, uid)
        page = request('GET', route, cookie=owner)[2]
        assert b'js-manage-board-members' in page and b'data-pop="add-member"' in page
        assert b'js-manage-board-members' not in request('GET', route, cookie=worker)[2]
        found = json.loads(request('GET', '/b/%s/members/search?q=STRAN' % board_id, cookie=owner)[2])
        assert [u['username'] for u in found] == ['stranger'], found
        assert json.loads(request('GET', '/b/%s/members/search?q=work' % board_id, cookie=owner)[2]) == [], 'already a member'
        assert json.loads(request('GET', '/b/%s/members/search?q=%%25' % board_id, cookie=owner)[2]) == [], 'text, not a pattern'
        assert request('GET', '/b/%s/members/search?q=stran' % board_id, cookie=worker)[0] == 404
        assert request('POST', '/b/%s/members' % board_id, {'userId': users['stranger']}, cookie=worker)[0] == 404
        assert active(users['stranger']) in (None, (0,))
        status, _, page, _ = request('POST', '/b/%s/members' % board_id, {'userId': users['stranger']}, cookie=owner)
        assert status == 200 and active(users['stranger']) == (1,)
        assert ('data-pop="remove-member-%s"' % users['stranger']).encode() in page
        assert ('data-pop="remove-member-%s"' % login['id']).encode() in page and \
            ('class="js-remove-member" href="#" data-user="%s"' % login['id']).encode() not in page, 'not oneself'
        # Negative: a member who is not an admin is offered no removal and
        # removes nobody; nobody who does not exist is added.
        assert b'js-remove-member' not in request('GET', route, cookie=worker)[2]
        assert request('POST', '/b/%s/members/%s/remove' % (board_id, users['stranger']), {}, cookie=worker)[0] == 404
        assert request('POST', '/b/%s/members' % board_id, {'userId': 'nobody'}, cookie=owner)[0] == 404
        status, _, page, _ = request('POST', '/b/%s/members/%s/remove' % (board_id, users['stranger']), {}, cookie=owner)
        assert status == 200 and active(users['stranger']) == (0,)
        assert ('data-user="%s"' % users['stranger']).encode() not in page, 'gone from the sidebar'
        assert request('POST', '/b/%s/members/%s/remove' % (board_id, users['stranger']), {}, cookie=owner)[0] == 404

        # WeKan's viewer (src/wlmd.pas): a Markdown link in a title is a link on
        # the minicard and in the card; HTML in it stays text.
        titled = sorted_ids['Banana']
        titled_path = '/b/%s/cards/%s' % (board_id, titled)
        assert request('POST', titled_path + '/title', {'title': '[Wekan](https://example.invalid/x) <b>no</b>'}, cookie=owner)[0] == 200
        page = request('GET', '%s/%s' % (route, titled), cookie=owner)[2]
        link = b'<a href="https://example.invalid/x" rel="nofollow noopener" target="_blank">Wekan</a> &lt;b&gt;no&lt;/b&gt;'
        assert page.count(link) == 2, 'the minicard and the card'
        assert request('POST', titled_path + '/title', {'title': '[x](javascript:alert(1)) <img src=x onerror=alert(1)>'}, cookie=owner)[0] == 200
        page = request('GET', route, cookie=owner)[2]
        assert b'href="javascript' not in page and b'<img src=x' not in page and b'&lt;img src=x onerror=alert(1)&gt;' in page
        assert request('POST', titled_path + '/title', {'title': 'Banana'}, cookie=owner)[0] == 200

        # #6712: a list folded per user, per swimlane (setListCollapsedState).
        key = '%s:%s' % (sort_list, lane)
        folded = lambda who=owner: ('class="list js-list list-collapsed" id="js-list-%s"' % sort_list).encode() in request('GET', route, cookie=who)[2]
        assert not folded() and b'js-collapse"' in request('GET', route, cookie=owner)[2]
        assert request('POST', '/_methods/setListCollapsedState', [board_id, key, True], cookie=owner, as_json=True)[0] == 200
        assert folded() and not folded(worker), "the owner's, not the worker's"
        assert request('POST', '/_methods/setListCollapsedState', [board_id, key, False], cookie=owner, as_json=True)[0] == 200
        assert not folded()
        # Negative: keys are ids (PrototypeBleed), the board one the user reads.
        for bad in ('__proto__.x', 'a:b:c', 'x"]', ':' + lane, ''):
            assert request('POST', '/_methods/setListCollapsedState', [board_id, bad, True], cookie=owner, as_json=True)[0] == 400, bad
        assert request('POST', '/_methods/setListCollapsedState', [board_id, key, 'yes'], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setListCollapsedState', [board_id, key, True], cookie=stranger, as_json=True)[0] == 403
        assert not folded()

        # Admin Panel / People (people.pug): a site admin edits a user, switches
        # Admin and Active, and makes a user with setCreateUser.
        user_row = lambda uid: card_db('SELECT username,isAdmin,loginDisabled,json_extract(profile_json,\'$.fullname\') FROM users WHERE id=?', uid)
        assert card_db('SELECT isAdmin FROM users WHERE id=?', login['id'])[0] == 1, 'the first account is the admin'
        page = request('GET', '/people', cookie=owner)[2]
        assert b'admin-panel-tabs' in page and b'data-id="people-setting"' in page and b'<td class="username">worker</td>' in page
        assert b'js-go-setting' in page and b'js-go-setting' not in request('GET', '/', cookie=worker)[2]
        assert ('data-pop="edit-user-%s"' % users['worker']).encode() in page
        assert ('class="text-green js-toggle-active-status" data-user-id="%s"' % users['worker']).encode() in page
        status, headers, _, _ = request('POST', '/admin/people/%s/edit' % users['worker'],
                                        {'username': 'worker', 'fullname': 'Renamed <Worker>', 'initials': 'RW',
                                         'email': 'worker@example.invalid', 'isAdmin': 'false', 'loginDisabled': 'false', 'password': ''}, cookie=owner)
        assert status == 303 and headers['Location'] == '/admin/people' and user_row(users['worker'])[3] == 'Renamed <Worker>'
        assert b'Renamed &lt;Worker&gt;' in request('GET', '/people', cookie=owner)[2]
        assert request('POST', '/admin/people/%s' % users['worker'], {'loginDisabled': 'true'}, cookie=owner)[0] == 303
        assert user_row(users['worker'])[2] == 1 and user_row(users['worker'])[3] == 'Renamed <Worker>', 'only Active changed'
        assert request('GET', route, cookie=worker)[0] in (302, 404), 'signed out when deactivated'
        assert request('POST', '/admin/people/%s' % users['worker'], {'loginDisabled': 'false'}, cookie=owner)[0] == 303
        assert user_row(users['worker'])[2] == 0
        worker = cookie_of('worker')
        # A new password signs the user in with it, and out of the old sessions.
        assert request('POST', '/admin/people/%s/edit' % users['silent'], {'username': 'silent', 'fullname': 'S', 'initials': '',
                       'email': '', 'isAdmin': 'false', 'loginDisabled': 'false', 'password': 'New-pass-99'}, cookie=owner)[0] == 303
        assert json.loads(request('POST', '/users/login', {'username': 'silent', 'password': 'New-pass-99'})[2]).get('token')
        assert 'token' not in json.loads(request('POST', '/users/login', {'username': 'silent', 'password': 'test-password'})[2])
        status, _, body, _ = request('POST', '/_methods/setCreateUser', ['Made User', 'made_user', 'MU', 'Made-pass-1', 'false', 'false',
                                     'made@example.invalid', [], [], []], cookie=owner, as_json=True)
        made = json.loads(body).get('result')
        assert status == 200 and made and user_row(made)[0] == 'made_user', body
        assert json.loads(request('POST', '/users/login', {'username': 'made_user', 'password': 'Made-pass-1'})[2]).get('token')
        # Negative: only a site admin, one's own admin and access stay, names
        # are WeKan's, an address and a username are one account's.
        assert request('GET', '/people', cookie=worker)[0] == 404
        assert request('POST', '/admin/people/%s' % login['id'], {'isAdmin': 'false'}, cookie=worker)[0] == 404
        assert request('POST', '/_methods/setCreateUser', ['X', 'x_user', 'X', 'pw-12345', 'false', 'false', 'x@example.invalid', [], [], []],
                       cookie=worker, as_json=True)[0] == 403
        assert request('POST', '/admin/people/%s' % login['id'], {'isAdmin': 'false', 'loginDisabled': 'true'}, cookie=owner)[0] == 303
        assert user_row(login['id'])[1:3] == (1, 0), "one's own"
        status, headers, _, _ = request('POST', '/admin/people/%s/edit' % users['worker'], {'username': 'made_user'}, cookie=owner)
        assert status == 303 and 'error=error-username-taken' in headers['Location'] and user_row(users['worker'])[0] == 'worker'
        status, headers, _, _ = request('POST', '/admin/people/%s/edit' % users['worker'], {'username': 'a b/c'}, cookie=owner)
        assert 'error=error-user-notCreated' in headers['Location']
        status, headers, _, _ = request('POST', '/admin/people/%s/edit' % users['worker'], {'username': 'worker', 'email': 'made@example.invalid'}, cookie=owner)
        assert 'error=error-email-taken' in headers['Location']
        assert request('POST', '/_methods/setCreateUser', ['X', 'made_user', 'X', 'pw-12345', 'false', 'false', 'y@example.invalid', [], [], []],
                       cookie=owner, as_json=True)[0] == 409
        assert request('POST', '/_methods/setCreateUser', ['X', 'y_user', 'X', 'pw-12345', 'yes', 'false', 'y@example.invalid', [], [], []],
                       cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/admin/people/nobody/edit', {'username': 'x'}, cookie=owner)[0] == 404

        # A refused sign-in in the HTML5 view: its own form again, with WeKan's
        # error, the typed username kept as text, the password toggle, no cookie.
        status, _, page, cookies = request('POST', '/sign-in', {'username': 'owner"<x>', 'password': 'wrong'})
        assert status == 403 and b'class="at-error js-login-error"' in page and b'password-toggle-btn' in page
        assert b'value="owner&quot;&lt;x&gt;"' in page and cookie_value(cookies, 'meteor_login_token') is None
        status, _, page, _ = request('POST', '/sign-in', {'username': 'owner', 'password': 'wrong'}, agent=IBROWSE)
        assert b'HTML 3.2' in page, 'the HTML4 view keeps its own form'

        # The HTML5 view's sign-up (signup.pug): WeKan's fields, two visibility
        # buttons, the address kept, signed in by the login cookie.
        page = request('GET', '/sign-up')[2]
        for field in (b'id="at-field-username"', b'id="at-field-email"', b'id="at-field-password"', b'id="at-field-password_again"'):
            assert field in page, field
        assert page.count(b'password-toggle-btn') == 2
        status, headers, _, cookies = request('POST', '/sign-up', {'username': 'html5_user', 'email': 'H5@Example.invalid',
                                                                  'password': 'pw-h5-123', 'confirm': 'pw-h5-123'})
        assert status == 302 and headers['Location'] == '/' and cookie_value(cookies, 'meteor_login_token')
        made = card_db("SELECT id FROM users WHERE username='html5_user'")[0]
        assert card_db('SELECT address FROM user_emails WHERE userId=?', made)[0] == 'h5@example.invalid'
        assert card_db('SELECT isAdmin FROM users WHERE id=?', made)[0] == 0
        # Negative: the form again with the error and what was typed - no
        # second account by a name or an address, no mismatch, no address.
        for form, code, key in [({'username': 'html5_user', 'email': 'x@example.invalid'}, 400, None),
                                ({'username': 'other_h5', 'email': 'h5@example.invalid'}, 409, None),
                                ({'username': 'other_h5', 'email': 'o@example.invalid', 'confirm': 'nope'}, 400, None),
                                ({'username': 'other_h5', 'email': ''}, 400, None)]:
            body = dict({'password': 'pw-h5-123', 'confirm': 'pw-h5-123'}, **form)
            status, _, page, cookies = request('POST', '/sign-up', body)
            assert status == code and b'class="at-error js-signup-error"' in page, (form, status)
            assert ('value="%s"' % form['username']).encode() in page and cookie_value(cookies, 'meteor_login_token') is None
        assert card_db("SELECT count(*) FROM users WHERE username='other_h5'")[0] == 0

        # The card's and the board's activities (activities.jade), in the
        # reader's language, every name escaped.
        assert request('POST', '/b/%s/cards/%s/title' % (board_id, moved), {'title': 'Moved <b>x</b>'}, cookie=owner)[0] == 200
        page = request('GET', '%s/%s' % (route, moved), cookie=owner)[2]
        assert b'data-section="activities"' in page and b'class="activities js-card-activities"' in page
        act = card_db("SELECT id FROM activities WHERE cardId=? AND activityType='moveCard' ORDER BY createdAt LIMIT 1", moved)[0]
        assert ('<div class="activity" data-id="%s">' % act).encode() in page
        assert b'Moved &lt;b&gt;x&lt;/b&gt;' in page and b'Moved <b>x</b>' not in page
        assert b'js-sidebar-activities' in page and b'js-sidebar-activities' not in request('GET', route, cookie=worker)[2], 'for a board admin'
        assert request('POST', '/b/%s/cards/%s/title' % (board_id, moved), {'title': 'Cherry'}, cookie=owner)[0] == 200

        # The minicard's assignees, newest comments and "Mark as complete", as
        # the board's Card Settings show them.
        mini = lambda who=owner: request('GET', route, cookie=who)[2]
        assert b'minicard-comments' not in mini() and b'js-toggle-card-complete' not in mini(), 'off by default'
        card_db('INSERT INTO card_assignees(cardId,userId) VALUES(?,?)', card_id, users['worker'])
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.allowsCommentsOnMinicard',json('true'),"
                 "'$.allowsDueCompleteOnMinicard',json('true')) WHERE id=?", board_id)
        page = mini()
        assert b'<div class="minicard-assignees js-minicard-assignees"><span class="member" title="Renamed &lt;Worker&gt;">RW</span>' in page
        assert b'<span class="minicard-comment-text">Zebra quartz</span>' in page and page.count(b'class="minicard-comment"') >= 3
        toggle = ('class="minicard-complete-toggle js-toggle-card-complete" href="#" data-card="%s" data-complete="true"' % card_id).encode()
        assert toggle in page and toggle not in mini(worker), 'not for a Worker'
        status, _, _, _ = request('POST', card_path + '/complete', {'complete': 'true'}, cookie=owner)
        assert status == 204 and card_db('SELECT dueComplete FROM cards WHERE id=?', card_id)[0] == 1
        assert ('data-card="%s" data-complete="false"' % card_id).encode() in mini()
        # Negative: no non-member, and the assignees follow the board's setting.
        assert request('POST', card_path + '/complete', {'complete': 'false'}, cookie=stranger)[0] == 403
        assert card_db('SELECT dueComplete FROM cards WHERE id=?', card_id)[0] == 1
        assert request('POST', card_path + '/complete', {'complete': 'false'}, cookie=owner)[0] == 204
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.allowsAssigneeOnMinicard',json('false')) WHERE id=?", board_id)
        assert b'minicard-assignees' not in mini()
        board_db("UPDATE boards SET settings_json=json_remove(settings_json,'$.allowsAssigneeOnMinicard','$.allowsCommentsOnMinicard',"
                 "'$.allowsDueCompleteOnMinicard') WHERE id=?", board_id)
        card_db('DELETE FROM card_assignees WHERE cardId=?', card_id)

        # #5729: the user's own same width for every list, and personal widths
        # while the board allows them; a width is 200 to 1000 (#6465).
        call = lambda name, args, who=owner: request('POST', '/_methods/' + name, args, cookie=who, as_json=True)
        styled = lambda w, who=owner: ('id="js-list-%s" data-list="%s" data-swimlane="%s" style="--list-width:%dpx;"'
                                       % (sort_list, sort_list, lane, w)).encode() in request('GET', route, cookie=who)[2]
        assert call('setFixedListWidthEnabled', [board_id, True])[0] == 200 and styled(220), 'the default width'
        assert call('setFixedListWidth', [board_id, 360])[0] == 200 and styled(360) and not styled(360, worker)
        status, _, body, _ = call('setFixedListWidth', [board_id, 150])
        assert status == 400 and json.loads(body)['error'] == 'invalid-width' and styled(360)
        assert call('setFixedListWidth', [board_id, 5000])[0] == 400 and call('setFixedListWidth', [board_id, '300'])[0] == 400
        assert call('setFixedListWidthEnabled', [board_id, False])[0] == 200 and not styled(360)
        assert call('applyListWidthToStorage', [board_id, sort_list, 410, 410])[0] == 200 and not styled(410), 'not allowed yet'
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.allowsPersonalListWidth',json('true')) WHERE id=?", board_id)
        assert styled(410) and not styled(410, worker)
        # Negative: keys are ids and never an object's own (PrototypeBleed), and
        # a board the user reads.
        for key in ('__proto__', 'constructor', 'prototype'):
            assert call('applyListWidthToStorage', [board_id, key, 300, 300])[0] == 400, key
        assert call('applyListWidthToStorage', [board_id, 'x"]', 300, 300])[0] == 400
        assert call('setFixedListWidthEnabled', [board_id, True], stranger)[0] == 403
        board_db("UPDATE boards SET settings_json=json_remove(settings_json,'$.allowsPersonalListWidth') WHERE id=?", board_id)
        assert not styled(410)

        # editProfilePopup and WeKan's setUsername/setEmail: one's own name and
        # initials; username and address for a site admin, or where Admin Panel
        # allows it (off in a store without accountSettings).
        page = request('GET', '/', cookie=worker)[2]
        assert b'class="js-edit-profile"' in page and b'data-pop="edit-profile"' in page
        assert b'class="js-profile-username" type="text" value="worker" readonly' in page, 'not changeable by a member'
        status, headers, _, _ = request('POST', '/profile', {'fullname': 'Worker <Two>', 'initials': 'W2'}, cookie=worker)
        assert status == 303 and user_row(users['worker'])[3] == 'Worker <Two>'
        assert request('POST', '/_methods/setUsername', ['renamed_worker', users['worker']], cookie=worker, as_json=True)[0] == 403
        assert request('POST', '/_methods/setEmail', ['w2@example.invalid', users['worker']], cookie=worker, as_json=True)[0] == 403
        assert request('POST', '/_methods/setUsername', ['taken', login['id']], cookie=worker, as_json=True)[0] == 403, 'nobody else'
        assert user_row(users['worker'])[0] == 'worker'
        assert request('POST', '/_methods/setUsername', ['worker_two', users['worker']], cookie=owner, as_json=True)[0] == 200
        assert user_row(users['worker'])[0] == 'worker_two'
        status, _, body, _ = request('POST', '/_methods/setUsername', ['made_user', users['worker']], cookie=owner, as_json=True)
        assert status == 409 and json.loads(body)['error'] == 'username-already-taken'
        assert request('POST', '/_methods/setUsername', ['a/b', users['worker']], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setEmail', ['made@example.invalid', users['worker']], cookie=owner, as_json=True)[0] == 409
        assert request('POST', '/_methods/setEmail', ['Worker2@Example.invalid', users['worker']], cookie=owner, as_json=True)[0] == 200
        assert card_db('SELECT address,verified FROM user_emails WHERE userId=?', users['worker']) == ('worker2@example.invalid', 0)
        assert request('POST', '/_methods/setUsername', ['worker', users['worker']], cookie=owner, as_json=True)[0] == 200

        # Multi-Selection: a list's cards selected, then archived together with
        # WeKan's archiveSelectedCards - the whole selection checked first.
        page = request('GET', route, cookie=owner)[2]
        assert b'js-multiselection-activate' in page and b'js-multiselection-view is-hidden' in page and b'js-select-cards' in page
        assert b'js-multiselection-activate' not in request('GET', route, cookie=commenter)[2]
        arch = lambda ids, who=owner, board=board_id: request('POST', '/_methods/archiveSelectedCards', [board, ids], cookie=who, as_json=True)
        pair = [sorted_ids['Apple'], sorted_ids['Damson']]
        assert arch(pair, stranger)[0] == 403 and arch(pair + ['nope'])[0] == 400 and arch([])[0] == 400
        assert arch([pair[0], 5])[0] == 400
        assert card_db('SELECT count(*) FROM cards WHERE id IN (?,?) AND archived=0', *pair)[0] == 2, 'nothing archived by a refused selection'
        assert arch(pair + [pair[0]])[0] == 200, 'each card once'
        assert card_db('SELECT count(*) FROM cards WHERE id IN (?,?) AND archived=1', *pair)[0] == 2
        assert card_db("SELECT count(*) FROM activities WHERE activityType='archivedCard' AND cardId IN (?,?)", *pair)[0] == 2
        assert arch(pair)[0] == 400, 'not archived twice'
        for cid in pair:
            assert request('POST', '/b/%s/archive/restore' % board_id, {'kind': 'cards', 'id': cid}, cookie=owner)[0] == 200

        # The board's visibility (boardVisibilityList), by a board admin, and
        # #3249: an instance board read by every signed-in user, edited only
        # by its members, never seen signed out.
        page = request('GET', route, cookie=owner)[2]
        assert b'js-change-visibility' in page and b'data-pop="visibility"' in page and b'fa fa-lock' in page
        assert b'js-change-visibility' not in request('GET', route, cookie=worker)[2]
        visibility = lambda: board_db('SELECT permission FROM boards WHERE id=?', board_id)[0]
        assert request('POST', '/b/%s/visibility' % board_id, {'visibility': 'instance'}, cookie=worker)[0] == 403
        assert request('POST', '/b/%s/visibility' % board_id, {'visibility': 'everyone'}, cookie=owner)[0] == 400
        assert visibility() == 'private'
        outsider = 'meteor_login_token=' + cookie_value(request('POST', '/sign-in', {'username': 'html5_user', 'password': 'pw-h5-123'})[3], 'meteor_login_token')
        assert request('GET', route, cookie=outsider)[0] == 404
        status, headers, _, _ = request('POST', '/b/%s/visibility' % board_id, {'visibility': 'instance'}, cookie=owner)
        assert status == 303 and visibility() == 'instance' and b'fa fa-users' in request('GET', route, cookie=owner)[2]
        assert request('GET', route, cookie=outsider)[0] == 200, 'any signed-in user reads it'
        h5 = json.loads(request('POST', '/users/login', {'username': 'html5_user', 'password': 'pw-h5-123'})[2])
        assert request('POST', '/api/boards/%s/lists/%s/cards' % (board_id, list_id), {'title': 'Not a member', 'authorId': h5['id'],
                       'swimlaneId': lane}, headers={'Authorization': 'Bearer ' + h5['token']}, as_json=True)[0] != 200, 'only members edit it'
        assert request('GET', route)[0] in (302, 404), 'never signed out'
        assert request('POST', '/b/%s/visibility' % board_id, {'visibility': 'private'}, cookie=owner)[0] == 303
        assert visibility() == 'private' and request('GET', route, cookie=outsider)[0] == 404

        # WeKan's password policy (passwordPolicy.js): getPasswordPolicy answers
        # signed out; an enforced minimum refuses a shorter password at sign-up.
        status, _, body, _ = request('POST', '/_methods/getPasswordPolicy', [], as_json=True)
        assert status == 200 and json.loads(body)['result'] == {'minLength': 9, 'enforce': True}, body
        assert b'minlength="9"' in request('GET', '/sign-up')[2]
        status, _, page, _ = request('POST', '/sign-up', {'username': 'short_pw', 'email': 'short@example.invalid',
                                                        'password': 'Eight-88', 'confirm': 'Eight-88'})
        assert status == 400 and b'js-signup-error' in page and card_db("SELECT count(*) FROM users WHERE username='short_pw'")[0] == 0
        status, _, page, _ = request('POST', '/sign-up', {'username': 'short_pw', 'password': 'Eight-88', 'confirm': 'Eight-88'}, agent='Welite-test')
        assert card_db("SELECT count(*) FROM users WHERE username='short_pw'")[0] == 0, 'the HTML4 view refuses it too'
        status, headers, _, _ = request('POST', '/sign-up', {'username': 'nine_pw', 'email': 'nine@example.invalid',
                                                           'password': 'Nine-9999', 'confirm': 'Nine-9999'})
        assert status == 302 and card_db("SELECT count(*) FROM users WHERE username='nine_pw'")[0] == 1, 'exactly long enough'
        assert request('POST', '/sign-up', {'username': 'long_pw', 'email': 'long@example.invalid', 'password': 'x' * 513,
                                            'confirm': 'x' * 513})[0] == 400

        # #5462/#5997: a list's order by WeKan's updateListSort and by the
        # collection's own update - write access only, and it persists.
        list_sort = lambda: card_db('SELECT sort FROM lists WHERE id=?', sort_list)[0]
        before = list_sort()
        status, _, body, _ = call('updateListSort', [sort_list, board_id, {'sort': -999}], commenter)
        assert status == 403 and json.loads(body)['error'] == 'permission-denied'
        status, _, body, _ = call('/lists/update', [{'_id': sort_list}, {'$set': {'sort': -999}}], commenter)
        assert status == 403 and json.loads(body) == {'error': 403, 'reason': 'Access denied'}
        assert list_sort() == before, 'the order is unchanged after refused attempts'
        assert call('updateListSort', [sort_list, board_id, {'sort': -3}])[0] == 200 and list_sort() == -3
        # Negative: no other field, no swimlane of another board, no list of another board.
        status, _, body, _ = call('updateListSort', [sort_list, board_id, {'title': 'x'}])
        assert status == 400 and json.loads(body)['error'] == 'invalid-field'
        assert call('updateListSort', [sort_list, board_id, {'swimlaneId': 'elsewhere'}])[0] == 400
        assert call('updateListSort', [other_list, board_id, {'sort': 1}])[0] == 403
        assert call('updateListSort', [sort_list, board_id, {'sort': before}])[0] == 200

        # #1426 Accounts.verifyEmail: the link verifies the address and signs
        # the account in; a used, unknown or too old token does nothing.
        made_id = card_db("SELECT id FROM users WHERE username='made_user'")[0]
        set_tokens = lambda tokens: card_db("UPDATE users SET services_json=json_set(services_json,'$.email',json(?)) WHERE id=?",
                                            json.dumps({'verificationTokens': tokens}), made_id)
        verified = lambda: card_db('SELECT verified FROM user_emails WHERE userId=?', made_id)[0]
        set_tokens([{'token': 'old-token', 'address': 'made@example.invalid', 'when': '2001-01-01T00:00:00.000Z'},
                    {'token': 'good-token', 'address': 'made@example.invalid', 'when': time.strftime('%Y-%m-%dT%H:%M:%S.000Z', time.gmtime())}])
        assert verified() == 0
        for bad in ('not-a-real-token', 'old-token'):
            status, headers, _, cookies = request('GET', '/verify-email/' + bad)
            assert status == 302 and headers['Location'] == '/sign-in' and cookie_value(cookies, 'meteor_login_token') is None, bad
        assert verified() == 0, 'neither an unknown nor a too old token verifies'
        status, headers, _, cookies = request('GET', '/verify-email/good-token')
        assert status == 302 and headers['Location'] == '/' and cookie_value(cookies, 'meteor_login_token')
        assert verified() == 1
        signed = 'meteor_login_token=' + cookie_value(cookies, 'meteor_login_token')
        home = request('GET', '/', cookie=signed)
        assert b'made_user' in home[2], ('signed in as the account', home[0], home[1].get('Location'))
        left = json.loads(card_db("SELECT json_extract(services_json,'$.email.verificationTokens') FROM users WHERE id=?", made_id)[0])
        assert [t['token'] for t in left] == ['old-token'], 'the used token is gone'
        assert request('GET', '/verify-email/good-token')[1]['Location'] == '/sign-in', 'and cannot be used again'

        # Board invitations (sidebar.jade): accepted or declined from the
        # sidebar; nobody forges one (InviteProfileBleed, #4730).
        invite = lambda uid: card_db("UPDATE users SET profile_json=json_set(profile_json,'$.invitedBoards',json(?)) WHERE id=?",
                                     json.dumps([board_id]), uid)
        invited = lambda uid: board_id in json.loads(card_db("SELECT COALESCE(json_extract(profile_json,'$.invitedBoards'),'[]') FROM users WHERE id=?", uid)[0])
        member_active = lambda uid: card_db('SELECT isActive FROM board_members WHERE boardId=? AND userId=?', board_id, uid)[0]
        invite(users['silent'])
        # Its password was changed in Admin Panel / People above.
        silent = 'meteor_login_token=' + cookie_value(request('POST', '/sign-in', {'username': 'silent', 'password': 'New-pass-99'})[3], 'meteor_login_token')
        assert b'js-member-invite-accept' in request('GET', route, cookie=silent)[2]
        assert b'js-member-invite-accept' not in request('GET', route, cookie=owner)[2]
        acc = call('acceptInvite', [board_id], silent)
        assert json.loads(acc[2]).get('result') is True, acc[:3:2]
        assert not invited(users['silent']) and member_active(users['silent']) == 1
        invite(users['silent'])
        assert json.loads(call('quitBoard', [board_id], silent)[2])['result'] is True
        assert not invited(users['silent']) and member_active(users['silent']) == 0, 'declined'
        # Negative: no invitation, no acceptance; the account is not written
        # by the client; a non-member quits nothing.
        status, _, body, _ = call('/users/update', [{'_id': users['silent']}, {'$addToSet': {'profile.invitedBoards': board_id}}], silent)
        assert status == 403 and json.loads(body) == {'error': 403, 'reason': 'Access denied'} and not invited(users['silent'])
        assert json.loads(call('acceptInvite', [board_id], silent)[2])['result'] is False
        assert member_active(users['silent']) == 0, 'a removed member does not reactivate'
        assert call('quitBoard', [board_id], silent)[0] == 403
        card_db('UPDATE board_members SET isActive=1 WHERE boardId=? AND userId=?', board_id, users['silent'])

        # Notifications (boardNotificationRecipients.js): a comment notifies the
        # board's watchers and those it mentions, active members who watch or
        # track the board, each once; never its author, nobody muted (#6658).
        notes = lambda uid: json.loads(card_db("SELECT COALESCE(json_extract(profile_json,'$.notifications'),'[]') FROM users WHERE id=?", uid)[0])
        comment_on = lambda text, who=owner: request('POST', '/b/%s/cards/%s/comments' % (board_id, card_id), {'comment': text}, cookie=who)
        for uid in (users['worker'], login['id']):
            card_db("UPDATE users SET profile_json=json_set(profile_json,'$.notifications',json('[]')) WHERE id=?", uid)
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.watchers',json(?)) WHERE id=?",
                 json.dumps([{'userId': users['worker'], 'level': 'watching'}]), board_id)
        assert comment_on('Plain words')[0] == 200
        got = notes(users['worker'])
        assert len(got) == 1 and got[0]['read'] is None
        act = card_db('SELECT activityType,json_extract(data_json,\'$.commentId\') FROM activities WHERE id=?', got[0]['activity'])
        assert act[0] == 'addComment' and act[1], 'the addComment activity it points to'
        assert notes(login['id']) == [], 'never the author'
        # A mention reaches a member who tracks the board; a muted one gets nothing.
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.watchers',json(?)) WHERE id=?",
                 json.dumps([{'userId': login['id'], 'level': 'tracking'}]), board_id)
        assert comment_on('@owner look', worker)[0] == 200
        assert len(notes(login['id'])) == 1, 'mentioned and tracking'
        assert len(notes(users['worker'])) == 1, 'the author of the mention, muted now, gets no more'
        # Watching the card itself notifies, the board muted or not.
        assert card_watchers() == [users['worker']]
        assert comment_on('@worker on a card you watch')[0] == 200
        assert len(notes(users['worker'])) == 2
        card_db("UPDATE cards SET extra_json=json_set(extra_json,'$.watchers',json('[]')) WHERE id=?", card_id)
        assert comment_on('@worker and nobody else')[0] == 200
        assert len(notes(users['worker'])) == 2, 'a mention does not opt a muted member back in'
        # The card's other activities notify the same way (activities.js):
        # moved, put on the card - the member it is about takes part (#5833) -
        # and archived; a muted member is told nothing.
        kinds = lambda uid: [card_db('SELECT activityType FROM activities WHERE id=?', n['activity'])[0] for n in notes(uid)]
        card_db("UPDATE users SET profile_json=json_set(profile_json,'$.notifications',json('[]')) WHERE id=?", users['worker'])
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.watchers',json(?)) WHERE id=?",
                 json.dumps([{'userId': users['worker'], 'level': 'watching'}]), board_id)
        assert request('POST', card_path + '/move-to', {'listId': second_list, 'swimlaneId': lane}, cookie=owner)[0] == 200
        assert request('POST', card_path + '/move-to', {'listId': list_id, 'swimlaneId': lane}, cookie=owner)[0] == 200
        assert kinds(users['worker']) == ['moveCard', 'moveCard'], kinds(users['worker'])
        assert notes(login['id']) == [] or 'moveCard' not in kinds(login['id']), 'never the one who moved it'
        card_db('DELETE FROM card_members WHERE cardId=? AND userId=?', card_id, users['worker'])
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.watchers',json(?)) WHERE id=?",
                 json.dumps([{'userId': users['worker'], 'level': 'tracking'}]), board_id)
        assert request('POST', '%s/members/%s' % (card_path, users['worker']), {}, cookie=owner)[0] == 200
        assert kinds(users['worker'])[-1] == 'joinMember', kinds(users['worker'])
        assert request('POST', '%s/members/%s' % (card_path, users['worker']), {}, cookie=owner)[0] == 200
        assert kinds(users['worker'])[-1] == 'unjoinMember', kinds(users['worker'])
        board_db("UPDATE boards SET settings_json=json_remove(settings_json,'$.watchers') WHERE id=?", board_id)
        before = len(notes(users['worker']))
        assert request('POST', '%s/members/%s' % (card_path, users['worker']), {}, cookie=owner)[0] == 200
        assert request('POST', '%s/members/%s' % (card_path, users['worker']), {}, cookie=owner)[0] == 200
        assert len(notes(users['worker'])) == before, 'muted: put on the card and off it, told nothing'
        # Negative: a change that writes no activity notifies nobody.
        board_db("UPDATE boards SET settings_json=json_set(settings_json,'$.watchers',json(?)) WHERE id=?",
                 json.dumps([{'userId': users['worker'], 'level': 'watching'}]), board_id)
        before = len(notes(users['worker']))
        assert request('POST', card_path + '/move-to', {'listId': list_id, 'swimlaneId': lane}, cookie=owner)[0] == 200
        assert len(notes(users['worker'])) == before, 'a move to where it is is no move'
        api = (ROOT / 'src/wlapi.pas').read_text()
        at = api.index('function NotificationsSql(')
        guard = api[at:api.index('function AddViewComment(', at)]
        assert "SharedSettingOn(Db,'disableNotifications')" in guard and 'EXISTS(SELECT 1 FROM activities WHERE id=' in guard
        assert b'"notifications":[' in request('GET', '/api/user', cookie=owner)[2]
        board_db("UPDATE boards SET settings_json=json_remove(settings_json,'$.watchers') WHERE id=?", board_id)

        # #6704: the comment editor's @ mention menu is drawn from the board's
        # active members, carried as JSON on the textarea - escaped, so a full
        # name cannot end the attribute; an inactive member is not offered.
        def mentions():
            page = request('GET', '%s/%s' % (route, card_id), cookie=owner)[2].decode()
            found = re.search(r'<textarea class="editor js-new-comment-input"[^>]* data-mentions="([^"]*)"', page)
            assert found, 'the comment editor carries the members'
            return {m['u']: m['f'] for m in json.loads(html.unescape(found.group(1)))}
        card_db("UPDATE users SET profile_json=json_set(profile_json,'$.fullname',?) WHERE id=?", 'Wor"ker <b>&amp;', users['worker'])
        got = mentions()
        assert got['worker'] == 'Wor"ker <b>&amp;' and 'owner' in got, got
        card_db('UPDATE board_members SET isActive=0 WHERE boardId=? AND userId=?', board_id, users['silent'])
        assert 'silent' not in mentions(), 'an inactive member is not offered'
        card_db('UPDATE board_members SET isActive=1 WHERE boardId=? AND userId=?', board_id, users['silent'])
        card_db("UPDATE users SET profile_json=json_remove(profile_json,'$.fullname') WHERE id=?", users['worker'])
        # Negative: the menu writes names as text, never as markup.
        js = (ROOT / 'public/static/welite.js').read_text()
        menu = js[js.index('function mentionUpdate'):js.index("document.addEventListener('input'")]
        assert 'textContent' in menu and 'innerHTML' not in menu and 'insertAdjacentHTML' not in menu

        # The notifications drawer (notificationsDrawer, Weddy's
        # notifications_drawer.go): newest first, the act-* sentence with the
        # board, the actor and the names in bold, the card a link to it.
        title = card_db('SELECT title FROM cards WHERE id=?', card_id)[0]
        for aid, kind, board, at in (('drawer-a1', 'createCard', board_id, '2026-11-26T01:00:00.000Z'),
                                     ('drawer-a2', 'addComment', board_id, '2026-11-26T02:00:00.000Z'),
                                     ('drawer-a3', 'createCard', 'no-such-board', '2026-11-26T03:00:00.000Z'),
                                     ('drawer-a4', 'createBoard', board_id, '2026-11-26T04:00:00.000Z'),
                                     ('drawer-a5', 'noSentenceOfItsOwn<b>', board_id, '2026-11-26T05:00:00.000Z')):
            card_db('INSERT INTO activities(id,activityType,userId,boardId,cardId,createdAt,data_json) VALUES(?,?,?,?,?,?,?)',
                    aid, kind, users['worker'], board, card_id if kind != 'createBoard' else None, at,
                    json.dumps({'cardTitle': 'Shown <i>title</i>'}) if aid == 'drawer-a2' else '{}')
        later = int(time.time() * 1000) + 24 * 3600000
        card_db("UPDATE users SET profile_json=json_set(profile_json,'$.notifications',json(?)) WHERE id=?", json.dumps([
            {'activity': 'drawer-a1', 'read': None}, {'activity': 'drawer-a2', 'read': '2026-11-26T02:30:00.000Z'},
            {'activity': 'drawer-a3', 'read': None}, {'activity': 'drawer-a4', 'read': None, 'showAt': later},
            {'activity': 'drawer-a5', 'read': None}, {'activity': 'drawer-missing', 'read': None}]), login['id'])
        def drawer():
            page = request('GET', route, cookie=owner)[2].decode()
            body = page[page.index('<section id="notifications-drawer"'):page.index('</section>', page.index('<section id="notifications-drawer"'))]
            return body, re.findall(r'<li class="notification([^"]*)" data-activity="([^"]*)"', body)
        body, rows = drawer()
        assert [r[1] for r in rows] == ['drawer-a5', 'drawer-a2', 'drawer-a1'], rows
        assert [r[0] for r in rows] == ['', ' is-read', ''], 'the read one is marked'
        link = '<b><a href="/b/%s/' % board_id
        assert link in body and ('/%s">&quot;%s&quot;</a></b>' % (card_id, title)) in body, body
        assert '&quot;Shown &lt;i&gt;title&lt;/i&gt;&quot;' in body and '<i>title' not in body, 'the activity\'s title, escaped'
        assert 'noSentenceOfItsOwn&lt;b&gt;' in body and 'OfItsOwn<b>' not in body, 'an unknown type shows itself, as text'
        assert '__card__' not in body and '__list__' not in body
        assert 'class="menu-item mark-all-read"' in body and 'class="menu-item delete-all" href="#" data-confirm="' in body
        # #5171: the board's entries in one row when the member groups by board.
        card_db("UPDATE users SET profile_json=json_set(profile_json,'$.notificationDelivery',json(?)) WHERE id=?",
                json.dumps({'tray': {'grouping': 'board'}}), login['id'])
        body, rows = drawer()
        assert '<li class="notification-group" data-key="board:%s">' % board_id in body and '>&#9656; 3 ' in body, body
        assert [r[0] for r in rows] == ['', ' is-read is-group-rest', ' is-group-rest'], rows
        card_db("UPDATE users SET profile_json=json_remove(profile_json,'$.notificationDelivery') WHERE id=?", login['id'])
        # The menu: all read, then none; nobody signed in changes nothing.
        assert request('POST', '/notifications/read-all', {})[0] in (302, 303, 401, 403, 404)
        assert notes(login['id'])[0]['read'] is None, 'nobody signed in marks nothing read'
        assert request('POST', '/notifications/read-all', {}, cookie=owner)[0] == 200
        assert all(n['read'] for n in notes(login['id'])), notes(login['id'])
        assert [r[0] for r in drawer()[1]] == [' is-read'] * 3
        assert request('POST', '/notifications/delete-all', {}, cookie=worker)[0] == 200
        assert len(notes(login['id'])) == 6, "one user's menu leaves another's notifications"
        assert request('POST', '/notifications/delete-all', {}, cookie=owner)[0] == 200
        assert notes(login['id']) == [] and drawer()[1] == []
        card_db("DELETE FROM activities WHERE id LIKE 'drawer-a%'")
        # TrayBleed: the tray's own writes of the user's own entries pass -
        # read at a date, unread, removed - and nothing else does.
        tray = lambda mod, who=owner, uid=None: call('/users/update', [{'_id': uid or login['id']}, mod], who)[0]
        card_db("UPDATE users SET profile_json=json_set(profile_json,'$.notifications',json(?)) WHERE id=?",
                json.dumps([{'activity': 'own-1', 'read': None}, {'activity': 'own-2', 'read': None}]), login['id'])
        assert tray({'$set': {'profile.notifications.0.read': '2026-11-26T10:00:00.000Z'}}) == 200
        assert notes(login['id'])[0]['read'] == '2026-11-26T10:00:00.000Z' and notes(login['id'])[1]['read'] is None
        assert tray({'$set': {'profile.notifications.1.read': {'$date': 1764151200000}}}) == 200
        assert notes(login['id'])[1]['read'].startswith('2025-11-26T10:00:00'), notes(login['id'])
        assert tray({'$set': {'profile.notifications.0.read': None}}) == 200 and notes(login['id'])[0]['read'] is None
        assert tray({'$unset': {'profile.notifications.1.read': 1}}) == 200 and 'read' not in notes(login['id'])[1]
        assert tray({'$pull': {'profile.notifications': {'activity': 'own-1'}}}) == 200
        assert [n['activity'] for n in notes(login['id'])] == ['own-2']
        # Negative: no entry added, rewritten or given another activity, no
        # text as a date, no other user's tray, nothing beside it.
        for mod in ({'$push': {'profile.notifications': {'activity': 'foreign'}}},
                    {'$set': {'profile.notifications': [{'activity': 'foreign'}]}},
                    {'$set': {'profile.notifications.0.activity': 'foreign'}},
                    {'$set': {'profile.notifications.0.read': 'yesterday'}},
                    {'$set': {'profile.notifications.0': {'activity': 'foreign'}}},
                    {'$addToSet': {'profile.notifications': {'activity': 'foreign'}}},
                    {'$set': {'profile.notifications.0.read': None, 'profile.fullname': 'x'}},
                    {'$set': {'profile.notifications.0.read': None}, '$push': {'profile.notifications': {'activity': 'x'}}}):
            assert tray(mod) == 403, mod
        assert tray({'$set': {'profile.notifications.0.read': None}}, uid=users['worker']) == 403
        assert tray({'$set': {'profile.notifications.0.read': None}}, who=None) in (401, 403)
        assert [n['activity'] for n in notes(login['id'])] == ['own-2'], notes(login['id'])
        api = (ROOT / 'src/wlapi.pas').read_text()
        at = api.index('function ViewUsersUpdate(')
        assert "'TrayBleed','ddp:user-notifications'" in api[at:api.index('finally Args.Free;end;', at)], 'an attempt is recorded'

        # WeKan's header: Home, the collapse toggle and the title, then the
        # mobile/desktop toggle; setMobileMode keeps the choice, a boolean.
        page = request('GET', route, cookie=owner)[2]
        at = [page.find(x) for x in (b'class="header-home-link"', b'js-toggle-header-icons-collapsed',
                                     b'class="header-page-title', b'class="mobile-mode-toggle js-header-collapsible-icon"')]
        assert -1 not in at and at == sorted(at), at
        assert b'data-profile=""' in page
        mobile = lambda: card_db("SELECT json_type(profile_json,'$.mobileMode') FROM users WHERE id=?", login['id'])[0]
        assert request('POST', '/_methods/setMobileMode', [True], cookie=owner, as_json=True)[0] == 200 and mobile() == 'true'
        assert b'data-profile="true"' in request('GET', route, cookie=owner)[2]
        assert request('POST', '/_methods/setMobileMode', [False], cookie=owner, as_json=True)[0] == 200 and mobile() == 'false'
        assert b'data-profile="false"' in request('GET', route, cookie=owner)[2]
        # Negative: only a boolean, only signed in, and only one's own.
        for args in (['true'], [1], [None], [], [True, True], [{'$set': 1}]):
            assert request('POST', '/_methods/setMobileMode', args, cookie=owner, as_json=True)[0] == 400, args
        assert request('POST', '/_methods/setMobileMode', [True], as_json=True)[0] == 401
        assert mobile() == 'false'
        assert b'data-profile=""' in request('GET', route, cookie=worker)[2], "another user's choice is theirs"

        # ?ui=html4 switches a modern browser to HTML4, and the cookie keeps it;
        # the login cookie's session is the HTML4 view's session then.
        status, _, page, cookies = request('GET', '/?ui=html4', cookie=owner)
        assert status == 200 and b'HTML 3.2' in page and cookie_value(cookies, 'welite-ui') == 'html4'
        assert b'View Board' in page and ('name="sessionId" value="%s"' % token).encode() in page
        status, _, page, _ = request('GET', '/', cookie=owner + '; welite-ui=html4')
        assert b'HTML 3.2' in page
        # The HTML4 toggle: a POST with the session, into the HTML5 view's cookie.
        # The same browser, now in the HTML4 view (a session belongs to its browser).
        status, headers, _, cookies = request('POST', route + '?ui=html5',
                                              {'nav_view': '1', 'sessionId': token}, cookie='welite-ui=html4')
        assert status == 303 and headers['Location'] == route, (status, headers)
        assert cookie_value(cookies, 'meteor_login_token') == token and cookie_value(cookies, 'welite-ui') == 'html5'
        # Negative: another browser presenting the session gets no login cookie from it.
        status, headers, _, cookies = request('POST', route + '?ui=html5',
                                              {'nav_view': '1', 'sessionId': token}, agent=IBROWSE)
        assert status == 303 and cookie_value(cookies, 'meteor_login_token') is None
        # Negative: a toggle with no valid session sets no login cookie.
        status, headers, _, cookies = request('POST', '/?ui=html5', {'nav_view': '1', 'sessionId': 'f' * 64}, agent=IBROWSE)
        assert status == 303 and cookie_value(cookies, 'meteor_login_token') is None

        # WeKan's mobile view (isMiniScreen): every list of a swimlane a
        # compact row, the current one (welite-list) opened in its own lane.
        page = request('GET', route, cookie=owner + '; welite-mobile=1')[2].decode()
        rows = re.findall(r'<a class="mini-list js-select-list js-list mobile-view" id="js-list-([^"]+)"', page)
        assert list_id in rows and 'class="list-body' not in page, rows
        lane_of = re.search(r'data-list="%s" data-swimlane="([^"]+)"' % re.escape(list_id), page).group(1)
        page = request('GET', route, cookie=owner + '; welite-mobile=1; welite-list=' + quote(list_id + ':' + lane_of))[2].decode()
        assert ('class="list js-list mobile-view" id="js-list-%s"' % list_id) in page and 'class="list-body' in page
        lane = page[page.index('id="swimlane-%s"' % lane_of):]
        lane = lane[:lane.find('class="swimlane ', 10) if lane.find('class="swimlane ', 10) > 0 else len(lane)]
        assert 'mini-list' not in lane, 'only the current list in its lane'
        # Negative: desktop by default, and a current list of no lane is none.
        assert 'mini-list' not in request('GET', route, cookie=owner)[2].decode()
        assert 'class="list-body' not in request('GET', route, cookie=owner + '; welite-mobile=1; welite-list=nope')[2].decode()

        # WeKan's preferredLanguage: no language chosen, the browser's own
        # list (the welite-languages cookie welite.js keeps), with WeKan's
        # aliases (vep is ve-PP); a chosen one wins, and nothing is saved.
        lang = lambda page: re.search(rb'<html lang="([^"]+)"', page).group(1).decode()
        card_db("UPDATE users SET profile_json=json_remove(profile_json,'$.language') WHERE id=?", users['worker'])
        page = request('GET', route, cookie=worker)[2]
        assert b'data-language-source="browser"' in page
        assert lang(request('GET', route, cookie=worker + '; welite-languages=zz-ZZ%2Cvep')[2]) == 've-PP'
        assert lang(request('GET', route, cookie=worker + '; welite-languages=zz-ZZ%2Cfi-FI')[2]) == 'fi'
        assert lang(request('GET', route, cookie=worker, headers={'Accept-Language': 'vep'})[2]) == 've-PP'
        assert card_db("SELECT json_extract(profile_json,'$.language') FROM users WHERE id=?", users['worker'])[0] is None
        # Negative: nothing it does not have, no path, and a chosen language wins.
        assert lang(request('GET', route, cookie=worker + '; welite-languages=..%2F..%2Fetc%2Cxx')[2]) == 'en'
        assert request('POST', '/_methods/setLanguage', ['de'], cookie=worker, as_json=True)[0] == 200
        page = request('GET', route, cookie=worker + '; welite-languages=fi')[2]
        assert lang(page) == 'de' and b'data-language-source' not in page
        assert request('POST', '/_methods/setLanguage', ['en'], cookie=worker, as_json=True)[0] == 200

        # Member Settings' Change Language (changeLanguagePopup): fetched when
        # opened, every installed language, the one now checked.
        assert b'class="js-change-language" href="/language/popup"' in request('GET', '/', cookie=owner)[2]
        popup = request('GET', '/language/popup', cookie=owner)[2].decode()
        tags = re.findall(r'class="js-set-language" href="#" dir="ltr" data-language="([^"]+)"', popup)
        installed = len([f for f in (ROOT / 'i18n/data').glob('*.jsn') if not f.is_symlink()])
        assert len(tags) > 200 and len(tags) == len(set(tags)) and len(tags) <= installed + 5, (len(tags), installed)
        assert popup.startswith('<template class="js-pop-over-template" data-pop="change-language" data-popup="changeLanguagePopup"')
        assert '<li class="active"><a class="js-set-language" href="#" dir="ltr" data-language="en">' in popup
        assert popup.count('fa-check') == 1 and popup.count('(RTL)') >= 5
        assert '<bdi class="language-name">English</bdi>' in popup and '&nbsp;<bdi>Brazil</bdi>' in popup
        assert request('GET', '/language/popup')[1].get('Location') == '/sign-in', 'signed-in only'

        # Member Settings' Change Password (changePasswordPopup): the password
        # now and the new one twice; then every session is signed out, this
        # one too (passwordChangeRequired.js), and only the new one signs in.
        assert b'class="js-change-password" href="/profile/password"' in request('GET', '/', cookie=stranger)[2]
        page = request('GET', '/profile/password', cookie=stranger)[2]
        assert b'id="at-field-current_password"' in page and b'name="newPassword2"' in page and b'minlength="9"' in page
        assert request('GET', '/profile/password')[1].get('Location') == '/sign-in'
        stranger2 = cookie_of('stranger')
        change = lambda old, new, again=None, who=stranger: request('POST', '/profile/password',
            {'oldPassword': old, 'newPassword': new, 'newPassword2': new if again is None else again}, cookie=who)[:2]
        # Negative: the wrong password now, two that differ, one too short.
        for args, key in ((('wrong-password', 'Changed-pass-1'), 'login-refused-bad-password'),
                          (('test-password', 'Changed-pass-1', 'Changed-pass-2'), 'password-mismatch'),
                          (('test-password', 'short1'), 'error-password-policy')):
            status, headers = change(*args)
            assert status == 303 and headers['Location'] == '/profile/password?error=' + key, (status, headers)
        assert b'at least 9 characters' in request('GET', '/profile/password?error=error-password-policy', cookie=stranger)[2]
        assert request('GET', '/', cookie=stranger)[0] == 200 and request('GET', '/', cookie=stranger2)[0] == 200, 'nothing changed'
        # Negative: the form is held to the sign-in limit, five a while.
        api = (ROOT / 'src/wlh5.pas').read_text()
        at = api.index("if Path = '/profile/password' then\n  begin\n    if not (ResolveTenant")
        form = api[at:api.index('ViewSetPassword(', at)]
        assert form.index('ReserveLoginAttempt(') < form.index('AuthenticateAccount('), 'checked within the limit'
        card_db("DELETE FROM _wl_attempt WHERE bucket LIKE 'account:%'")
        for _ in range(5):
            assert change('guess', 'Changed-pass-1')[1]['Location'].endswith('error=login-refused-braked') is False
        assert change('test-password', 'Changed-pass-1')[1]['Location'] == '/profile/password?error=login-refused-braked', \
            'even the right password, once the guesses are spent'
        assert request('GET', '/', cookie=stranger)[0] == 200
        card_db("DELETE FROM _wl_attempt WHERE bucket LIKE 'account:%'")
        status, headers = change('test-password', 'Changed-pass-1')
        assert status == 303 and headers['Location'] == '/sign-in'
        for who in (stranger, stranger2):
            assert request('GET', '/', cookie=who)[1].get('Location') == '/sign-in', 'every session signed out'
        assert 'token' not in json.loads(request('POST', '/users/login', {'username': 'stranger', 'password': 'test-password'})[2])
        card_db("DELETE FROM _wl_attempt WHERE bucket LIKE 'account:%'")
        stranger = 'meteor_login_token=' + json.loads(request('POST', '/users/login',
            {'username': 'stranger', 'password': 'Changed-pass-1'})[2])['token']
        assert request('GET', '/', cookie=stranger)[0] == 200
        # WeKan's setPassword: a site admin's, and it signs that user out too.
        status, _, body, _ = request('POST', '/_methods/setPassword', ['Admin-set-pass-1', users['stranger']], cookie=worker, as_json=True)
        assert status == 403, body
        assert request('POST', '/_methods/setPassword', ['Admin-set-pass-1'], cookie=owner, as_json=True)[0] == 400
        assert request('POST', '/_methods/setPassword', ['short', users['stranger']], cookie=owner, as_json=True)[0] == 400
        assert request('GET', '/', cookie=stranger)[0] == 200, 'a refused setPassword signs nobody out'
        assert request('POST', '/_methods/setPassword', ['Admin-set-pass-1', users['stranger']], cookie=owner, as_json=True)[0] == 200
        assert request('GET', '/', cookie=stranger)[1].get('Location') == '/sign-in'
        card_db("DELETE FROM _wl_attempt WHERE bucket LIKE 'account:%'")
        got = request('POST', '/users/login', {'username': 'stranger', 'password': 'Admin-set-pass-1'})
        assert json.loads(got[2]).get('token'), got[:3]

        # Log Out revokes the cookie's session.
        status, headers, _, cookies = request('POST', '/logout', {}, cookie=owner)
        assert status == 302 and headers['Location'] == '/sign-in'
        assert cookie_value(cookies, 'meteor_login_token') == ''
        status, headers, _, _ = request('GET', '/', cookie=owner)
        assert status == 302 and headers['Location'] == '/sign-in', 'the session is revoked'
        print('PASS: HTML4 and HTML5 views over HTTP (%s SQLite)' % backend)
    finally:
        proc.terminate()
        proc.wait(10)
        log.close()


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='view.', dir=base) as name:
        tmp = Path(name)
        pure_checks(tmp)
        for backend, flags in [('linked', []), ('cli', ['-dWLDB_CLI'])]:
            out = tmp / ('build-' + backend)
            out.mkdir(parents=True, exist_ok=True)
            result = subprocess.run([FPC, *flags, '-B', '-FU' + str(out), '-FE' + str(out), str(ROOT / 'src/wlhttp.lpr')],
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            assert result.returncode == 0, result.stdout
            http_checks(out / 'wlhttp', tmp, backend)


if __name__ == '__main__':
    sys.exit(main())

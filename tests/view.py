"""The HTML4 and HTML5 views on one backend (src/wlview.pas, src/wlh5.pas).

A modern browser gets the HTML5 view - Weddy's markup, which is WeKan's - and a
retro or unknown one the HTML4 view. ?ui=html4|html5 switches and is kept in
the welite-ui cookie. The HTML5 view signs in with WeKan's meteor_login_token
cookie. Linked and CLI SQLite.
"""
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
            assert not _re.search(r'\battachments\s+(?:AS\s+)?[a-z]\w*\s+WHERE', stmt, _re.I), (pas.name, stmt[-200:])
    print('PASS: no aliased attachments beside LiveAttachmentSQL')


def http_checks(server, tmp, backend):
    data = tmp / ('data-' + backend)
    listen = free_port()
    env = dict(os.environ, WELITE_DATA=str(data), WELITE_SHARED='0', WELITE_PORT=str(listen),
               WELITE_SCHEMA=str(ROOT / 'src/schema.sql'), WELITE_DESIGNER=str(ROOT / 'src/designer.sql'),
               WELITE_I18N=str(ROOT / 'i18n'), WELITE_PUBLIC=str(ROOT / 'public'))
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

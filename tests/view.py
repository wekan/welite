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
        if data is not None:
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

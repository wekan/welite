#!/usr/bin/env python3
"""WeKan's Rules on a shared store (src/wlrules.pas), over HTTP.

    FPC=/path/to/fpc FERRETDB=/path/to/ferretdb python3 -I tests/rules.py

WeLite on FerretDB's SQLite file, as tests/wkui/run.sh runs it: rules made
with the Rules page's methods, and cards made with the REST API that start
them. Checked through FerretDB itself, as WeKan would read the board:

- sortList orders a list's cards by name after each new card;
- linkCard links a new card into a list of another board its user may change;
- negative: an action stored with a board its user may not change links
  nothing there, and the attempt is in Admin Panel / Problems (RuleBleed);
- a rule's history row is in the board's hash chain, and undo and redo take
  the rule away and put it back;
- negative: a stranger cannot undo the board's history, nor run its rules'
  methods.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from wire import Client  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FERRET = Path(os.environ['FERRETDB'])


def port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='rules.', dir=base) as name:
        tmp = Path(name)
        build = tmp / 'build'
        build.mkdir()
        r = subprocess.run([os.environ.get('FPC', 'fpc'), '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(build), '-FE' + str(build),
                            str(ROOT / 'src/wlhttp.lpr')], capture_output=True, text=True)
        assert r.returncode == 0, r.stdout[-2000:]
        data = tmp / 'data/local/files/db'
        data.mkdir(parents=True)
        state = tmp / 'state'
        state.mkdir()
        mongo_port, http_port = port(), port()
        mongo_log = (tmp / 'ferret.log').open('w+')
        app_log = (tmp / 'http.log').open('w+')
        ferret = subprocess.Popen([str(FERRET), '--handler=sqlite', '--sqlite-url=' + data.as_uri() + '/', '--state-dir=' + str(state),
                                   '--listen-addr=127.0.0.1:%d' % mongo_port, '--debug-addr=127.0.0.1:%d' % port(), '--log-level=ERROR',
                                   '--telemetry=disable'], stdout=mongo_log, stderr=mongo_log)
        app = None
        try:
            client = Client(mongo_port)
            for _ in range(200):
                try:
                    client.command({'ping': 1})
                    break
                except OSError:
                    assert ferret.poll() is None, 'FerretDB exited'
                    time.sleep(.05)
            # FerretDB knows the collections it made: WeKan makes them at startup.
            for collection in ['boards', 'swimlanes', 'lists', 'cards', 'card_comments', 'checklists', 'checklistItems', 'customFields', 'users',
                               'activities', 'attachments', 'rules', 'triggers', 'actions', 'integrations', 'eventlog', 'changeHistory',
                               'settings']:
                client.command({'create': collection})
            env = dict(os.environ, WELITE_DATA=str(tmp / 'data'), WELITE_SHARED='1', WELITE_PORT=str(http_port),
                       WELITE_SCHEMA=str(ROOT / 'src/schema.sql'), WELITE_DESIGNER=str(ROOT / 'src/designer.sql'),
                       WELITE_PUBLIC=str(ROOT / 'public'), WELITE_I18N=str(ROOT / 'i18n'))
            app = subprocess.Popen([str(build / 'wlhttp')], env=env, cwd=tmp, stdout=app_log, stderr=app_log)

            def request(method, path, data=None, cookie=None, token=None, as_json=False, agent='Mozilla/5.0 Chrome/120.0'):
                con = http.client.HTTPConnection('127.0.0.1', http_port, timeout=20)
                h = {'Host': 'localhost', 'User-Agent': agent}
                if cookie:
                    h['Cookie'] = cookie
                if token:
                    h['Authorization'] = 'Bearer ' + token
                body = None
                if data is not None:
                    if as_json:
                        h['Content-Type'] = 'application/json'
                        body = json.dumps(data)
                    else:
                        h['Content-Type'] = 'application/x-www-form-urlencoded'
                        body = urlencode(data)
                con.request(method, path, body, h)
                resp = con.getresponse()
                result = resp.status, dict(resp.getheaders()), resp.read()
                con.close()
                return result

            for _ in range(200):
                try:
                    request('GET', '/sign-in')
                    break
                except OSError:
                    assert app.poll() is None, 'WeLite exited'
                    time.sleep(.05)
            tokens, cookies, ids = {}, {}, {}
            # The first account is the site admin, who may change every board:
            # the users of these checks are ordinary ones.
            for who in ['admin', 'owner', 'other', 'stranger']:
                status, _, _ = request('POST', '/sign-up', {'username': who, 'password': 'test-password', 'confirm': 'test-password'},
                                       agent='Welite-test')
                assert status == 200, status
                login = json.loads(request('POST', '/users/login', {'username': who, 'password': 'test-password'})[2])
                tokens[who], ids[who] = login['token'], login['id']
                status, headers, _ = request('POST', '/sign-in', {'username': who, 'password': 'test-password'})
                cookie = re.search(r'meteor_login_token=([^;]+)', headers.get('Set-Cookie', ''))
                assert status == 302 and cookie, (status, headers)
                cookies[who] = 'meteor_login_token=' + cookie.group(1)

            def board(who, title, lists):
                b = json.loads(request('POST', '/api/boards', {'title': title, 'owner': ids[who]}, token=tokens[who], as_json=True)[2])
                made = {}
                for list_title in lists:
                    made[list_title] = json.loads(request('POST', '/api/boards/%s/lists' % b['_id'], {'title': list_title},
                                                          token=tokens[who], as_json=True)[2])['_id']
                return b['_id'], b['defaultSwimlaneId'], made

            def call(who, method, *args):
                status, _, body = request('POST', '/_methods/' + method, list(args), cookie=cookies[who], as_json=True)
                return status, json.loads(body)

            def card(who, board_id, list_id, lane, title):
                status, _, body = request('POST', '/api/boards/%s/lists/%s/cards' % (board_id, list_id),
                                          {'title': title, 'authorId': ids[who], 'swimlaneId': lane}, token=tokens[who], as_json=True)
                assert status == 200, body
                return json.loads(body)['_id']

            def find(collection, flt):
                return client.command({'find': collection, 'filter': flt})['cursor']['firstBatch']

            home, lane, lists = board('owner', 'Home', ['Todo', 'Done'])
            away, away_lane, away_lists = board('owner', 'Away', ['Inbox'])
            foreign, _, foreign_lists = board('other', 'Foreign', ['Inbox'])

            # sortList: by name, after each new card.
            status, made = call('owner', 'rules.createRule', home, 'Sort by name',
                                {'activityType': 'createCard', 'listName': 'Todo'},
                                {'actionType': 'sortList', 'listName': '*', 'sortField': 'name'})
            assert status == 200 and made['result']['_id'], made
            for title in ['Cherry', 'apple', 'Banana']:
                card('owner', home, lists['Todo'], lane, title)
            order = [c['title'] for c in sorted(find('cards', {'listId': lists['Todo']}), key=lambda c: c['sort'])]
            assert order == ['apple', 'Banana', 'Cherry'], order
            # Negative: another list is not sorted.
            for title in ['Zulu', 'Alpha']:
                card('owner', home, lists['Done'], lane, title)
            order = [c['title'] for c in sorted(find('cards', {'listId': lists['Done']}), key=lambda c: c['sort'])]
            assert order == ['Zulu', 'Alpha'], order
            print('PASS: sortList orders the list by name')

            # linkCard: into a list of another board the user may change.
            status, made = call('owner', 'rules.createRule', home, 'Link to Away',
                                {'activityType': 'createCard', 'listName': 'Done'},
                                {'actionType': 'linkCard', 'boardId': away, 'listName': 'Inbox', 'swimlaneName': '*'})
            assert status == 200, made
            linked_rule = made['result']['_id']
            source = card('owner', home, lists['Done'], lane, 'Shared work')
            links = find('cards', {'boardId': away, 'linkedId': source})
            assert len(links) == 1 and links[0]['type'] == 'cardType-linkedCard' and links[0]['listId'] == away_lists['Inbox'], links
            print('PASS: linkCard links the card into a board its user may change')

            # Negative: the same action, stored as naming a board the user may
            # not change (rules.createRule refuses it: RuleBleed), links nothing.
            status, refused = call('owner', 'rules.createRule', home, 'Link to Foreign',
                                   {'activityType': 'createCard', 'listName': 'Done'},
                                   {'actionType': 'linkCard', 'boardId': foreign, 'listName': 'Inbox'})
            assert status == 403 and refused['error'] == 'not-authorized', refused
            rule = find('rules', {'_id': linked_rule})[0]
            client.command({'update': 'actions', 'updates': [{'q': {'_id': rule['actionId']}, 'u': {'$set': {'boardId': foreign}}}]})
            source = card('owner', home, lists['Done'], lane, 'Smuggled')
            assert find('cards', {'boardId': foreign, 'linkedId': source}) == []
            events = [e for e in find('eventlog', {}) if e.get('bleed') == 'RuleBleed']
            assert events and any(e.get('source') == 'canary:rule.cross-board-write' for e in events), events
            print('PASS: a stored action naming a foreign board links nothing, and is recorded')

            # History: each rule write one row of the board's hash chain;
            # undo takes a new rule away, redo puts it back.
            rows = find('changeHistory', {'boardId': home, 'entityType': 'rule'})
            assert len(rows) == 2 and all(re.fullmatch('[0-9a-f]{64}', r['integrityHash']) for r in rows), rows
            assert rows[1]['previousHash'] == rows[0]['integrityHash'], rows
            # Negative: the action was changed behind the history's back - undo
            # does not overwrite what it did not write.
            status, conflict = call('owner', 'changeHistory.undoLast', home)
            assert status == 409 and conflict['error'] == 'history-conflict', conflict
            assert len(find('rules', {'_id': linked_rule})) == 1
            client.command({'update': 'actions', 'updates': [{'q': {'_id': rule['actionId']}, 'u': {'$set': {'boardId': away}}}]})
            status, undone = call('owner', 'changeHistory.undoLast', home)
            assert status == 200 and undone['result']['undone'] is True, undone
            assert find('rules', {'_id': linked_rule}) == []
            status, redone = call('owner', 'changeHistory.redoLast', home)
            assert status == 200 and redone['result']['redone'] is True, redone
            assert len(find('rules', {'_id': linked_rule})) == 1
            # Negative: a stranger may not undo the board's history, nor make its rules.
            status, denied = call('stranger', 'changeHistory.undoLast', home)
            assert status == 403 and denied['error'] == 'not-authorized', denied
            status, denied = call('stranger', 'rules.createRule', home, 'Mine', {'activityType': 'createCard'}, {'actionType': 'archive'})
            assert status == 403 and denied['error'] == 'not-authorized', denied
            assert len(find('rules', {'boardId': home})) == 2
            print('PASS: rule history undo and redo, and their refusals')
        finally:
            for proc in (app, ferret):
                if proc is not None and proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        proc.kill()
            app_log.seek(0)
            log = app_log.read()
            if 'exception' in log.lower():
                print(log[-2000:])


if __name__ == '__main__':
    sys.exit(main())

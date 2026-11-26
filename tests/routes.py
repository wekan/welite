"""WeKan's URL routes in WeLite (src/wlroutes.pas), linked and CLI SQLite.

A board is /b/:id/:slug and a card /b/:boardId/:slug/:cardId, as in WeKan's
config/router.js; registration is /sign-up. The slug is not checked, as in
WeKan. WeLite's own links use these routes, and its former page routes
(/board?id=, /board/card?id=&card=, /register) still open the same pages.
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


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


def compile_server(out, flags):
    out.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([FPC, *flags, '-B', '-FU' + str(out), '-FE' + str(out), str(ROOT / 'src/wlhttp.lpr')],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, result.stdout
    return out / 'wlhttp'


def pure_checks(tmp):
    """The builders and the parser, compiled and run as a small Pascal program."""
    src = tmp / 'rtcheck.lpr'
    src.write_text('''program rtcheck;
{$mode objfpc}{$H+}
uses SysUtils, wlroutes;
var B, S, C: string;
procedure Split(const P: string);
begin
  if SplitBoardRoute(P, B, S, C) then WriteLn(P, '|1|', B, '|', S, '|', C)
  else WriteLn(P, '|0');
end;
begin
  WriteLn(BoardRoute('abc', 'my-board'));
  WriteLn(BoardRoute('abc', ''));
  WriteLn(CardRoute('abc', 'my-board', 'c1'));
  WriteLn(BoardRoute('a b', 'x/y'));
  Split('/b/abc/my-board');
  Split('/b/abc/my-board/');
  Split('/b/abc');
  Split('/b/abc/my-board/c1');
  Split('/b/a%20b/x%2Fy');
  Split('/b/templates');
  Split('/b/abc/my-board/rules');
  Split('/b/abc/my-board/rules/export');
  Split('/b/abc/my-board/rules/other');
  Split('/b/abc/my-board/c1/extra');
  Split('/b//my-board');
  Split('/b/');
  Split('/board');
end.
''')
    build = tmp / 'rt-build'
    build.mkdir(exist_ok=True)
    result = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(build), '-FE' + str(build), str(src)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, result.stdout
    out = subprocess.run([str(build / 'rtcheck')], capture_output=True, text=True, check=True).stdout.splitlines()
    assert out == [
        '/b/abc/my-board',
        '/b/abc/board',                      # WeKan's default slug
        '/b/abc/my-board/c1',
        '/b/a+b/x%2Fy',                      # each part encoded: a slug cannot add a path part
        '/b/abc/my-board|1|abc|my-board|',
        '/b/abc/my-board/|1|abc|my-board|',
        '/b/abc|1|abc||',                    # WeKan's /b/:id
        '/b/abc/my-board/c1|1|abc|my-board|c1',
        '/b/a%20b/x%2Fy|1|a b|x/y|',
        '/b/templates|0',                    # WeKan's templates container
        # WeKan's /b/:id/:slug/rules is the board's Rules page (wlrules,
        # 2026-11-26): carried as the card part 'rules', and its downloads as
        # 'rules/export', which ServeWekanRoute sends to /board/rules[/export].
        # This was a negative case before the Rules page existed.
        '/b/abc/my-board/rules|1|abc|my-board|rules',
        '/b/abc/my-board/rules/export|1|abc|my-board|rules/export',
        # Negative: WeKan's own pages and anything else are not a board.
        '/b/abc/my-board/rules/other|0',
        '/b/abc/my-board/c1/extra|0',
        '/b//my-board|0',
        '/b/|0',
        '/board|0',
    ], out
    print('PASS: route builders and parser')


def http_checks(server, tmp, backend):
    data = tmp / ('data-' + backend)
    listen = free_port()
    env = dict(os.environ, WELITE_DATA=str(data), WELITE_SHARED='0', WELITE_PORT=str(listen),
               WELITE_SCHEMA=str(ROOT / 'src/schema.sql'), WELITE_DESIGNER=str(ROOT / 'src/designer.sql'),
               WELITE_I18N=str(ROOT / 'i18n'))
    for variable in ['REQUIRE_2FA', 'LDAP_ENABLE', 'WELITE_ENTROPY_FILE', 'WELITE_ARGON_SECRET_FILE', 'WELITE_SHORT_NAMES']:
        env.pop(variable, None)
    log = (tmp / ('server-' + backend + '.log')).open('w+')
    proc = subprocess.Popen([str(server)], cwd=tmp, env=env, stdout=log, stderr=log)

    def request(method, path, data=None, headers=None, as_json=False):
        conn = http.client.HTTPConnection('127.0.0.1', listen, timeout=20)
        h = {'Host': 'localhost', 'User-Agent': 'Welite-test'}
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
        # WeKan's /sign-up is registration: the form, and the account it creates.
        status, _, form = request('GET', '/sign-up')
        assert status == 200 and b'name="confirm"' in form, (status, form[-300:])
        status, _, home = request('POST', '/sign-up', {'username': 'owner', 'password': 'test-password',
                                                      'confirm': 'test-password'})
        assert status == 200, (status, home[-300:])
        session = re.search(rb'name="sessionId" value="([0-9a-f]+)"', home).group(1).decode()
        assert b'action="/sign-up"' in home and b'action="/register"' not in home, 'links name WeKan\'s /sign-up'
        # The old /register still registers (an alias).
        status, _, _ = request('POST', '/register', {'username': 'other', 'password': 'test-password',
                                                     'confirm': 'test-password'})
        assert status == 200

        status, _, body = request('POST', '/users/login', {'username': 'owner', 'password': 'test-password'})
        assert status == 200, body
        login = json.loads(body)
        auth = {'Authorization': 'Bearer ' + login['token']}
        status, _, body = request('POST', '/api/boards', {'title': 'Route Board', 'owner': login['id']},
                                  headers=auth, as_json=True)
        assert status == 200, body
        board = json.loads(body)
        board_id, lane = board['_id'], board['defaultSwimlaneId']
        status, _, body = request('POST', '/api/boards/%s/lists' % board_id, {'title': 'Todo'}, headers=auth, as_json=True)
        assert status == 200, body
        list_id = json.loads(body)['_id']
        status, _, body = request('POST', '/api/boards/%s/lists/%s/cards' % (board_id, list_id),
                                  {'title': 'Route Card', 'authorId': login['id'], 'swimlaneId': lane},
                                  headers=auth, as_json=True)
        assert status == 200, body
        card_id = json.loads(body)['_id']

        def get(path):
            sep = '&' if '?' in path else '?'
            return request('GET', path + sep + 'sessionId=' + session)

        # All Boards links the board by WeKan's route, with the board's own slug.
        status, _, home = get('/')
        assert status == 200
        route = '/b/%s/route-board' % board_id
        assert ('action="%s' % route).encode() in home, home[-800:]
        assert b'/board?id=' not in home, 'no former board link left'

        # The board, under its route; the slug is not checked, and /b/:id is the board too.
        for path in [route, '/b/%s/any-slug' % board_id, '/b/%s' % board_id, route + '/']:
            status, _, page = get(path)
            assert status == 200 and b'Route Board' in page and b'Route Card' in page, (path, status)
        status, _, page = get(route)
        card_route = '%s/%s' % (route, card_id)
        # A board its viewer may change opens a card in the same POSTed form, so
        # the session never goes into a URL (fd5f992); the route is for links.
        assert ('name="view_card" value="%s"' % card_id).encode() in page
        assert b'/board/card?id=' not in page and b'/board?id=' not in page, 'no former board or card link left'
        assert ('action="%s?' % route).encode() in page, 'the board\'s own forms post to its route'

        # The card, under WeKan's card route.
        status, _, page = get(card_route)
        assert status == 200 and b'Route Card' in page, status
        assert route.encode() in page, 'the card links back to its board by the route'

        # The former routes still open the same pages.
        status, _, page = get('/board?id=' + board_id)
        assert status == 200 and b'Route Card' in page
        status, _, page = get('/board/card?id=%s&card=%s' % (board_id, card_id))
        assert status == 200 and b'Route Card' in page

        # Negative: an unknown board is not found under the route either, and a
        # path with more parts, or WeKan's own /b/templates, is not a board.
        status, _, page = get('/b/no-such-board/x')
        assert status == 404, status
        status, _, _ = get('/b/%s/route-board/%s/extra' % (board_id, card_id))
        assert status == 404, status
        status, _, page = get('/b/templates')
        assert b'Route Card' not in page
        # Negative: without a session the board is not shown, under either route.
        for path in [route, '/board?id=' + board_id]:
            status, _, page = request('GET', path)
            assert b'Route Card' not in page, path
        print('PASS: WeKan routes over HTTP (%s SQLite)' % backend)
    finally:
        proc.terminate()
        proc.wait(10)
        log.close()


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='routes.', dir=base) as name:
        tmp = Path(name)
        pure_checks(tmp)
        for backend, flags in [('linked', []), ('cli', ['-dWLDB_CLI'])]:
            server = compile_server(tmp / ('build-' + backend), flags)
            http_checks(server, tmp, backend)


if __name__ == '__main__':
    sys.exit(main())

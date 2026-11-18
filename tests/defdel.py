"""Definition DELETE removes its own card values in the same transaction."""
import json
from urllib.parse import quote

from optdel import connect
from wire import encode


def exercise(call, board, snapshot, assign, verify, fail, clear):
    base = '/api/boards/' + quote(board, safe='') + '/custom-fields'

    def create(name):
        status, _, body = call('POST', base, dict(name=name, type='text'))
        assert status == 200, (status, body)
        return json.loads(body)['_id']

    identity, sibling = create('Delete definition'), create('Keep definition')
    assign(identity, sibling)
    route = base + '/' + quote(identity, safe='')

    def missing(path):
        status, _, body = call('DELETE', path, None)
        assert status == 404 and json.loads(body) == dict(error='Custom field not found'), (status, body)

    before = snapshot()
    missing(base + '/missing')
    assert snapshot() == before
    fail()
    try:
        status, _, body = call('DELETE', route, None)
        assert status == 500, (status, body)
        assert snapshot() == before
    finally:
        clear()

    status, _, body = call('DELETE', route, None)
    assert status == 200 and json.loads(body) == dict(_id=identity), (status, body)
    verify(identity, sibling)
    assert call('GET', route, None)[0] == 404
    missing(route)
    print('PASS: definition DELETE removes scoped values and activities, retains siblings and rolls back on a definition write failure')


def native(call, db, board, snapshot):
    with connect(db) as con:
        card, = con.execute('SELECT id FROM cards WHERE boardId=? ORDER BY id LIMIT 1', (board,)).fetchone()

    def assign(identity, sibling):
        with connect(db) as con:
            con.executemany('INSERT INTO card_custom_field_values VALUES(?,?,?)',
                            [(card, identity, 'Remove'), (card, sibling, 'Keep')])

    def verify(identity, sibling):
        with connect(db) as con:
            assert con.execute('SELECT id FROM custom_fields WHERE id IN (?,?)', (identity, sibling)).fetchall() == [(sibling,)]
            assert con.execute("SELECT json_extract(data_json,'$.customFieldId') FROM activities WHERE "
                               "json_extract(data_json,'$.customFieldId') IN (?,?)", (identity, sibling)).fetchall() == [(sibling,)]
            assert con.execute('SELECT customFieldId,value FROM card_custom_field_values WHERE cardId=? AND customFieldId IN (?,?)',
                               (card, identity, sibling)).fetchall() == [(sibling, 'Keep')]

    exercise(call, board, snapshot, assign, verify,
             lambda: install_failure(db, 'custom_fields'), lambda: clear_failure(db))

    base = '/api/boards/' + quote(board, safe='') + '/custom-fields'
    status, _, body = call('POST', base, dict(name='Shared definition', type='text'))
    assert status == 200, (status, body)
    identity = json.loads(body)['_id']
    route = base + '/' + quote(identity, safe='')
    with connect(db) as con:
        con.execute("INSERT INTO boards(id,title,slug,createdAt,archived) VALUES('def-other','Other','other','now',1)")
        con.execute("INSERT INTO lists(id,boardId,title,createdAt) VALUES('def-list','def-other','Other','now')")
        con.execute("INSERT INTO cards(id,boardId,listId,title,createdAt,userId,dateLastActivity,modifiedAt) SELECT 'def-card','def-other','def-list','Other','now',userId,'now','now' FROM cards WHERE id=?", (card,))
        con.execute("INSERT INTO custom_field_boards VALUES(?,'def-other')", (identity,))
    before = snapshot()
    assert call('PUT', route, dict(name='Denied'))[0] == 403
    assert call('DELETE', route, None)[0] == 403
    assert snapshot() == before
    with connect(db) as con:
        con.execute("UPDATE boards SET archived=0 WHERE id='def-other'")
        actor, = con.execute("SELECT userId FROM activities WHERE json_extract(data_json,'$.customFieldId')=?", (identity,)).fetchone()
        con.execute("INSERT INTO board_members(boardId,userId,isAdmin) VALUES('def-other',?,1)", (actor,))
    status, _, body = call('PUT', route, dict(name='Shared update', alwaysOnCard=True))
    assert status == 200, (status, body)
    with connect(db) as con:
        assert con.execute("SELECT value FROM card_custom_field_values WHERE cardId='def-card' AND customFieldId=?", (identity,)).fetchall() == [(None,)]
    assert call('DELETE', route, None)[0] == 200
    with connect(db) as con:
        assert con.execute('SELECT count(*) FROM card_custom_field_values WHERE customFieldId=?', (identity,)).fetchone() == (0,)
    print('PASS: multi-board field mutations require every board and cover card values on every bound board')


def shared(call, client, db, board, snapshot):
    card = client.command({'find':'cards','filter':dict(boardId=board),'limit':1})['cursor']['firstBatch'][0]
    card_id = card['_id']
    expected = None

    def assign(identity, sibling):
        nonlocal expected
        keep = dict(_id=sibling, value='Keep', extra=dict(preserved=True))
        expect_doc = dict(card, customFields=[*card.get('customFields', []), keep])
        expected = encode(expect_doc)
        fields = [*expect_doc['customFields'], dict(_id=identity, value='Remove')]
        assert client.command({'update':'cards','updates':[dict(q=dict(_id=card_id),u={'$set':dict(customFields=fields)})]})['n'] == 1

    def verify(identity, sibling):
        assert client.find('customFields', identity) == []
        assert len(client.find('customFields', sibling)) == 1
        activities = client.command({'find':'activities','filter':{
            'customFieldId':{'$in':[identity, sibling]}}})['cursor']['firstBatch']
        assert [entry['customFieldId'] for entry in activities] == [sibling], activities
        assert encode(client.find('cards', card_id)[0]) == expected

    with connect(db) as con:
        table, = con.execute("SELECT table_name FROM _wl_models WHERE name='custom_fields'").fetchone()
    exercise(call, board, snapshot, assign, verify,
             lambda: install_failure(db, table), lambda: clear_failure(db))


def install_failure(db, table):
    with connect(db) as con:
        con.execute(f'CREATE TRIGGER def_del_fail AFTER DELETE ON "{table.replace(chr(34), chr(34)*2)}" '
                    "BEGIN SELECT RAISE(FAIL,'test delete failure'); END")


def clear_failure(db):
    with connect(db) as con:
        con.execute('DROP TRIGGER def_del_fail')

"""Verify automatic definitions seed new API cards with explicit null values."""
import json
from urllib.parse import quote

from optdel import connect


def run(call, board, list_id, lane, existing_card, values, snapshot, fail, clear):
    base = '/api/boards/' + quote(board, safe='')
    fields = base + '/custom-fields'

    def create(name, **flags):
        status, _, body = call('POST', fields, dict(name=name, type='text', **flags))
        assert status == 200, (status, body)
        return json.loads(body)['_id']

    automatic = create('Automatic', automaticallyOnCard=True)
    always = create('Always')
    never = create('Manual')
    before = snapshot()
    fail(always)
    try:
        status, _, body = call('PUT', fields + '/' + always, dict(alwaysOnCard=True))
        assert status == 500, (status, body)
        assert snapshot() == before
    finally:
        clear()
    status, _, body = call('PUT', fields + '/' + always, dict(alwaysOnCard=True))
    assert status == 200, (status, body)
    existing = values(existing_card)
    assert existing.get(always, False) is None and automatic not in existing, existing

    data = dict(title='Card with automatic definitions')
    if lane:
        data['swimlaneId'] = lane
    path = base + '/lists/' + quote(list_id, safe='') + '/cards'
    existing_value = path + '/' + quote(existing_card, safe='') + '/customFields/' + always
    status, _, body = call('POST', existing_value, dict(value='Keep this value'))
    assert status == 200, (status, body)
    status, _, body = call('PUT', fields + '/' + always, dict(alwaysOnCard=True))
    assert status == 200 and values(existing_card)[always] == 'Keep this value', (status, body)
    before = snapshot()
    fail(automatic)
    try:
        status, _, body = call('POST', path, data)
        assert status == 500, (status, body)
        assert snapshot() == before
    finally:
        clear()
    status, _, body = call('POST', path, data)
    assert status == 200, (status, body)
    card_id = json.loads(body)['_id']
    actual = values(card_id)
    assert actual.get(automatic, False) is None and actual.get(always, False) is None, actual
    assert never not in actual, actual
    print('PASS: API card creation seeds null placeholders and always-on fields backfill atomically')


def native(call, db, board, snapshot):
    with connect(db) as con:
        list_id, lane = con.execute('SELECT id,swimlaneId FROM lists WHERE boardId=? ORDER BY id LIMIT 1', (board,)).fetchone()
        existing, = con.execute('SELECT id FROM cards WHERE listId=? ORDER BY id LIMIT 1', (list_id,)).fetchone()

    def values(card_id):
        with connect(db) as con:
            return dict(con.execute('SELECT customFieldId,value FROM card_custom_field_values WHERE cardId=?', (card_id,)))

    def fail(identity):
        with connect(db) as con:
            con.execute("CREATE TRIGGER auto_fail AFTER INSERT ON card_custom_field_values "
                        f"WHEN NEW.customFieldId='{identity}' BEGIN SELECT RAISE(FAIL,'test automatic field failure'); END")

    run(call, board, list_id, lane, existing, values, snapshot, fail, lambda: clear_failure(db))


def shared(call, client, db, board, snapshot):
    item = client.command({'find':'lists','filter':dict(boardId=board),'limit':1})['cursor']['firstBatch'][0]
    existing = client.command({'find':'cards','filter':dict(listId=item['_id']),'limit':1})['cursor']['firstBatch'][0]['_id']

    def values(card_id):
        return {field['_id']: field['value'] for field in client.find('cards', card_id)[0]['customFields']}

    def fail(identity):
        with connect(db) as con:
            table, = con.execute("SELECT table_name FROM _wl_models WHERE name='cards'").fetchone()
            table = '"' + table.replace('"', '""') + '"'
            con.execute(f"CREATE TRIGGER auto_fail AFTER UPDATE ON {table} WHEN EXISTS("
                        "SELECT 1 FROM json_each(NEW._ferretdb_sjson,'$.customFields') "
                        f"WHERE json_extract(value,'$._id')='{identity}') "
                        "BEGIN SELECT RAISE(FAIL,'test automatic field failure'); END")

    run(call, board, item['_id'], item.get('swimlaneId'), existing, values, snapshot, fail, lambda: clear_failure(db))


def clear_failure(db):
    with connect(db) as con:
        con.execute('DROP TRIGGER auto_fail')

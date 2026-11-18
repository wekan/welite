"""Verify automatic definitions seed new API cards with explicit null values."""
import json
from urllib.parse import quote

from optdel import connect


def run(call, board, list_id, lane, values, snapshot, fail, clear):
    base = '/api/boards/' + quote(board, safe='')
    fields = base + '/custom-fields'

    def create(name, **flags):
        status, _, body = call('POST', fields, dict(name=name, type='text', **flags))
        assert status == 200, (status, body)
        return json.loads(body)['_id']

    automatic = create('Automatic', automaticallyOnCard=True)
    always = create('Always')
    never = create('Manual')
    status, _, body = call('PUT', fields + '/' + always, dict(alwaysOnCard=True))
    assert status == 200, (status, body)

    data = dict(title='Card with automatic definitions')
    if lane:
        data['swimlaneId'] = lane
    path = base + '/lists/' + quote(list_id, safe='') + '/cards'
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
    print('PASS: API card creation seeds automatic and always-on custom fields as explicit null')


def native(call, db, board, snapshot):
    with connect(db) as con:
        list_id, lane = con.execute('SELECT id,swimlaneId FROM lists WHERE boardId=? ORDER BY id LIMIT 1', (board,)).fetchone()

    def values(card_id):
        with connect(db) as con:
            return dict(con.execute('SELECT customFieldId,value FROM card_custom_field_values WHERE cardId=?', (card_id,)))

    def fail(identity):
        with connect(db) as con:
            con.execute("CREATE TRIGGER auto_fail AFTER INSERT ON card_custom_field_values "
                        f"WHEN NEW.customFieldId='{identity}' BEGIN SELECT RAISE(FAIL,'test automatic field failure'); END")

    run(call, board, list_id, lane, values, snapshot, fail, lambda: clear_failure(db))


def shared(call, client, db, board, snapshot):
    item = client.command({'find':'lists','filter':dict(boardId=board),'limit':1})['cursor']['firstBatch'][0]

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

    run(call, board, item['_id'], item.get('swimlaneId'), values, snapshot, fail, lambda: clear_failure(db))


def clear_failure(db):
    with connect(db) as con:
        con.execute('DROP TRIGGER auto_fail')

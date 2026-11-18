"""Exercise list soft deletion against the live FerretDB source documents."""
import json
import sqlite3

from wire import DateMs, encode


def run(request, client, db, token):
    lists_path = '/api/boards/b/lists'
    status, _, body = request('POST', lists_path, {'title': 'Soft delete'}, token)
    assert status == 200, (status, body)
    list_id = json.loads(body)['_id']
    path = lists_path + '/' + list_id
    status, _, body = request('POST', path + '/cards', {'title': 'Retained', 'swimlaneId': 's'}, token)
    assert status == 200, (status, body)
    card_id = json.loads(body)['_id']
    original_list = client.find('lists', list_id)[0]
    original_card = client.find('cards', card_id)[0]

    with sqlite3.connect(db) as con:
        table, = con.execute("SELECT table_name FROM _wl_models WHERE name='lists'").fetchone()
        quoted = '"' + table.replace('"', '""') + '"'
        con.execute(f'CREATE TRIGGER reject_list_mark AFTER UPDATE ON {quoted} '
                    "BEGIN SELECT RAISE(FAIL,'test list mark failure'); END")
    try:
        assert request('DELETE', path, token=token)[0] == 500
        assert encode(client.find('lists', list_id)[0]) == encode(original_list)
        assert encode(client.find('cards', card_id)[0]) == encode(original_card)
    finally:
        with sqlite3.connect(db) as con:
            con.execute('DROP TRIGGER reject_list_mark')

    status, _, body = request('DELETE', path, token=token)
    assert status == 200 and json.loads(body) == {'_id': list_id}, (status, body)
    retained_list = client.find('lists', list_id)[0]
    retained_card = client.find('cards', card_id)[0]
    markers = ('deletedAt', 'deletedBy', 'deleteBatchId')
    assert isinstance(retained_list['deletedAt'], DateMs) and retained_list['deletedBy'] == 'u'
    assert retained_list['deleteBatchId'] and all(retained_list[k] == retained_card[k] for k in markers)
    assert isinstance(retained_card['deletedAt'], DateMs)
    assert {k:v for k,v in retained_list.items() if k not in markers} == original_list
    assert {k:v for k,v in retained_card.items() if k not in markers} == original_card
    assert request('GET', path, token=token)[0] == 404
    assert request('GET', '/api/cards/' + card_id, token=token)[0] == 404
    assert request('DELETE', path, token=token)[0] == 404
    print('PASS: live shared list DELETE retains typed batch markers and restores both source documents on failure')

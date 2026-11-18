"""Exercise list soft deletion against the live FerretDB source documents."""
import json
import sqlite3
from urllib.parse import parse_qs, urlencode, urlsplit

from layout import Forms

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
    def history(action):
        result=client.command({'find':'userPositionHistory','filter':dict(entityId=list_id,actionType=action)})
        return result['cursor']['firstBatch']
    deleted,=history('delete')
    assert deleted['batchId']==retained_list['deleteBatchId'] and isinstance(deleted['createdAt'],DateMs),deleted
    assert deleted['newState']['deletedAt']==retained_list['deletedAt'] and isinstance(deleted['newState']['deletedAt'],DateMs),deleted
    assert deleted['previousState']==dict(boardId='b',swimlaneId='s',sort=original_list['sort']),deleted
    print('PASS: live shared list DELETE retains typed batch markers and restores both source documents on failure')

    status, headers, _ = request('POST', '/sign-in', urlencode(dict(username='user', password='test-password')))
    assert status in (302,303) and 'Set-Cookie' not in headers, (status,headers)
    session = parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
    board_path = '/board?id=b&view=all&sessionId=' + session

    def restore_fields():
        status, _, body = request('GET', board_path)
        assert status == 200, (status,body)
        forms = Forms()
        forms.feed(body.decode())
        fields, = [fields for action,fields in forms.forms
                   if action == '/board/restore-list' and fields.get('listId') == list_id]
        return fields

    with sqlite3.connect(db) as con:
        con.execute(f'CREATE TRIGGER reject_list_restore AFTER UPDATE ON {quoted} '
                    "BEGIN SELECT RAISE(FAIL,'test list restore failure'); END")
    try:
        assert request('POST', '/board/restore-list', urlencode(restore_fields()))[0] == 409
        assert encode(client.find('lists',list_id)[0]) == encode(retained_list)
        assert encode(client.find('cards',card_id)[0]) == encode(retained_card)
    finally:
        with sqlite3.connect(db) as con:
            con.execute('DROP TRIGGER reject_list_restore')

    fields = restore_fields()
    status, headers, _ = request('POST', '/board/restore-list', urlencode(fields))
    assert status == 302 and 'Set-Cookie' not in headers, (status,headers)
    assert request('GET', headers['Location'])[0] == 200
    assert request('POST', '/board/restore-list', urlencode(fields))[0] == 403
    assert encode(client.find('lists',list_id)[0]) == encode(original_list)
    assert encode(client.find('cards',card_id)[0]) == encode(original_card)
    assert request('GET', path, token=token)[0] == 200
    assert request('GET', '/api/cards/' + card_id, token=token)[0] == 200
    restored,=history('restore')
    assert restored['batchId']==deleted['batchId'] and restored['newState']==dict(deletedAt=None),restored
    assert restored['previousState']==deleted['newState'] and isinstance(restored['previousState']['deletedAt'],DateMs),restored
    print('PASS: live shared delete and restore write typed WeKan position history')
    print('PASS: live shared HTML restore unsets the batch, preserves BSON, and rolls back both rows on failure')

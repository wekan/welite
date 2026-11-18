"""Exercise list soft deletion against the live FerretDB source documents."""
import json
import hashlib
import sqlite3
from urllib.parse import urlencode

from layout import Forms

from wire import DateMs, encode


def run(request, client, db, token, refresh_ferret, session):
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT 1 FROM _ferretdb_collections WHERE name='userPositionHistory'").fetchone() is None
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
    with sqlite3.connect(db) as con:
        name,=con.execute("SELECT table_name FROM _ferretdb_collections WHERE name='userPositionHistory'").fetchone()
        history_table='"'+name.replace('"','""')+'"'
        assert con.execute('SELECT count(*) FROM '+history_table).fetchone()==(1,)
    refresh_ferret()
    deleted,=history('delete')
    assert deleted['batchId']==retained_list['deleteBatchId'] and isinstance(deleted['createdAt'],DateMs),deleted
    assert deleted['newState']['deletedAt']==retained_list['deletedAt'] and isinstance(deleted['newState']['deletedAt'],DateMs),deleted
    assert deleted['previousState']==dict(boardId='b',swimlaneId='s',sort=original_list['sort']),deleted
    print('PASS: live shared list DELETE retains typed batch markers and restores both source documents on failure')

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
    def changes():
        result=client.command({'find':'changeHistory','filter':dict(entityId=list_id)})
        return {entry['changeType']:entry for entry in result['cursor']['firstBatch']}
    lifecycle=changes()
    assert set(lifecycle)=={'removed','added'}, lifecycle
    removed, added=lifecycle['removed'], lifecycle['added']
    assert removed['previousHash'] is None and added['previousHash']==removed['integrityHash'], lifecycle
    assert removed['newContent']==added['previousContent'] and isinstance(removed['newContent']['deletedAt'],DateMs), lifecycle
    client.command({'create':'historyWriterGates'})
    def board_key(kind):
        return hashlib.sha256(json.dumps([kind,'b'],separators=(',',':')).encode()).hexdigest()
    gate_id=board_key('history-writer-gate')
    idle_gate=dict(_id=gate_id,boardId='b',version=1,mode='legacy',migrationId=None,writers=[])
    assert client.command({'insert':'historyWriterGates','documents':[idle_gate]})['n']==1
    try:
        assert request('DELETE',path,token=token)[0]==200
        assert changes()['removed']['previousHash']==added['integrityHash']
        assert request('POST','/board/restore-list',urlencode(restore_fields()))[0]==302
        lifecycle=changes()
        removed,added=lifecycle['removed'],lifecycle['added']
        assert added['previousHash']==removed['integrityHash']
        assert client.find('historyWriterGates',gate_id)==[idle_gate]
    finally:
        assert client.command({'delete':'historyWriterGates','deletes':[dict(q={'_id':gate_id},limit=1)]})['n']==1
    print('PASS: shared lifecycle appends atomically through an idle legacy WeKan gate')
    assert client.command({'insert':'historyWriterGates','documents':[
        dict(_id='list-test-gate',boardId='b',mode='coordinated') ]})['n']==1
    try:
        assert request('DELETE',path,token=token)[0]==200
        assert changes()==lifecycle
    finally:
        assert client.command({'delete':'historyWriterGates','deletes':[dict(q={'_id':'list-test-gate'},limit=1)]})['n']==1
    print('PASS: shared legacy lifecycle chain links typed records and defers to a WeKan writer gate')

    head_id=board_key('history-chain')
    client.command({'create':'historyChainHeads'})
    assert client.command({'insert':'historyWriterGates','documents':[
        dict(_id=gate_id,boardId='b',version=1,mode='coordinated',
             migrationId='11111111-2222-4333-8444-555555555555',writers=[])]})['n']==1
    assert client.command({'insert':'historyChainHeads','documents':[
        dict(_id=head_id,boardId='b',version=1,hash=added['integrityHash'],pending=None,pendingHash=None)]})['n']==1
    try:
        assert request('POST','/board/restore-list',urlencode(restore_fields()))[0]==302
        head=client.find('historyChainHeads',head_id)[0]
        current,=client.command({'find':'changeHistory','filter':dict(integrityHash=head['hash'])})['cursor']['firstBatch']
        assert head['hash']!=added['integrityHash'] and head['pending'] is None and head['pendingHash'] is None, head
        assert current['previousHash']==added['integrityHash'] and current['changeType']=='added', current
        assert current['newContent']['deleted'] is False and isinstance(current['previousContent']['deletedAt'],DateMs), current
        # A reservation owned by WeKan must survive a concurrent list mutation.
        pending = dict(_id='wekan-pending-history', boardId='b', previousHash=head['hash'])
        result = client.command({'update':'historyChainHeads','updates':[
            dict(q={'_id':head_id},u={'$set':dict(pending=pending,pendingHash='reserved')})]})
        assert result['n']==1, result
        reserved,=client.find('historyChainHeads',head_id)
        before=changes()
        assert request('DELETE',path,token=token)[0]==200
        assert changes()==before
        assert encode(client.find('historyChainHeads',head_id)[0])==encode(reserved)
        invalid_hash='g'*64
        result=client.command({'update':'historyChainHeads','updates':[
            dict(q={'_id':head_id},u={'$set':dict(hash=invalid_hash,pending=None,pendingHash=None)})]})
        assert result['n']==1, result
        assert request('POST','/board/restore-list',urlencode(restore_fields()))[0]==302
        assert changes()==before and client.find('historyChainHeads',head_id)[0]['hash']==invalid_hash
        result=client.command({'update':'historyChainHeads','updates':[
            dict(q={'_id':head_id},u={'$set':dict(hash=head['hash'])})]})
        assert result['n']==1, result
        result=client.command({'update':'historyWriterGates','updates':[
            dict(q={'_id':gate_id},u={'$set':dict(migrationId='invalid')})]})
        assert result['n']==1, result
        assert request('DELETE',path,token=token)[0]==200
        assert changes()==before and client.find('historyChainHeads',head_id)[0]['hash']==head['hash']
    finally:
        for collection,key in [('historyWriterGates',gate_id),('historyChainHeads',head_id)]:
            assert client.command({'delete':collection,'deletes':[dict(q={'_id':key},limit=1)]})['n']==1
    print('PASS: shared coordinated lifecycle append advances an idle head with the typed history row')
    print('PASS: shared coordinated list deletion leaves an occupied reservation intact')
    print('PASS: malformed coordinated history gate and head cannot advance the chain')

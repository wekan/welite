"""Real-router percent IDs retain resource ownership and one-pass identity."""
import json
import sqlite3
from urllib.parse import quote
from wire import encode, DateMs

BOARD='path 漢+%2F'
LIST='path list+%2B'
FIELD='path field+%25'
IDS=['path / 漢+%2F','path%2F','path/','path+id','path id']
FOREIGN='path foreign 漢'

def exercise(call, uid, snapshot):
    q=lambda value:quote(value,safe='')
    root='/api/boards/'+q(BOARD)
    base=root+'/lists/'+q(LIST)+'/cards/'
    assert json.loads(call('GET',root,None)[2])['_id']==BOARD
    assert json.loads(call('GET',root+'/custom-fields/'+q(FIELD),None)[2])['_id']==FIELD
    # Explicitly escaped unreserved bytes also decode before user identity checks.
    escaped_uid=''.join('%%%02X'%byte for byte in uid.encode())
    status,_,body=call('GET','/api/users/'+escaped_uid+'/boards',None)
    assert status==200,(status,body)
    assert BOARD in {row['_id'] for row in json.loads(body)}
    for cid in IDS:
        status,_,body=call('GET',base+q(cid),None)
        assert status==200,(cid,status,body)
        card=json.loads(body);assert card['_id']==cid and card['title']==cid,(cid,card)
        status,_,body=call('POST',base+q(cid)+'/customFields/'+q(FIELD),dict(value=cid))
        assert status==200 and json.loads(body)['_id']==cid,(cid,status,body)
        card=json.loads(call('GET',base+q(cid),None)[2])
        assert next(row['value'] for row in card['customFields'] if row['_id']==FIELD)==cid
    # Literal '+' in a path must select the plus ID, rather than the space ID.
    status,_,body=call('GET',base+'path+id',None)
    assert status==200 and json.loads(body)['_id']=='path+id',(status,body)
    # Encoded slashes stay inside this captured ID; %252F resolves to literal %2F.
    assert json.loads(call('GET',base+'path%252F',None)[2])['_id']=='path%2F'
    assert json.loads(call('GET',base+'path%2f',None)[2])['_id']=='path/'
    for suffix in ['members','assignees']:
        path=base+q(IDS[0])+'/'+suffix+'/'+escaped_uid
        assert call('POST',path,None)[0]==200
        assert call('DELETE',path,None)[0]==200
    bad=['%','%0','%xz','%00','%0A','%7f','%80','%C0%AF','%ED%A0%80','%F4%90%80%80','%E6%BC']
    for value in bad:
        before=snapshot()
        for path in [base+value,root+'/lists/'+value+'/cards/'+q(IDS[0])]:
            status,_,body=call('GET',path,None)
            assert status==400,(path,status,body)
            assert json.loads(body)['error']==400
        status,_,body=call('POST',base+q(IDS[0])+'/customFields/'+value,dict(value='attack'))
        assert status==400,(value,status,body)
        assert snapshot()==before,value
    before=snapshot()
    # An encoded foreign ID must still fail the original board/parent check.
    for path in [root+'/lists/'+q(LIST)+'/cards/'+q(FOREIGN),
                 root+'/lists/'+q(FOREIGN)+'/cards/'+q(IDS[0])]:
        assert call('GET',path,None)[0]==404
        assert call('POST',path+'/customFields/'+q(FIELD),dict(value='attack'))[0]==404
    assert snapshot()==before
    print('PASS: real API router UTF-8/space/plus/percent/slash IDs, one-pass decoding, user/member/assignee paths, malformed rejection and foreign-parent isolation')


def run_native(call, db, uid):
    with sqlite3.connect(db) as con:
        for bid in [BOARD,FOREIGN]:
            con.execute('INSERT INTO boards(id,title,slug,createdAt) VALUES(?,?,?,?)',(bid,bid,bid,'now'))
            con.execute('INSERT INTO board_members(boardId,userId,isAdmin) VALUES(?,?,1)',(bid,uid))
        for lid,bid in [(LIST,BOARD),(FOREIGN,FOREIGN)]:
            con.execute('INSERT INTO lists(id,boardId,title,createdAt) VALUES(?,?,?,?)',(lid,bid,lid,'now'))
        for cid,lid,bid in [(cid,LIST,BOARD) for cid in IDS]+[(FOREIGN,FOREIGN,FOREIGN)]:
            con.execute('INSERT INTO cards(id,title,listId,boardId,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,?,?,?,?,?,?)',(cid,cid,lid,bid,uid,'now','now','now'))
        con.execute('INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES(?,?,?,?)',(FIELD,FIELD,'text','now'))
        con.execute('INSERT INTO custom_field_boards(customFieldId,boardId) VALUES(?,?)',(FIELD,BOARD))
    def snapshot():
        with sqlite3.connect(db) as con:
            return tuple(con.execute('SELECT * FROM '+name+' ORDER BY 1,2').fetchall() for name in ['cards','card_custom_field_values','card_members','card_assignees'])
    exercise(call,uid,snapshot)


def run_shared(call, client, uid):
    assert client.command({'insert':'boards','documents':[dict(_id=bid,title=bid,slug=bid,permission='private',members=[dict(userId=uid,isAdmin=True,isActive=True,isReadOnly=False)]) for bid in [BOARD,FOREIGN]]})['n']==2
    assert client.command({'insert':'lists','documents':[dict(_id=lid,title=lid,boardId=bid) for lid,bid in [(LIST,BOARD),(FOREIGN,FOREIGN)]]})['n']==2
    docs=[dict(_id=cid,title=cid,listId=LIST,boardId=BOARD,unknown=DateMs(-1)) for cid in IDS]
    docs.append(dict(_id=FOREIGN,title=FOREIGN,listId=FOREIGN,boardId=FOREIGN,unknown=DateMs(-1)))
    assert client.command({'insert':'cards','documents':docs})['n']==len(docs)
    assert client.command({'insert':'customFields','documents':[dict(_id=FIELD,name=FIELD,type='text',boardIds=[BOARD])]})['n']==1
    def snapshot():return [encode(client.find('cards',doc['_id'])[0]) for doc in docs]
    exercise(call,uid,snapshot)

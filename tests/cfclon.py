"""Shared HTML clone permissions and transaction-time field/role changes."""
import json
import sqlite3
from urllib.parse import urlencode,parse_qs,urlsplit
from layout import Forms
from wire import DateMs,encode


def run_shared(request,client,db):
    uid='u';board='clone-policy';cid='clone-original';field='clone-field'
    original_user=client.find('users',uid)[0]
    def update(collection,identity,changes):
        assert client.command({'update':collection,'updates':[dict(q=dict(_id=identity),u={'$set':changes})]})['n']==1
    def role(admin):update('boards',board,dict(members=[dict(userId=uid,isActive=True,isAdmin=admin)]))
    assert client.command({'insert':'boards','documents':[dict(_id=board,title=board,slug=board,permission='private',members=[dict(userId=uid,isActive=True,isAdmin=False)])]})['n']==1
    assert client.command({'insert':'lists','documents':[dict(_id='clone-list',boardId=board,title='Clone')]})['n']==1
    assert client.command({'insert':'customFields','documents':[dict(_id=field,name='Clone field',type='text',boardIds=[board],adminOnly=False,readOnly=False)]})['n']==1
    assert client.command({'insert':'cards','documents':[dict(_id=cid,boardId=board,listId='clone-list',userId=uid,title='Clone card',createdAt=DateMs(0),modifiedAt=DateMs(0),dateLastActivity=DateMs(0),customFields=[dict(_id=field,value='original')])]})['n']==1
    status,headers,body=request('POST','/sign-in',urlencode(dict(username='user',password='test-password')))
    assert status in [302,303],(status,body)
    session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
    def cards():return client.command({'find':'cards','filter':dict(boardId=board)})['cursor']['firstBatch']
    def snapshot():
        result=[]
        for name in ['boards','cards','customFields','activities']:
            condition=dict(_id=board) if name=='boards' else dict(_id=field) if name=='customFields' else dict(boardId=board)
            rows=client.command({'find':name,'filter':condition})['cursor']['firstBatch']
            result.append([encode(row) for row in sorted(rows,key=lambda row:row['_id'])])
        return result
    def clone(expected):
        status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)))
        assert status==200,(status,body)
        parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
        before=snapshot();old={row['_id'] for row in cards()};original=encode(client.find('cards',cid)[0])
        status,_,body=request('POST','/board/move',urlencode(dict(form,action='clone',sel_card=cid)))
        assert status==expected,(expected,status,body)
        assert encode(client.find('cards',cid)[0])==original
        if expected!=302:assert snapshot()==before;return
        added=[row for row in cards() if row['_id'] not in old];assert len(added)==1,added
        assert added[0]['customFields']==client.find('cards',cid)[0]['customFields'],added
    try:
        clone(302)
        for flag in ['readOnly','adminOnly']:
            update('customFields',field,{flag:True});clone(403);update('customFields',field,{flag:False})
        update('users',uid,dict(isAdmin=True));update('customFields',field,dict(readOnly=True));clone(403)
        update('users',uid,dict(isAdmin=False))
        update('cards',cid,dict(customFields=[dict(_id=field,value=None)]));clone(302)
        update('cards',cid,dict(customFields=[dict(_id=field,value='original')]));role(True);clone(302)
        role(False);update('customFields',field,dict(readOnly=False))
        # History is not copied, so unreadable old activity data does not block a clone.
        assert client.command({'insert':'activities','documents':[dict(_id='clone-old-history',activityType='setCustomField',boardId=board,cardId=cid,createdAt=DateMs(0),customFieldId='deleted-field',oldValue='not copied')]})['n']==1
        clone(302)
        with sqlite3.connect(db) as con:tables={name:'"'+table.replace('"','""')+'"' for name,table in con.execute('SELECT name,table_name FROM _ferretdb_collections')}
        for mutation in ["UPDATE "+tables['customFields']+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.readOnly',json('true')) WHERE json_extract(_ferretdb_sjson,'$._id')='clone-field';",
                         "UPDATE "+tables['boards']+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.members[0].isActive',json('false')) WHERE json_extract(_ferretdb_sjson,'$._id')='clone-policy';"]:
            with sqlite3.connect(db) as con:con.execute('CREATE TRIGGER clone_policy AFTER INSERT ON '+tables['activities']+" WHEN json_extract(NEW._ferretdb_sjson,'$.activityType')='clone' AND json_extract(NEW._ferretdb_sjson,'$.boardId')='clone-policy' BEGIN "+mutation+' END')
            try:clone(500)
            finally:
                with sqlite3.connect(db) as con:con.execute('DROP TRIGGER clone_policy')
        update('customFields',field,dict(readOnly=True));update('cards',cid,dict(customFields=[dict(_id=field,value=None)]))
        with sqlite3.connect(db) as con:
            con.execute('CREATE TRIGGER clone_policy AFTER UPDATE ON '+tables['cards']+" WHEN json_extract(NEW._ferretdb_sjson,'$._id')<>'clone-original' AND json_extract(NEW._ferretdb_sjson,'$.boardId')='clone-policy' AND json_type(NEW._ferretdb_sjson,'$.customFields[0].value')='null' BEGIN UPDATE "+tables['cards']+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.customFields[0].value','Injected protected value','$.\"$s\".p.customFields.i[0].\"$s\".p.value.t','string') WHERE json_extract(_ferretdb_sjson,'$._id')=json_extract(NEW._ferretdb_sjson,'$._id'); END")
        try:clone(500)
        finally:
            with sqlite3.connect(db) as con:con.execute('DROP TRIGGER clone_policy')
        print('PASS: shared HTML clone ordinary/protected/null/admin boundaries, ignored uncopied history, role/flag revocation, injected destination values and exact source/transaction rollback')
    finally:
        operation={'$set':dict(isAdmin=original_user['isAdmin'])} if 'isAdmin' in original_user else {'$unset':dict(isAdmin='')}
        assert client.command({'update':'users','updates':[dict(q=dict(_id=uid),u=operation)]})['n']==1

"""Shared HTML clone permissions and transaction-time field/role changes."""
import json
import copy
import sqlite3
from urllib.parse import urlencode,parse_qs,urlsplit
from layout import Forms
from clroots import run as check_root_presence
from wire import DateMs,Long,Binary,ObjectId,Timestamp,Regex,encode


def run_shared(request,client,db,token):
    uid='u';board='clone-policy';cid='clone-original';field='clone-field'
    original_user=client.find('users',uid)[0]
    opaque=dict(boardId=DateMs(0),_wl_source='literal source text',other_json='ordinary text',date=DateMs(-7),long=Long(9007199254740993),binary=Binary(bytes(range(16)),4),oid=ObjectId(bytes(range(12))),timestamp=Timestamp(2**63+3),regex=Regex('漢.*','im'),zero=-0.0,nan=float('nan'),infinity=float('inf'),array=[DateMs(0),Long(7),Binary(b'keep',128)],nullable=None)
    def update(collection,identity,changes):
        assert client.command({'update':collection,'updates':[dict(q=dict(_id=identity),u={'$set':changes})]})['n']==1
    def role(admin):update('boards',board,dict(members=[dict(userId=uid,isActive=True,isAdmin=admin)]))
    assert client.command({'insert':'boards','documents':[dict(_id=board,title=board,slug=board,permission='private',members=[dict(userId=uid,isActive=True,isAdmin=False)])]})['n']==1
    assert client.command({'insert':'lists','documents':[dict(_id='clone-list',boardId=board,title='Clone')]})['n']==1
    assert client.command({'insert':'customFields','documents':[dict(_id=field,name='Clone field',type='text',boardIds=[board],adminOnly=False,readOnly=False)]})['n']==1
    assert client.command({'insert':'cards','documents':[dict(_id=cid,boardId=board,listId='clone-list',userId=uid,title='Clone card',opaque=opaque,createdAt=DateMs(0),modifiedAt=DateMs(0),dateLastActivity=DateMs(0),customFields=[dict(_id=field,value='original')])]})['n']==1
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
        before=snapshot();old={row['_id'] for row in cards()};source_card=client.find('cards',cid)[0];original=encode(source_card)
        status,_,body=request('POST','/board/move',urlencode(dict(form,action='clone',sel_card=cid)))
        assert status==expected,(expected,status,body)
        assert encode(client.find('cards',cid)[0])==original
        if expected!=302:assert snapshot()==before;return
        added=[row for row in cards() if row['_id'] not in old];assert len(added)==1,added
        for name in ['members','assignees','labelIds','customFields','cardDependencies']:
            assert (name in added[0])==(name in source_card),(name,added[0],source_card)
            if name not in source_card:continue
            value=copy.deepcopy(source_card[name])
            if name=='cardDependencies' and isinstance(value,list):
                for entry in value:
                    if entry['cardId']==cid:entry['cardId']=added[0]['_id']
            assert encode(dict(value=added[0][name]))==encode(dict(value=value)),(name,added[0],source_card)

        deliberate={'_id','title','createdAt','modifiedAt','dateLastActivity','sort','cardNumber','members','assignees','labelIds','customFields','cardDependencies'}
        for name in (set(source_card)|set(added[0]))-deliberate:
            assert (name in added[0])==(name in source_card),(name,added[0],source_card)
            value=source_card[name]
            if name in ['parentId','linkedId'] and type(value) is str and value==cid:value=added[0]['_id']
            assert encode(dict(value=added[0][name]))==encode(dict(value=value)),(name,added[0],source_card)
        assert encode(added[0]['opaque'])==encode(source_card['opaque']),{key:(encode(dict(value=value)).hex(),encode(dict(value=added[0]['opaque'][key])).hex()) for key,value in source_card['opaque'].items() if encode(dict(value=value))!=encode(dict(value=added[0]['opaque'][key]))}
        return added[0]
    try:
        clone(302)
        update('cards',cid,dict(identifierProbe=dict(customFieldId=Regex(field,''),value='Typed identifier must not grant access')))
        clone(403)
        update('cards',cid,dict(identifierProbe=None));clone(302)
        update('cards',cid,dict(typedMarker=dict(field=Regex('customFields',''),value=[dict(_id='deleted-field',value='Literal typed marker data')])));clone(302)
        update('cards',cid,dict(customFields=[dict(_id=Regex(field,''),value='Typed orphan custom value')]))
        clone(403)
        api='/api/boards/'+board+'/lists/clone-list/cards/'+cid
        status,_,body=request('GET',api,token=token);assert status==200,(status,body)
        assert json.loads(body)['customFields'][0]['value'] is None,body
        before=snapshot();assert request('POST',api+'/customFields/'+field,dict(value='attack'),token)[0]==403;assert snapshot()==before
        update('cards',cid,dict(customFields=[dict(_id=field,value='original')]))

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
        for mutation in ["UPDATE _wl_models SET version=version+1 WHERE name='cards';",
                         "UPDATE _ferretdb_collections SET settings=json_set(settings,'$.uuid','changed-clone-epoch') WHERE name='cards';",
                         "UPDATE "+tables['customFields']+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.readOnly',json('true')) WHERE json_extract(_ferretdb_sjson,'$._id')='clone-field';",
                         "UPDATE "+tables['boards']+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.members[0].isActive',json('false')) WHERE json_extract(_ferretdb_sjson,'$._id')='clone-policy';"]:
            with sqlite3.connect(db) as con:con.execute('CREATE TRIGGER clone_policy AFTER INSERT ON '+tables['activities']+" WHEN json_extract(NEW._ferretdb_sjson,'$.activityType')='clone' AND json_extract(NEW._ferretdb_sjson,'$.boardId')='clone-policy' BEGIN "+mutation+' END')
            with sqlite3.connect(db) as con:binding_before=con.execute("SELECT m.*,c.settings FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name WHERE m.name='cards'").fetchone()
            try:
                clone(500)
                with sqlite3.connect(db) as con:assert con.execute("SELECT m.*,c.settings FROM _wl_models m JOIN _ferretdb_collections c ON c.table_name=m.table_name WHERE m.name='cards'").fetchone()==binding_before
            finally:
                with sqlite3.connect(db) as con:con.execute('DROP TRIGGER clone_policy')
        update('customFields',field,dict(readOnly=True));update('cards',cid,dict(customFields=[dict(_id=field,value=None)]))
        with sqlite3.connect(db) as con:
            con.execute('CREATE TRIGGER clone_policy AFTER UPDATE ON '+tables['cards']+" WHEN json_extract(NEW._ferretdb_sjson,'$._id')<>'clone-original' AND json_extract(NEW._ferretdb_sjson,'$.boardId')='clone-policy' AND json_type(NEW._ferretdb_sjson,'$.customFields[0].value')='null' BEGIN UPDATE "+tables['cards']+" SET _ferretdb_sjson=jsonb_set(_ferretdb_sjson,'$.customFields[0].value','Injected protected value','$.\"$s\".p.customFields.i[0].\"$s\".p.value.t','string') WHERE json_extract(_ferretdb_sjson,'$._id')=json_extract(NEW._ferretdb_sjson,'$._id'); END")
        try:clone(500)
        finally:
            with sqlite3.connect(db) as con:con.execute('DROP TRIGGER clone_policy')
        with sqlite3.connect(db) as con:
            model=con.execute("SELECT * FROM _wl_models WHERE name='cards'").fetchone()
            con.execute("DELETE FROM _wl_models WHERE name='cards'")
        try:clone(500)
        finally:
            with sqlite3.connect(db) as con:con.execute('INSERT INTO _wl_models VALUES(?,?,?,?)',model)
        update('customFields',field,dict(readOnly=False))
        # Stored values retain BSON identity even when today's definition is text.
        for value in [DateMs(-7),Long(9007199254740993),True,['one','two'],Binary(b'row metadata',128),Timestamp(2**63+7),Regex('漢.*','im'),-0.0,float('nan')]:
            update('cards',cid,dict(customFields=[dict(_id=field,value=value,unknown=opaque)]));clone(302)
        for value in [None,[],[dict(_id=field)],[dict(_id=field,value=None)]]:
            update('cards',cid,dict(customFields=value));clone(302)
        assert client.command({'update':'cards','updates':[dict(q=dict(_id=cid),u={'$unset':{'customFields':''}})]})['n']==1
        clone(302)
        update('cards',cid,dict(customFields=[dict(_id=field,value='original')],members=['u','external-user'],assignees=[],labelIds=None,cardDependencies=[dict(cardId=cid,type='related-to',unknown=opaque),dict(cardId='external-card',unknown=opaque)]));clone(302)
        update('cards',cid,dict(members=['u','u']));clone(500)
        update('cards',cid,dict(members=[Regex('u','')]));clone(500)
        update('cards',cid,dict(members=['u','external-user'],customFields=[dict(_id=field,value=None,unknown=dict(customFieldId='deleted-field',value='Hidden relation metadata'))]));clone(403)
        update('cards',cid,dict(customFields=[dict(_id=field,value='original')]))
        update('cards',cid,dict(userId=None,type=None,archived=None,description=None,requestedBy=Long(9007199254740993),spentTime=-0.0,endAt=DateMs(-9223372036854775808),parentId=Regex(cid,'')));clone(302)
        # A child selected through the parent graph remaps forward/back references.
        child='clone-child'
        assert client.command({'insert':'cards','documents':[dict(_id=child,boardId=board,listId='clone-list',parentId=cid,title='Clone child',cardDependencies=[dict(cardId=cid,type='related-to',unknown=opaque)])]})['n']==1
        update('cards',cid,dict(cardDependencies=[dict(cardId=child,type='related-to',unknown=opaque)]))
        status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
        parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
        old={row['_id'] for row in cards()};originals={key:encode(client.find('cards',key)[0]) for key in [cid,child]}
        status,_,body=request('POST','/board/move',urlencode(dict(form,action='clone',sel_card=cid)));assert status==302,(status,body)
        added=[row for row in cards() if row['_id'] not in old];assert len(added)==2,added
        parent_copy=next(row for row in added if row['title']=='Clone card Copy');child_copy=next(row for row in added if row['title']=='Clone child')
        assert child_copy['parentId']==parent_copy['_id'] and 'userId' not in child_copy and 'type' not in child_copy
        assert parent_copy['cardDependencies'][0]['cardId']==child_copy['_id']
        assert child_copy['cardDependencies'][0]['cardId']==parent_copy['_id']
        for row in added:
            assert encode(row['cardDependencies'][0]['unknown'])==encode(client.find('cards',cid)[0]['cardDependencies'][0]['unknown'])
        assert all(encode(client.find('cards',key)[0])==value for key,value in originals.items())
        check_root_presence(request,client,db,board,session)
        print('PASS: shared cloned typed managed values/metadata/presence and selected/external dependency remapping')
        print('PASS: shared cloned unknown root BSON types/bits/order and missing ownership refusal')
        print('PASS: shared HTML clone ordinary/protected/null/admin boundaries, ignored uncopied history, role/flag revocation, injected destination values and exact source/transaction rollback')
    finally:
        operation={'$set':dict(isAdmin=original_user['isAdmin'])} if 'isAdmin' in original_user else {'$unset':dict(isAdmin='')}
        assert client.command({'update':'users','updates':[dict(q=dict(_id=uid),u=operation)]})['n']==1

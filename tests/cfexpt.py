"""Selection exports cannot narrow away unreadable values elsewhere on a board."""
import json
import sqlite3
from urllib.parse import urlencode
from layout import Forms
from wire import DateMs,Long,Binary,Regex,encode


def run_shared(request,client,db):
    uid='u';board='export-policy';cid='export-visible';hidden='export-hidden';field='export-field'
    user=client.find('users',uid)[0]
    def update(collection,identity,changes):
        assert client.command({'update':collection,'updates':[dict(q=dict(_id=identity),u={'$set':changes})]})['n']==1
    assert client.command({'insert':'boards','documents':[dict(_id=board,title=board,slug=board,permission='private',members=[dict(userId=uid,isActive=True,isAdmin=False)])]})['n']==1
    assert client.command({'insert':'lists','documents':[dict(_id='export-list',boardId=board,title='Export')]})['n']==1
    assert client.command({'insert':'customFields','documents':[dict(_id=field,name='Private',type='text',boardIds=[board],adminOnly=True)]})['n']==1
    assert client.command({'insert':'cards','documents':[dict(_id=cid,title='Selected',boardId=board,listId='export-list'),dict(_id=hidden,title='Outside selection',boardId=board,listId='export-list',customFields=[dict(_id=field,value='EXPORT PRIVATE SECRET')])]})['n']==2
    status,headers,body=request('POST','/sign-in',urlencode(dict(username='user',password='test-password')))
    assert status in [302,303],(status,body)
    location=headers['Location']
    from urllib.parse import parse_qs,urlsplit
    session=parse_qs(urlsplit(location).query)['sessionId'][0]
    def snapshot():return [encode(client.find(name,identity)[0]) for name,identity in [('boards',board),('cards',cid),('cards',hidden),('customFields',field)]]+[encode(row) for row in client.find('activities','export-activity')]
    def export(expected):
        status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)))
        assert status==200,(status,body)
        parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
        before=snapshot();status,headers,body=request('POST','/board/move',urlencode(dict(form,action='export',sel_card=cid)))
        assert status==expected,(expected,status,body)
        assert snapshot()==before
        if expected>=400:
            assert 'Content-Disposition' not in headers and b'EXPORT PRIVATE SECRET' not in body and b'_wl_source' not in body
        else:
            exported=json.loads(body)
            assert set(exported)=={'welite_selection','boardId','data','files'},exported.keys()
            assert [row['id'] for row in exported['data']['cards']]==[cid]
            assert all(row.get('_wl_source') is None for rows in exported['data'].values() for row in rows),exported
        return body
    try:
        export(403)
        update('customFields',field,dict(adminOnly=False,readOnly=True));export(200)
        update('customFields',field,dict(adminOnly=DateMs(8640000000000001)));export(403)
        update('customFields',field,dict(adminOnly=float('nan')));export(403)
        update('customFields',field,dict(adminOnly=None));export(200)
        update('customFields',field,dict(adminOnly=True));update('users',uid,dict(isAdmin=True));export(403)
        update('boards',board,dict(members=[dict(userId=uid,isActive=True,isAdmin=True)]));export(200)
        update('customFields',field,dict(boardIds=[]));export(403)
        update('cards',hidden,dict(customFields=[dict(_id=field,value=DateMs(8640000000000001))]));export(403)
        update('cards',hidden,dict(customFields=[dict(_id=field,value=None)]));export(200)
        update('customFields',field,dict(boardIds=[board]));update('boards',board,dict(members=[dict(userId=uid,isActive=True,isAdmin=False)]));export(403)
        update('customFields',field,dict(adminOnly=False))
        activity=dict(_id='export-activity',activityType='setCustomField',boardId=board,cardId=cid,createdAt=DateMs(0),customFieldId='deleted-field',oldValue=DateMs(-7),unknown=Long(9007199254740993),binary=Binary(b'preserve',4))
        assert client.command({'insert':'activities','documents':[activity]})['n']==1
        export(403)
        update('activities','export-activity',dict(customFieldId=field));export(200)
        update('activities','export-activity',dict(field='customFields',oldValue=[dict(_id='deleted-field',value='OLD BATCH PRIVATE SECRET')])) ;export(403)
        update('activities','export-activity',dict(field=None,oldValue=DateMs(-7)));export(200)
        update('activities','export-activity',dict(integrityHash='ACTIVITY PRIVATE HASH'));export(403)
        update('boards',board,dict(members=[dict(userId=uid,isActive=True,isAdmin=True)]));export(200)
        update('activities','export-activity',dict(integrityHash=None))
        update('boards',board,dict(members=[dict(userId=uid,isActive=True,isAdmin=False)]))
        update('cards',cid,dict(unknownPayload=dict(customFields=[dict(_id='deleted-field',value='EMBEDDED PRIVATE SECRET')])));export(403)
        update('cards',cid,dict(unknownPayload=dict(customFields=[dict(_id=field,value='Readable embedded value')])));export(200)
        # Regex patterns are rendered as strings by plain SQL projections; they
        # must never acquire canonical identifier or activity-marker authority.
        update('cards',cid,dict(unknownPayload=dict(customFields=[dict(_id=Regex(field,''),value='Typed orphan secret')])));export(403)
        update('cards',cid,dict(unknownPayload=dict(boardId=Regex(board,''),customFieldId=field,value='Typed board secret')));export(403)
        update('cards',cid,dict(unknownPayload=dict(field=Regex('customFields',''),value=[dict(_id='deleted-field',value='Literal marker data')],_wl_source='literal data',other_json='ordinary string')));export(200)
        update('cards',cid,dict(unknownPayload=None))
        update('activities','export-activity',dict(customFieldId=Regex(field,'')));export(403)
        update('activities','export-activity',dict(customFieldId=field));export(200)
        update('activities','export-activity',dict(field=Regex('customFields',''),oldValue=[dict(_id='deleted-field',value='Literal activity marker')]));export(200)
        update('activities','export-activity',dict(field=None,oldValue=DateMs(-7)))
        update('cards',cid,dict(customFields=[dict(_id=field,value='Readable assignment')]))
        update('customFields',field,dict(unknownPayload=dict(customFieldId=Regex(field,''),value='Definition typed secret')));export(403)
        update('customFields',field,dict(unknownPayload=None));export(200)
        with sqlite3.connect(db) as con:
            model=con.execute("SELECT * FROM _wl_models WHERE name='activities'").fetchone()
            con.execute("DELETE FROM _wl_models WHERE name='activities'")
        try:export(500)
        finally:
            with sqlite3.connect(db) as con:con.execute('INSERT INTO _wl_models VALUES(?,?,?,?)',model)
        export(200)
        print('PASS: typed export identifier/marker identity, literal source keys, unchanged public format and exact source BSON')
        print('PASS: shared activity/nested JSON export checks, readable history, hash administration and exact Date/Long/Binary source preservation')
        print('PASS: shared HTML selection export gates whole-board private/orphan values, unassigned definitions and site-admin bypass; readable/read-only/admin/null exports retain selected scope')
    finally:
        operation={'$set':dict(isAdmin=user['isAdmin'])} if 'isAdmin' in user else {'$unset':dict(isAdmin='')}
        assert client.command({'update':'users','updates':[dict(q=dict(_id=uid),u=operation)]})['n']==1

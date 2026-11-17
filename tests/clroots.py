"""Live lane-root clones retain mapped presence across all seven root models."""
import copy
import json
from urllib.parse import urlencode
from layout import Forms
from paths import stored
from wire import DateMs,Long,Regex,ObjectId,encode

def run(request,client,db,board,session):
    records={
        'swimlanes':dict(_id='presence-lane',boardId=board,title='Presence lane',color=None),
        'lists':dict(_id='presence-list',boardId=board,swimlaneId='presence-lane',title='Presence list',wipLimit=dict(enabled=None,value=Long(7),soft=True,opaque=DateMs(-7))),
        'cards':dict(_id='presence-card',boardId=board,listId='presence-list',swimlaneId='presence-lane',title=None,archived=None,spentTime=-0.0),
        'checklists':dict(_id='presence-check',cardId='presence-card',title=None),
        'checklistItems':dict(_id='presence-item',cardId='presence-card',checklistId='presence-check',title=None,isFinished=None),
        'card_comments':dict(_id='presence-comment',boardId=board,cardId='presence-card',userId=None),
        'attachments':dict(_id='presence-file',name=None,meta=dict(boardId=board,cardId='presence-card',listId='presence-list',swimlaneId='presence-lane',opaque=DateMs(-7)))
    }
    for collection,record in records.items():assert client.command({'insert':collection,'documents':[record]})['n']==1
    decoys=[
        ('lists',dict(_id='scope-list',boardId=board,swimlaneId=Regex('presence-lane',''),title='Unrelated lane lookalike')),
        ('lists',dict(_id='scope-list-board',boardId=Regex(board,''),swimlaneId='presence-lane',title='Unrelated board lookalike')),
        ('cards',dict(_id='scope-card-list',boardId=board,listId=Regex('presence-list',''),title='Unrelated list lookalike')),
        ('cards',dict(_id='scope-card-lane',boardId=board,swimlaneId=Regex('presence-lane',''),title='Unrelated lane lookalike')),
        ('cards',dict(_id='scope-card-board',boardId=Regex(board,''),listId='presence-list',title='Unrelated board lookalike')),
        ('checklists',dict(_id='scope-check',cardId=Regex('presence-card',''),title='Unrelated card lookalike')),
        ('checklistItems',dict(_id='scope-item',checklistId=Regex('presence-check',''),title='Unrelated checklist lookalike')),
        ('card_comments',dict(_id='scope-comment',boardId=board,cardId=Regex('presence-card',''),text='Unrelated comment')),
        ('attachments',dict(_id='scope-file',meta=dict(boardId=board,cardId=Regex('presence-card','')))),
        ('attachments',dict(_id='scope-file-board',meta=dict(boardId=Regex(board,''),cardId='presence-card'))),
        ('activities',dict(_id='scope-history',boardId=board,cardId=Regex('presence-card',''),activityType='test')),
        ('activities',dict(_id='scope-history-board',boardId=Regex(board,''),cardId='presence-card',activityType='test')),
        ('lists',dict(_id=ObjectId(bytes.fromhex('00112233445566778899aabb')),boardId=board,title='Nonstring root identity')),
    ]
    histories=[dict(_id='presence-history',boardId=board,cardId='presence-card',activityType='test'),
               dict(_id='presence-history-fallback',boardId=board,cardId=Regex('presence-card',''),listId='presence-list',activityType='test')]
    for collection,record in decoys+[('activities',row) for row in histories]:assert client.command({'insert':collection,'documents':[record]})['n']==1
    for identity in ['scope-file','scope-file-board']:
        fake=stored(db,identity);fake.parent.mkdir(parents=True,exist_ok=True);fake.write_bytes(b'unrelated bytes')
    path=stored(db,'presence-file');path.parent.mkdir(parents=True,exist_ok=True);payload=b'presence attachment\0\xff';path.write_bytes(payload)
    def rows(collection):return client.command({'find':collection,'filter':{},'batchSize':10000})['cursor']['firstBatch']
    sources=[(name,row['_id']) for name,row in records.items()]+[(name,row['_id']) for name,row in decoys]+[('activities',row['_id']) for row in histories]
    unchanged={(name,str(identity)):encode(client.find(name,identity)[0]) for name,identity in sources}
    def export(selection,expected):
        status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
        parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
        status,headers,body=request('POST','/board/move',urlencode(dict(form,action='export',**selection)),timeout=30);assert status==expected,(status,body)
        assert all(encode(client.find(name,identity)[0])==unchanged[name,str(identity)] for name,identity in sources)
        if expected!=200:
            assert 'Content-Disposition' not in headers;return
        data=json.loads(body)
        for collection,row in records.items():
            table='checklist_items' if collection=='checklistItems' else collection
            assert [entry['id'] for entry in data['data'][table]]==[row['_id']],('Nonstring scope widened export',table,data['data'][table])
        assert {row['id'] for row in data['data']['activities']}=={row['_id'] for row in histories}
        assert [row['id'] for row in data['files']]==['presence-file']
    export(dict(sel_swimlane='presence-lane'),200)
    export(dict(sel_list='00112233445566778899aabb'),400)
    # Raw edit/save parameters must not bypass graph filtering when mixed with
    # a valid root: reject the entire request before rendering or mutation.
    for action in ['edit','save']:
        status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
        parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
        values=dict(form,action=action,**{'title_list_presence-list':'Changed','color_list_presence-list':'blue','title_list_scope-list-board':'Wrong','color_list_scope-list-board':'blue'})
        status,_,body=request('POST','/board/move',urlencode(list(values.items())+[('sel_list','presence-list'),('sel_list','scope-list-board')]))
        assert status==400 and b'Unrelated board lookalike' not in body,(action,status,body)
        assert all(encode(client.find(name,identity)[0])==unchanged[name,str(identity)] for name,identity in sources)

    before={name:{row['_id'] for row in rows(name)} for name in records}
    originals={name:client.find(name,row['_id'])[0] for name,row in records.items()}
    status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
    parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
    status,_,body=request('POST','/board/move',urlencode(dict(form,action='clone',sel_swimlane='presence-lane')));assert status==302,(status,body)
    copies={}
    for name in records:
        added=[row for row in rows(name) if row['_id'] not in before[name]];assert len(added)==1,(name,added)
        copies[name]=added[0]
        assert encode(client.find(name,records[name]['_id'])[0])==encode(originals[name]),name
    expected=copy.deepcopy(originals)
    expected['lists']['swimlaneId']=copies['swimlanes']['_id']
    expected['cards'].update(listId=copies['lists']['_id'],swimlaneId=copies['swimlanes']['_id'])
    for name in ['checklists','checklistItems','card_comments']:expected[name]['cardId']=copies['cards']['_id']
    expected['checklistItems']['checklistId']=copies['checklists']['_id']
    expected['attachments']['meta'].update(cardId=copies['cards']['_id'],listId=copies['lists']['_id'],swimlaneId=copies['swimlanes']['_id'])
    for name,record in copies.items():
        changed={'_id','sort','cardNumber','createdAt','modifiedAt','dateLastActivity'}
        if name=='swimlanes':
            assert record['title']==originals[name]['title']+' Copy';changed.add('title')
        for key in (set(record)|set(expected[name]))-changed:
            assert (key in record)==(key in expected[name]),(name,key,record,expected[name])
            assert encode(dict(value=record[key]))==encode(dict(value=expected[name][key])),(name,key,record,expected[name])
    assert stored(db,copies['attachments']['_id']).read_bytes()==payload and path.read_bytes()==payload
    assert all(encode(client.find(name,row['_id'])[0])==unchanged[name,str(row['_id'])] for name,row in decoys)
    for identity in ['scopeCase','SCOPECASE']:
        assert client.command({'insert':'cards','documents':[dict(_id=identity,boardId=board,listId='presence-list',title=identity)]})['n']==1
    status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
    parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
    status,_,body=request('POST','/board/move',urlencode(dict(form,action='export',sel_list='presence-list')),timeout=30);assert status==200,(status,body)
    assert {row['id'] for row in json.loads(body)['data']['cards']}=={'presence-card','scopeCase','SCOPECASE'}
    before_cards={row['_id'] for row in rows('cards')}
    status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200
    parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1]
    status,_,body=request('POST','/board/move',urlencode(list(dict(form,action='clone').items())+[('sel_card','scopeCase'),('sel_card','SCOPECASE')]));assert status==302,(status,body)
    added=[row for row in rows('cards') if row['_id'] not in before_cards]
    assert len(added)==2 and {row['title'] for row in added}=={'scopeCase Copy','SCOPECASE Copy'},added
    print('PASS: shared explicit and expanded selection IDs preserve exact case')
    print('PASS: typed root scope excludes lane/list/card/checklist/comment/file/history lookalikes, retains valid OR branches and refuses nonstring roots')
    print('PASS: all seven shared clone roots retain mapped BSON/presence, nested null/unknown data, references and attachment bytes')

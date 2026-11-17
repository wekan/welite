"""Live lane-root clones retain mapped presence across all seven root models."""
import copy
from urllib.parse import urlencode
from layout import Forms
from paths import stored
from wire import DateMs,Long,encode

def run(request,client,db,board,session):
    records={
        'swimlanes':dict(_id='presence-lane',boardId=board,title='Presence lane',color=None),
        'lists':dict(_id='presence-list',boardId=board,swimlaneId='presence-lane',title='Presence list',wipLimit=dict(enabled=None,value=Long(7),soft=True,opaque=DateMs(-7))),
        'cards':dict(_id='presence-card',boardId=board,listId='presence-list',swimlaneId='presence-lane',title=None,archived=None,spentTime=-0.0),
        'checklists':dict(_id='presence-check',boardId=board,cardId='presence-card',title=None),
        'checklistItems':dict(_id='presence-item',boardId=board,cardId='presence-card',checklistId='presence-check',title=None,isFinished=None),
        'card_comments':dict(_id='presence-comment',boardId=board,cardId='presence-card',userId=None),
        'attachments':dict(_id='presence-file',name=None,meta=dict(boardId=board,cardId='presence-card',listId='presence-list',swimlaneId='presence-lane',opaque=DateMs(-7)))
    }
    for collection,record in records.items():assert client.command({'insert':collection,'documents':[record]})['n']==1
    path=stored(db,'presence-file');path.parent.mkdir(parents=True,exist_ok=True);payload=b'presence attachment\0\xff';path.write_bytes(payload)
    def rows(collection):return client.command({'find':collection,'filter':{}})['cursor']['firstBatch']
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
    print('PASS: all seven shared clone roots retain mapped BSON/presence, nested null/unknown data, references and attachment bytes')

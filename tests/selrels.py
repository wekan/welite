"""Live selection relations cannot turn nonstring BSON keys into string authority."""
import json
import sqlite3
from urllib.parse import urlencode,urlsplit,parse_qs
from layout import Forms
from wire import Regex,encode

def run_shared(request,client,db):
    board='relation-scope';card='relation-card';field='relation-field';badfield='relation-board-bad'
    labels=[dict(_id='label-good',name='Good',color='blue'),dict(_id=Regex('label-decoy',''),name='Typed lookalike',color='red')]
    dropdown=[dict(_id='choice-good',name='Good'),dict(_id=Regex('choice-bad',''),name='Typed lookalike')]
    record=dict(_id=card,boardId=board,listId='relation-list',title='Relation card',members=['u',Regex('member-bad','')],assignees=['assigned-good',Regex('assignee-bad','')],labelIds=['label-good','label-decoy',Regex('label-key-bad','')],customFields=[dict(_id=field,value=None),dict(_id=badfield,value=None)],cardDependencies=[dict(cardId='dep-good'),dict(cardId='dep-null',type=None),dict(cardId=Regex('dep-bad',''),type='related-to'),dict(cardId='dep-type-bad',type=Regex('related-to',''))])
    for collection,documents in [
        ('boards',[dict(_id=board,title=board,slug=board,permission='private',members=[dict(userId='u',isActive=True,isAdmin=True)],labels=labels)]),
        ('lists',[dict(_id='relation-list',boardId=board,title='Relations')]),
        ('customFields',[dict(_id=field,name='Field',type='text',boardIds=[board,Regex('relation-board-extra','')],adminOnly=False,settings=dict(dropdownItems=dropdown)),dict(_id=badfield,name='Wrong board type',type='text',boardIds=[Regex(board,'')],adminOnly=False)]),
        ('cards',[record])]:
        assert client.command({'insert':collection,'documents':documents})['n']==len(documents)
    status,headers,body=request('POST','/sign-in',urlencode(dict(username='user',password='test-password')));assert status in [302,303],(status,body)
    session=parse_qs(urlsplit(headers['Location']).query)['sessionId'][0]
    def update(collection,identity,changes):
        assert client.command({'update':collection,'updates':[dict(q=dict(_id=identity),u={'$set':changes})]})['n']==1
    def snapshot():
        result=[]
        for collection,condition in [('boards',dict(_id=board)),('cards',dict(boardId=board)),('customFields',dict(_id={'$in':[field,badfield]})),('activities',dict(boardId=board))]:
            rows=client.command({'find':collection,'filter':condition})['cursor']['firstBatch']
            result.append([encode(row) for row in sorted(rows,key=lambda row:row['_id'])])
        with sqlite3.connect(db) as con:result.append(con.execute("SELECT * FROM _wl_models WHERE name='card_labels'").fetchall())
        return result
    def action(name,expected):
        status,_,body=request('GET','/board?'+urlencode(dict(id=board,sessionId=session)));assert status==200,(status,body)
        parser=Forms();parser.feed(body.decode());form=parser.forms[-1][1];before=snapshot()
        status,headers,body=request('POST','/board/move',urlencode(dict(form,action=name,sel_card=card)),timeout=30)
        assert status==expected,(name,status,body)
        if name=='export' or expected!=302:assert snapshot()==before,'Selection changed source BSON or failed rollback'
        if name=='export' and expected==200:return json.loads(body)['data']
        assert 'Content-Disposition' not in headers,(name,headers)
    data=action('export',200)
    assert [row['id'] for row in data['board_labels']]==['label-good'],data['board_labels']
    assert [row['id'] for row in data['custom_fields']]==[field],data['custom_fields']
    assert [(row['customFieldId'],row['boardId']) for row in data['custom_field_boards']]==[(field,board)],data['custom_field_boards']
    assert [row['id'] for row in data['custom_field_dropdown_items']]==['choice-good'],data['custom_field_dropdown_items']
    assert [row['userId'] for row in data['card_members']]==['u'],data['card_members']
    assert [row['userId'] for row in data['card_assignees']]==['assigned-good'],data['card_assignees']
    assert {row['labelId'] for row in data['card_labels']}=={'label-good','label-decoy'},data['card_labels']
    assert {row['customFieldId'] for row in data['card_custom_field_values']}=={field,badfield},data['card_custom_field_values']
    assert {(row['targetCardId'],row['type']) for row in data['card_dependencies']}=={('dep-good','related-to'),('dep-null','related-to')},data['card_dependencies']
    update('boards',board,dict(labels=[labels[0],dict(_id=Regex('label-good',''),name='Shadow',color='red')]))
    action('export',500);update('boards',board,dict(labels=labels))
    update('cards',card,dict(members=['u',Regex('u','')]))
    action('edit',200)
    action('export',500);update('cards',card,dict(members=record['members']))
    update('customFields',field,dict(settings=dict(dropdownItems=[dropdown[0],dict(_id=Regex('choice-good',''),name='Shadow')])))
    action('export',500);update('customFields',field,dict(settings=dict(dropdownItems=dropdown)))
    action('export',200)
    # Valid managed references still copy exactly, including missing/null type defaults.
    update('cards',card,dict(members=['u','member-good'],assignees=['assigned-good'],labelIds=['label-good','label-decoy'],cardDependencies=record['cardDependencies'][:2]))
    original_card=client.find('cards',card)[0];original=encode(original_card)
    old={row['_id'] for row in client.command({'find':'cards','filter':dict(boardId=board)})['cursor']['firstBatch']}
    action('clone',302)
    added=[row for row in client.command({'find':'cards','filter':dict(boardId=board)})['cursor']['firstBatch'] if row['_id'] not in old]
    assert len(added)==1,added
    for name in ['members','assignees','labelIds','customFields','cardDependencies']:
        assert encode(dict(value=added[0][name]))==encode(dict(value=original_card[name])),name
    assert encode(client.find('cards',card)[0])==original
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER selection_relation_epoch INSTEAD OF INSERT ON activities BEGIN UPDATE _wl_models SET version=version+1 WHERE name='card_labels'; END;")
    try:action('clone',500)
    finally:
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER selection_relation_epoch')
    print('PASS: live typed embedded selection keys exclude lookalikes, retain null/default dependencies, reject duplicate shadows, preserve BSON and roll back relation epoch changes')

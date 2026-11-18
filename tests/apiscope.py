"""Called by admin.py against its isolated running server."""
import json
import re
from pathlib import Path
import sqlite3

def run(request, db, token):
    with sqlite3.connect(db) as con:
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('otherboard','Other','other','now')")
        con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES('foreignlane','otherboard','Foreign lane',0,'now')")
        con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,createdAt) VALUES('foreignlist','otherboard','foreignlane','Foreign list','now')")
        con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,userId,createdAt,modifiedAt,dateLastActivity) VALUES('foreigncard','otherboard','foreignlist','foreignlane','u','now','now','now')")
        for cid, card, board in [('check','card','protected'), ('foreigncheck','foreigncard','otherboard')]:
            con.execute("INSERT INTO checklists(id,cardId,boardId,sort,createdAt,modifiedAt) VALUES(?,?,?,0,'now','now')", (cid,card,board))
        con.execute("INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,modifiedAt) VALUES('foreignitem','foreigncheck','foreigncard','otherboard','Secret item',0,'now')")
        con.execute("INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES('foreigncomment','otherboard','foreigncard','u','Secret comment','now','now')")
        con.execute("INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES('foreignfield','Secret field','text','now')")
        con.execute("INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('foreignfield','otherboard')")
    cases = [
        ('GET','/lists/foreignlist/cards'),
        ('POST','/lists/foreignlist/cards'),
        ('DELETE','/lists/foreignlist'),
        ('GET','/lists/todo/cards/foreigncard'),
        ('PUT','/lists/todo/cards/foreigncard'),
        ('DELETE','/lists/todo/cards/foreigncard'),
        ('POST','/lists/todo/cards/foreigncard/archive'),
        ('POST','/lists/todo/cards/foreigncard/members/u'),
        ('DELETE','/lists/todo/cards/foreigncard/members/u'),
        ('POST','/lists/todo/cards/foreigncard/assignees/u'),
        ('DELETE','/lists/todo/cards/foreigncard/assignees/u'),
        ('GET','/lists/foreignlist/cards_count'),
        ('GET','/swimlanes/foreignlane/cards'),
        ('DELETE','/swimlanes/foreignlane'),
        ('GET','/cards/foreigncard/checklists'),
        ('POST','/cards/foreigncard/checklists'),
        ('GET','/cards/card/checklists/foreigncheck'),
        ('DELETE','/cards/card/checklists/foreigncheck'),
        ('POST','/cards/card/checklists/foreigncheck/items'),
        ('GET','/cards/card/checklists/check/items/foreignitem'),
        ('PUT','/cards/card/checklists/check/items/foreignitem'),
        ('DELETE','/cards/card/checklists/check/items/foreignitem'),
        ('GET','/cards/foreigncard/comments'),
        ('POST','/cards/foreigncard/comments'),
        ('GET','/cards/card/comments/foreigncomment'),
        ('DELETE','/cards/card/comments/foreigncomment'),
        ('GET','/custom-fields/foreignfield'),
        ('POST','/lists/todo/cards/card/customFields/foreignfield'),
    ]
    # Guard every resource-chain route in source too, so another handler cannot omit it.
    source = (Path(__file__).resolve().parents[1]/'src/wlapi.pas').read_text().split('implementation', 1)[1]
    handlers = re.split(r'(?=^procedure Api)', source, flags=re.M)
    checked = 0
    for handler in handlers:
        name = re.search(r'^procedure (Api\w+)', handler, re.M)
        if name is None:
            continue
        if name.group(1) in {'ApiBoardCopy', 'ApiUserBoards'}:
            continue  # Copy only reads its source board; UserBoards uses a user route.
        if any("RouteParams['"+key+"']" in handler for key in ['cardId','listId','swimlaneId','customField','checklistId','commentId','item']):
            assert 'if not ApiBoardGuard(' in handler, name.group(1) if name else handler[:60]
            checked += 1
    assert checked >= 20, checked
    with sqlite3.connect(db) as con:
        before = '\n'.join(con.iterdump())
    for method, suffix in cases:
        data = {'title':'attack','text':'attack','value':'attack'} if method in ['POST','PUT'] else None
        status, _, body = request(method, '/api/boards/protected'+suffix+'?token='+token, data)
        assert status == 404, (method, suffix, status, body)
    assert request('POST', '/api/boards/protected/lists/todo/cards?token='+token, {'title':'attack','swimlaneId':'foreignlane'})[0] == 400
    status, _, body = request('POST', '/api/attachment/upload?token='+token, json.dumps(dict(boardId='protected', swimlaneId='foreignlane', listId='foreignlist', cardId='foreigncard', fileData='eA==')).encode())
    assert status == 400, (status,body)
    with sqlite3.connect(db) as con:
        assert '\n'.join(con.iterdump()) == before, 'Rejected requests changed the database'
    with sqlite3.connect(db) as con:
        current_list = con.execute("SELECT listId FROM cards WHERE id='card'").fetchone()[0]
    assert request('GET', '/api/boards/protected/lists/'+current_list+'/cards/card?token='+token)[0] == 200
    print('PASS: 30 API cross-board/parent attempts rejected without database changes; valid card still readable')
    with sqlite3.connect(db) as con:
        con.execute("INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,modifiedAt) VALUES('deleteitem','check','card','protected','Item',0,'now')")
        con.execute("CREATE TRIGGER reject_check_delete AFTER DELETE ON checklists BEGIN SELECT RAISE(FAIL,'test'); END")
    path = '/api/boards/protected/cards/card/checklists/check?token='+token
    def read():
        status, _, body = request('GET',path)
        assert status == 200, (status,body)
        return json.loads(body)
    def update(data):
        return request('PUT',path,json.dumps(data).encode())[0]
    assert read()['dueAt'] is None
    for change in [{}, {'title':' '}, {'title':'Rejected','dueAt':'2026-02-30T00:00:00Z'},
                   {'dueAt':42}, {'dueAt':'2026-11-18T09:30:00'}]:
        assert update(change) == 400, change
    assert read()['title'] == 'Checklist' and read()['dueAt'] is None
    assert update({'title':'Renamed','dueAt':'2026-11-18T09:30:00+02:00'}) == 200
    assert (read()['title'],read()['dueAt']) == ('Renamed','2026-11-18T07:30:00.000Z')
    assert request('PUT',path,{'title':'Kept deadline'})[0] == 200
    assert read()['dueAt'] == '2026-11-18T07:30:00.000Z'
    assert update({'dueAt':None}) == 200
    assert (read()['title'],read()['dueAt']) == ('Kept deadline',None)
    print('PASS: checklist PUT validates deadline and title atomically and preserves omitted properties')
    assert request('DELETE',path)[0] == 500
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT id FROM checklist_items WHERE id='deleteitem'").fetchone() == ('deleteitem',)
        con.execute('DROP TRIGGER reject_check_delete')
    status, _, body = request('DELETE',path)
    assert status == 200 and json.loads(body) == dict(_id='check'), (status,body)
    status, _, body = request('DELETE',path)
    assert status == 404 and json.loads(body) == dict(error='Checklist not found or does not belong to the specified card'), (status,body)
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT id FROM checklist_items WHERE id IN ('deleteitem','foreignitem')").fetchall() == [('foreignitem',)]
    print('PASS: checklist DELETE cascades to its items and rolls back on failure')

    base = '/api/boards/protected/cards/card/checklists'
    def create(data):
        return request('POST',base+'?token='+token,json.dumps(data).encode())

    with sqlite3.connect(db) as con:
        before = '\n'.join(con.iterdump())
    for payload in [{'items':['first',20]}, {'dueAt':'tomorrow'}, {'title':None}]:
        assert create(payload)[0] == 400, payload
    with sqlite3.connect(db) as con:
        assert '\n'.join(con.iterdump()) == before
        con.execute("CREATE TRIGGER reject_initial_item AFTER INSERT ON checklist_items WHEN NEW.title='second' BEGIN SELECT RAISE(FAIL,'test'); END")
    payload = dict(title='Initial items',dueAt='2026-11-18T09:30:00.123+02:00',items=['first','second'])
    assert create(payload)[0] == 500
    with sqlite3.connect(db) as con:
        con.execute('DROP TRIGGER reject_initial_item')
        assert '\n'.join(con.iterdump()) == before
    status, _, body = create(payload)
    assert status == 200, (status,body)
    status, _, body = request('GET',base+'/'+json.loads(body)['_id']+'?token='+token)
    assert status == 200, (status,body)
    checklist = json.loads(body)
    assert checklist['dueAt'] == '2026-11-18T07:30:00.123Z', checklist
    assert [item['title'] for item in checklist['items']] == ['first','second'], checklist
    status, _, body = request('GET',base+'?token='+token)
    assert status == 200 and checklist in json.loads(body), (status,body)
    status, _, body = request('GET','/api/boards/protected/lists/'+current_list+'/cards/card?token='+token)
    assert status == 200 and checklist in json.loads(body)['checklists'], (status,body)
    print('PASS: checklist creation stores its deadline and ordered initial items or rolls back everything')

    items_path = base+'/'+checklist['_id']+'/items'
    def item_request(method,path,data=None):
        return request(method,path+'?token='+token,json.dumps(data).encode() if data is not None else None)
    status, _, body = item_request('POST',items_path,dict(title='Deadline item',dueAt='2026-11-18T09:30:00+02:00'))
    assert status == 200, (status,body)
    item_id = json.loads(body)['_id']
    item_path = items_path+'/'+item_id
    def read_item():
        status, _, body = item_request('GET',item_path)
        assert status == 200, (status,body)
        return json.loads(body)
    before_item = read_item()
    assert before_item['dueAt'] == '2026-11-18T07:30:00.000Z'
    assert item_request('PUT',item_path,dict(title='Rejected',dueAt='tomorrow'))[0] == 400
    assert read_item() == before_item
    status, _, body = item_request('PUT',item_path,dict(isFinished=True))
    assert status == 200 and json.loads(body) == dict(_id=item_id), (status,body)
    assert read_item() == dict(before_item,isFinished=True)
    assert item_request('PUT',item_path,dict(dueAt=None))[0] == 200
    assert read_item() == dict(before_item,isFinished=True,dueAt=None)
    print('PASS: checklist item API stores, preserves and clears deadlines with atomic validation')

    scoped_card = '/api/boards/protected/lists/'+current_list+'/cards/'
    status, _, body = request('GET',scoped_card+'missing?token='+token)
    assert status == 404 and json.loads(body) == dict(error='Card not found'), (status,body)
    with sqlite3.connect(db) as con:
        other_list, = con.execute("SELECT id FROM lists WHERE boardId='protected' AND id<>? LIMIT 1",(current_list,)).fetchone()
    status, _, body = request('GET','/api/boards/protected/lists/'+other_list+'/cards/card?token='+token)
    assert status == 404 and json.loads(body) == dict(error='Card not found'), (status,body)
    with sqlite3.connect(db) as con:
        con.execute("UPDATE cards SET archived=1 WHERE id='card'")
    try:
        status, _, body = request('GET',scoped_card+'card?token='+token)
        assert status == 404 and json.loads(body) == dict(error='Card not found'), (status,body)
        status, _, body = request('GET','/api/cards/card?token='+token)
        assert status == 200 and checklist['_id'] in {entry['_id'] for entry in json.loads(body)['checklists']}, (status,body)
        status, _, body = request('GET','/api/cards/missing?token='+token)
        assert status == 404 and json.loads(body) == dict(error='Card not found'), (status,body)
        assert request('GET','/api/cards/card')[0] == 401
    finally:
        with sqlite3.connect(db) as con:
            con.execute("UPDATE cards SET archived=0 WHERE id='card'")
    card_path=scoped_card+'card'
    for action, archived in [('archive',True),('unarchive',False)]:
        status, _, body = request('POST',card_path+'/'+action+'?token='+token)
        assert status == 200 and json.loads(body)['archived'] is archived, (status,body)
        with sqlite3.connect(db) as con:
            state = con.execute("SELECT archived,archivedAt,modifiedAt FROM cards WHERE id='card'").fetchone()
        assert state[0] == int(archived) and bool(state[1]) is archived, state
        status, _, body = request('POST',card_path+'/'+action+'?token='+token)
        assert status == 404 and json.loads(body) == dict(error='Card not found'), (status,body)
        with sqlite3.connect(db) as con:
            assert con.execute("SELECT archived,archivedAt,modifiedAt FROM cards WHERE id='card'").fetchone() == state
    print('PASS: archive and unarchive change state once and reject repeated requests without writes')
    print('PASS: global card GET includes archived cards and checklists and requires authentication')

    wrong_list_path='/api/boards/protected/lists/'+other_list+'/cards/card?token='+token
    for archived in [True,False]:
        status, _, body = request('PUT',wrong_list_path,json.dumps(dict(archive=archived)).encode())
        assert status == 200, (status,body)
        with sqlite3.connect(db) as con:
            assert con.execute("SELECT archived FROM cards WHERE id='card'").fetchone() == (int(archived),)
            before = '\n'.join(con.iterdump())
        assert request('PUT',wrong_list_path,json.dumps(dict(archive=archived)).encode())[0] == 200
        with sqlite3.connect(db) as con:
            assert '\n'.join(con.iterdump()) == before
    assert request('PUT',wrong_list_path,json.dumps(dict(archive=True,title='Rejected')).encode())[0] == 404
    print('PASS: archive-only PUT works without the current list and preserves state on repeated requests')

    list_path='/api/boards/protected/lists/'+current_list
    for list_type in ['list','template-list']:
        with sqlite3.connect(db) as con:
            con.execute("UPDATE lists SET type=? WHERE id=?",(list_type,current_list))
        for action, archived in [('archive',True),('unarchive',False)]:
            url=list_path+'/'+action+'?token='+token
            status, _, body = request('POST',url)
            assert status == 200 and json.loads(body) == dict(_id=current_list,archived=archived), (status,body)
            with sqlite3.connect(db) as con:
                assert con.execute('SELECT archived FROM lists WHERE id=?',(current_list,)).fetchone() == (int(archived),)
                assert con.execute("SELECT archived FROM cards WHERE id='card'").fetchone() == (int(archived and list_type=='template-list'),)
                before='\n'.join(con.iterdump())
            status, _, body = request('POST',url)
            assert status == 404 and json.loads(body) == dict(error='List not found'), (status,body)
            with sqlite3.connect(db) as con:
                assert '\n'.join(con.iterdump()) == before
    with sqlite3.connect(db) as con:
        con.execute("UPDATE lists SET type='list' WHERE id=?",(current_list,))
    print('PASS: list archive and restore reject repeated writes and cascade for template lists')

    def edit_list(data):
        return request('PUT',list_path+'?token='+token,json.dumps(data).encode())
    with sqlite3.connect(db) as con:
        before=con.execute('SELECT title,color,starred FROM lists WHERE id=?',(current_list,)).fetchone()
    assert edit_list(dict(title='Rejected',color='#abc'))[0] == 400
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT title,color,starred FROM lists WHERE id=?',(current_list,)).fetchone() == before
    status, _, body=edit_list(dict(title='Renamed list',color='#Aa01fF',starred=True))
    assert status == 200 and json.loads(body) == dict(_id=current_list), (status,body)
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT title,color,starred FROM lists WHERE id=?',(current_list,)).fetchone() == ('Renamed list','#Aa01fF',1)
        admin_id,=con.execute("SELECT id FROM users WHERE username='administrator'").fetchone()
        con.execute("INSERT OR IGNORE INTO board_members(boardId,userId,isAdmin) VALUES('protected',?,0)",(admin_id,))
        con.execute("UPDATE board_members SET isAdmin=0 WHERE boardId='protected' AND userId=?",(admin_id,))
    wip=dict(value=3,enabled=True,soft=False)
    assert edit_list(dict(title='Rejected',wipLimit=wip))[0] == 403
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT title FROM lists WHERE id=?',(current_list,)).fetchone() == ('Renamed list',)
        con.execute("UPDATE board_members SET isAdmin=1 WHERE boardId='protected' AND userId=?",(admin_id,))
    status, _, body=edit_list(dict(wipLimit=wip))
    assert status == 200, (status,body)
    with sqlite3.connect(db) as con:
        assert con.execute('SELECT wip_value,wip_enabled,wip_soft FROM lists WHERE id=?',(current_list,)).fetchone() == (3,1,0)
    print('PASS: list PUT validates color atomically and restricts WIP edits to board administrators')

    def read_list(path=list_path):
        return request('GET',path+'?token='+token)
    status, _, body=read_list()
    assert status == 200, (status,body)
    result=json.loads(body)
    assert result['title']=='Renamed list' and result['color']=='#Aa01fF' and result['starred'] is True
    assert result['wipLimit']==wip and result['boardId']=='protected', result
    assert request('POST',list_path+'/archive?token='+token)[0]==200
    try:
        for absent in [list_path,'/api/boards/protected/lists/foreignlist','/api/boards/protected/lists/missing']:
            status, _, body=read_list(absent)
            assert status==404 and json.loads(body)==dict(error='List not found'), (status,body)
    finally:
        assert request('POST',list_path+'/unarchive?token='+token)[0]==200
    print('PASS: list GET returns edit metadata and rejects archived, missing and foreign lists')

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
    assert request('GET', '/api/boards/protected/lists/todo/cards/card?token='+token)[0] == 200
    print('PASS: 29 API cross-board/parent attempts rejected without database changes; valid card still readable')

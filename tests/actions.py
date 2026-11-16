"""Selected-item actions exercise actual persistence, related data and attachment bytes."""
from layout import Forms
from urllib.parse import urlencode
from pathlib import Path
import base64
import json
import sqlite3

def run(request, db, session):
    with sqlite3.connect(db) as con:
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('actions','Action board','actions','now')")
        for lane in ['alane','aother']:
            con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(?,'actions',?,0,'now')",(lane,lane))
        for lid,lane in [('alist','alane'),('apreserve','aother')]:
            con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'actions',?,?,0,'now')",(lid,lane,lid))
        for cid,lid,lane,parent in [('acard','alist','alane',''),('achild','apreserve','aother','acard'),('akeep','apreserve','aother','')]:
            con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,parentId,title,description,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,'actions',?,?,?,?,'Description','u','now','now','now')",(cid,lid,lane,parent,cid))
        con.execute("INSERT INTO board_labels(boardId,id,name,color) VALUES('actions','label','Label','red')")
        con.execute("INSERT INTO card_labels(cardId,labelId) VALUES('acard','label')")
        con.execute("INSERT INTO card_members(cardId,userId) VALUES('acard','u')")
        con.execute("INSERT INTO card_assignees(cardId,userId) VALUES('acard','u')")
        con.execute("INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('acheck','acard','actions','Checklist',0,'now','now')")
        con.execute("INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,modifiedAt) VALUES('aitem','acheck','acard','actions','Item',0,'now')")
        con.execute("INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES('acomment','actions','acard','u','Comment','now','now')")
        con.execute("INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES('afield','Field','text','now')")
        con.execute("INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('afield','actions')")
        con.execute("INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('acard','afield','Value')")
        con.execute("INSERT INTO attachments(id,boardId,swimlaneId,listId,cardId,name,type,size,userId,createdAt) VALUES('afile','actions','alane','alist','acard','note.bin','application/octet-stream',5,'u','now')")
        con.execute("INSERT INTO activities(id,activityType,boardId,cardId,createdAt) VALUES('activity','createCard','actions','acard','now')")
    attachment=Path(db).parents[1]/'files/attachments/afile'
    attachment.write_bytes(b'a\0b\r\n')
    board='/board?'+urlencode(dict(id='actions',view='all',sessionId=session))
    def hidden(body):
        parser=Forms();parser.feed(body.decode());return parser.forms[-1][1]
    def action(name, selected=None, fields=None, token=None):
        data=hidden(request('GET',board)[2]) if token is None else dict(token)
        data['action']=name
        data.update(selected or {})
        data.update(fields or {})
        return request('POST','/board/move',data)
    def snapshot():
        with sqlite3.connect(db) as con:return '\n'.join(con.iterdump())
    before=snapshot()
    assert action('clear',{'sel_card':'acard'})[0]==302
    assert action('clear',{'sel_card':'stale-missing-card'})[0]==302
    assert snapshot()==before
    assert action('export')[0]==400
    status,_,body=action('edit',{'sel_card':'acard','sel_list':'alist'})
    assert status==200 and b'name="title_card_acard"' in body and b'name="title_list_alist"' in body
    token=hidden(body)
    fields=dict(title_card_acard='Edited <card>',color_card_acard='red',description_card_acard='Updated\ntext',title_list_alist='Edited list',color_list_alist='')
    saved=action('save',fields=fields,token=token)
    assert saved[0]==302,saved
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT title,description,color FROM cards WHERE id='acard'").fetchone()==('Edited <card>','Updated\ntext','red')
        assert con.execute("SELECT title FROM lists WHERE id='alist'").fetchone()[0]=='Edited list'
    status,_,body=action('edit',{'sel_card':'acard','sel_list':'alist'})
    token=hidden(body);before=snapshot()
    assert action('save',fields=dict(fields,title_list_alist=''),token=token)[0]==400
    assert snapshot()==before
    status,_,body=action('edit',{'sel_card':'acard','sel_list':'alist'})
    token=hidden(body)
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER reject_edit BEFORE UPDATE ON lists WHEN OLD.id='alist' BEGIN SELECT RAISE(ABORT,'forced edit failure'); END")
    before=snapshot()
    assert action('save',fields=dict(fields,title_card_acard='Must roll back'),token=token)[0]==400
    assert snapshot()==before,'Failed multi-item edit was not rolled back'
    with sqlite3.connect(db) as con:con.execute('DROP TRIGGER reject_edit')
    for key in ['sel_card','SEL_CARD']:
        before=snapshot()
        assert action('export',{key:'foreigncard'})[0]==403
        assert snapshot()==before
    # The same case-insensitive selection handling is used by permission and arrow paths.
    assert action('',{'SEL_CARD':'foreigncard'},dict(dir='right'))[0]==403
    token=hidden(request('GET',board)[2])
    status,headers,body=action('export',{'sel_list':'alist'},token=token)
    assert status==200 and 'select.jsn' in headers['Content-Disposition']
    graph=json.loads(body);data=graph['data']
    assert {row['id'] for row in data['cards']}=={'acard','achild'}
    assert data['card_comments'][0]['text']=='Comment' and data['checklist_items'][0]['title']=='Item'
    assert data['card_custom_field_values'][0]['value']=='Value'
    assert data['custom_fields'][0]['name']=='Field'
    assert base64.b64decode(graph['files'][0]['base64Data'])==attachment.read_bytes()
    assert 'users' not in data and 'login_tokens' not in data
    before=snapshot()
    assert action('export',{'sel_list':'alist'},token=token)[0]==200
    assert snapshot()==before
    assert action('clear',token=token)[0]==302
    assert action('export',{'sel_list':'alist'},token=token)[0]==403
    before=snapshot()
    status,_,body=action('delete',{'sel_list':'alist'})
    assert status==200 and b'confirm-delete' in body and snapshot()==before
    token=hidden(body)
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER reject_delete BEFORE DELETE ON cards WHEN OLD.id='acard' BEGIN SELECT RAISE(ABORT,'forced delete failure'); END")
    before=snapshot()
    assert action('confirm-delete',token=token)[0]==500
    assert snapshot()==before and attachment.exists()
    with sqlite3.connect(db) as con:con.execute('DROP TRIGGER reject_delete')
    status,_,body=action('delete',{'sel_list':'alist'})
    assert action('confirm-delete',token=hidden(body))[0]==302
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT COUNT(*) FROM cards WHERE id IN ('acard','achild')").fetchone()[0]==0
        assert con.execute("SELECT COUNT(*) FROM lists WHERE id='alist'").fetchone()[0]==0
        assert con.execute("SELECT COUNT(*) FROM cards WHERE id='akeep'").fetchone()[0]==1
        for table in ['card_members','card_assignees','card_labels','card_comments','checklists','checklist_items','attachments','activities']:
            assert con.execute('SELECT COUNT(*) FROM '+table+" WHERE "+('id' if table in ['checklists','checklist_items','attachments','activities'] else 'cardId')+"=?",({'checklists':'acheck','checklist_items':'aitem','attachments':'afile','activities':'activity'}.get(table,'acard'),)).fetchone()[0]==0,table
    assert not attachment.exists()
    print('PASS: selected Edit/Save/Clear/Export/confirmed Delete, descendant/child/file data, SQL rollback and case-insensitive ownership')

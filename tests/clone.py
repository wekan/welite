"""Deep-clone remapping and byte/SQL rollback checks against the running server."""
from layout import Forms
from pathlib import Path
from urllib.parse import urlencode
import json
import sqlite3
from paths import stored

def run(request, db, session):
    with sqlite3.connect(db) as con:
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('clone','Clone board','clone','now')")
        for sid,sort in [('clane',5),('clother',10)]:
            con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(?,'clone',?,?,'old')",(sid,sid,sort))
        for lid,sid,sort in [('clist','clane',7),('cother','clother',8),('cshared','',9)]:
            con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'clone',?,?,?,'old')",(lid,sid,lid,sort))
        for cid,lid,sid,parent,sort,archived in [('ccard','clist','clane','',1,0),('cchild','cother','clother','ccard',2,1),('cglobal','cshared','clane','',3,0),('ckeep','cother','clother','',4,0)]:
            con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,parentId,title,description,color,userId,sort,cardNumber,archived,createdAt,modifiedAt,dateLastActivity,extra_json) VALUES(?,'clone',?,?,?,?, 'UTF-8: 日本語',NULL,'u',?,42,?,'old','old','old','{\"nested\":true}')",(cid,lid,sid,parent,cid,sort,archived))
        con.execute("INSERT INTO board_labels(boardId,id,name,color) VALUES('clone','clabel','Label','red')")
        for table,column,value in [('card_labels','labelId','clabel'),('card_members','userId','u'),('card_assignees','userId','u')]:
            con.execute('INSERT INTO '+table+'(cardId,'+column+") VALUES('ccard',?)",(value,))
        for target in ['cchild','ckeep']:
            con.execute("INSERT INTO card_dependencies(cardId,targetCardId) VALUES('ccard',?)",(target,))
        con.execute("INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('ccheck','ccard','clone','Checklist',0,'old','old')")
        con.execute("INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,isFinished,modifiedAt) VALUES('citem','ccheck','ccard','clone','Item',0,1,'old')")
        for cid,parent in [('ccomment',''),('creply','ccomment')]:
            con.execute("INSERT INTO card_comments(id,boardId,cardId,userId,text,parentId,createdAt,modifiedAt) VALUES(?,'clone','ccard','u',?,?, 'old','old')",(cid,cid,parent))
        con.execute("INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES('cfield','Custom field','text','old')")
        con.execute("INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('cfield','clone')")
        con.execute("INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('ccard','cfield','Value')")
        for aid in ['cfile','czfile']:
            con.execute("INSERT INTO attachments(id,boardId,listId,swimlaneId,cardId,name,type,size,userId,createdAt) VALUES(?,'clone','clist','clane','ccard',?,'application/octet-stream',4,'u','old')",(aid,aid+'.bin'))
        con.execute("UPDATE cards SET coverId='cfile',description=? WHERE id='ccard'",('UTF-8: 日本語\0tail',))
        con.execute("INSERT INTO activities(id,activityType,boardId,cardId,createdAt) VALUES('chistory','createCard','clone','ccard','old')")
    files=Path(db).parents[1]/'attachme'
    for identity in ['cfile','czfile']:stored(db,identity).parent.mkdir(parents=True,exist_ok=True)
    stored(db,'cfile').write_bytes(b'a\0b\n')
    stored(db,'czfile').write_bytes(b'z\r\nx')
    board='/board?'+urlencode(dict(id='clone',view='all',sessionId=session))
    def token():
        parser=Forms();parser.feed(request('GET',board)[2].decode());return parser.forms[-1][1]
    def clone(selected=None, auth=None):
        data=token() if auth is None else dict(auth)
        data.update(action='clone');data.update(selected or {})
        return request('POST','/board/move',data)
    def snapshot():
        with sqlite3.connect(db) as con:data='\n'.join(con.iterdump())
        return data,{str(p.relative_to(files)):p.read_bytes() for p in files.rglob('*') if p.is_file()}
    assert clone()[0]==400
    before=snapshot()
    assert clone({'sel_card':'foreigncard'})[0]==403 and snapshot()==before
    with sqlite3.connect(db) as con:
        uid=con.execute("SELECT id FROM users WHERE username='administrator'").fetchone()[0]
        con.execute("INSERT INTO board_members(boardId,userId,isAdmin) VALUES('clone',?,0)",(uid,))
    for flag in ['readOnly','adminOnly']:
        with sqlite3.connect(db) as con:con.execute('UPDATE custom_fields SET '+flag+"=1 WHERE id='cfield'")
        before=snapshot();assert clone({'sel_card':'ccard'})[0]==403;assert snapshot()==before
        with sqlite3.connect(db) as con:con.execute('UPDATE custom_fields SET '+flag+"=0 WHERE id='cfield'")
    with sqlite3.connect(db) as con:con.execute("UPDATE cards SET extra_json=? WHERE id='ccard'",(json.dumps(dict(customFields=[dict(_id='missing',value='Hidden copy')])),))
    before=snapshot();assert clone({'sel_card':'ccard'})[0]==403;assert snapshot()==before
    with sqlite3.connect(db) as con:con.execute("UPDATE cards SET extra_json='{\"nested\":true}' WHERE id='ccard'")
    # Triggered authority changes occur after copied files and SQL rows exist.
    for mutation in ["UPDATE custom_fields SET readOnly=1 WHERE id='cfield';",
                     "UPDATE users SET loginDisabled=1 WHERE id='"+uid+"';"]:
        with sqlite3.connect(db) as con:con.execute("CREATE TRIGGER clone_policy AFTER INSERT ON activities WHEN NEW.activityType='clone' AND NEW.boardId='clone' BEGIN "+mutation+' END')
        before=snapshot();assert clone({'sel_card':'ccard'})[0]==500;assert snapshot()==before,'Policy rollback left rows or copied files'
        with sqlite3.connect(db) as con:con.execute('DROP TRIGGER clone_policy')
    # An assigned null is copyable, but a trigger cannot turn its new copy into
    # a protected nonnull value before commit.
    with sqlite3.connect(db) as con:
        con.execute("UPDATE custom_fields SET readOnly=1 WHERE id='cfield'")
        con.execute("UPDATE card_custom_field_values SET value=NULL WHERE cardId='ccard'")
        con.execute("CREATE TRIGGER clone_policy AFTER INSERT ON card_custom_field_values WHEN NEW.cardId<>'ccard' AND NEW.customFieldId='cfield' AND NEW.value IS NULL BEGIN UPDATE card_custom_field_values SET value='Injected protected value' WHERE cardId=NEW.cardId AND customFieldId=NEW.customFieldId; END")
    before=snapshot();assert clone({'sel_card':'ccard'})[0]==500;assert snapshot()==before
    with sqlite3.connect(db) as con:
        con.execute('DROP TRIGGER clone_policy')
        con.execute("UPDATE custom_fields SET readOnly=0 WHERE id='cfield'")
        con.execute("UPDATE card_custom_field_values SET value='Value' WHERE cardId='ccard'")
    # A second source file failure occurs after the first attachment has been copied.
    stored(db,'czfile').unlink();before=snapshot()
    assert clone({'sel_swimlane':'clane'})[0]==500
    assert snapshot()==before,'Failed file preparation left cloned rows or partial files'
    stored(db,'czfile').write_bytes(b'z\r\nx')
    with sqlite3.connect(db) as con:
        con.execute("UPDATE attachments SET storageBackend='external' WHERE id='czfile'")
    before=snapshot()
    assert clone({'sel_swimlane':'clane'})[0]==500
    assert snapshot()==before,'Unsupported attachment clone changed originals'
    with sqlite3.connect(db) as con:
        con.execute("UPDATE attachments SET storageBackend='filesystem' WHERE id='czfile'")
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER reject_clone BEFORE INSERT ON checklist_items WHEN NEW.id<>'citem' BEGIN SELECT RAISE(ABORT,'forced clone failure'); END")
    before=snapshot()
    assert clone({'sel_swimlane':'clane'})[0]==500
    assert snapshot()==before,'Failed SQL clone left copied rows/files'
    with sqlite3.connect(db) as con:con.execute('DROP TRIGGER reject_clone')
    old_ids={}
    with sqlite3.connect(db) as con:
        for table in ['swimlanes','lists','cards','checklists','checklist_items','card_comments','attachments']:
            old_ids[table]={row[0] for row in con.execute('SELECT id FROM '+table)}
        users=con.execute('SELECT COUNT(*) FROM users').fetchone()[0]
        original_rows={table:con.execute('SELECT * FROM '+table+' ORDER BY id').fetchall() for table in old_ids}
    auth=token()
    response=clone({'sel_swimlane':'clane','sel_list':'clist','sel_card':'ccard'},auth)
    assert response[0]==302,response
    assert clone({'sel_swimlane':'clane'},auth)[0]==403,'Clone token was replayed'
    with sqlite3.connect(db) as con:
        con.row_factory=sqlite3.Row
        new={table:[dict(row) for row in con.execute('SELECT * FROM '+table) if row['id'] not in old_ids[table]] for table in old_ids}
        assert len(new['swimlanes'])==1 and len(new['lists'])==1 and len(new['cards'])==3
        lane=new['swimlanes'][0];lst=new['lists'][0]
        assert lane['title']=='clane Copy' and lane['sort']>10
        assert lst['title']=='clist Copy' and lst['swimlaneId']==lane['id']
        root=next(row for row in new['cards'] if row['title']=='ccard Copy')
        child=next(row for row in new['cards'] if row['title']=='cchild')
        shared=next(row for row in new['cards'] if row['title']=='cglobal')
        assert root['listId']==lst['id'] and root['swimlaneId']==lane['id']
        assert child['parentId']==root['id'] and child['listId']=='cother' and child['swimlaneId']=='clother' and child['archived']==1
        assert shared['listId']=='cshared' and shared['swimlaneId']==lane['id']
        assert root['color'] is None and json.loads(root['extra_json'])=={'nested':True}
        assert root['description']=='UTF-8: 日本語\0tail' and root['createdAt']!='old', (root['description'],root['createdAt'])
        numbers=[row['cardNumber'] for row in new['cards']]
        assert len(set(numbers))==3 and min(numbers)>42
        check=new['checklists'][0];item=new['checklist_items'][0]
        assert check['cardId']==root['id'] and item['checklistId']==check['id'] and item['cardId']==root['id'] and item['isFinished']==1
        comment=next(row for row in new['card_comments'] if row['text']=='ccomment')
        reply=next(row for row in new['card_comments'] if row['text']=='creply')
        assert comment['cardId']==root['id'] and reply['parentId']==comment['id']
        dependencies={row[0] for row in con.execute('SELECT targetCardId FROM card_dependencies WHERE cardId=?',(root['id'],))}
        assert dependencies=={child['id'],'ckeep'}
        for table,column,value in [('card_members','userId','u'),('card_assignees','userId','u'),('card_labels','labelId','clabel'),('card_custom_field_values','customFieldId','cfield')]:
            assert con.execute('SELECT '+column+' FROM '+table+' WHERE cardId=?',(root['id'],)).fetchone()[0]==value
        assert len(new['attachments'])==2
        for attachment in new['attachments']:
            assert attachment['cardId']==root['id'] and attachment['listId']==lst['id'] and attachment['swimlaneId']==lane['id']
            assert stored(db,attachment['id']).read_bytes()==stored(db,Path(attachment['name']).stem).read_bytes()
        assert root['coverId']==next(a['id'] for a in new['attachments'] if a['name']=='cfile.bin')
        assert con.execute("SELECT COUNT(*) FROM activities WHERE activityType='clone' AND boardId='clone'").fetchone()[0]==5
        assert con.execute('SELECT COUNT(*) FROM users').fetchone()[0]==users
        for table,rows in original_rows.items():
            now=[tuple(row) for row in con.execute('SELECT * FROM '+table+' ORDER BY id') if row['id'] in old_ids[table]]
            assert now==rows,table+' originals changed'
    # A list-only clone stays in its original lane and preserves implicit card titles.
    with sqlite3.connect(db) as con:
        before_lists={row[0] for row in con.execute('SELECT id FROM lists')}
        before_cards={row[0] for row in con.execute('SELECT id FROM cards')}
    assert clone({'sel_list':'clist'})[0]==302
    with sqlite3.connect(db) as con:
        con.row_factory=sqlite3.Row
        lists=[dict(row) for row in con.execute('SELECT * FROM lists') if row['id'] not in before_lists]
        cards=[dict(row) for row in con.execute('SELECT * FROM cards') if row['id'] not in before_cards]
        assert len(lists)==1 and len(cards)==2
        assert lists[0]['swimlaneId']=='clane' and lists[0]['title']=='clist Copy'
        root=next(row for row in cards if row['title']=='ccard')
        assert root['listId']==lists[0]['id'] and root['swimlaneId']=='clane'
        assert next(row for row in cards if row['title']=='cchild')['parentId']==root['id']
    print('PASS: deep Clone deduplicates mixed roots, remaps child/cover/dependency IDs, preserves shared references and original rows, copies bytes and rolls back file/SQL failures')

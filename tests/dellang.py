"""Native deletion previews count removed data without counting retained definitions."""
from html.parser import HTMLParser
import html
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import urlencode
from layout import Forms
from homelang import Page
from paths import stored
root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'i18n/locales.jsn').read_text())
english=json.loads((root/'i18n/data/en.jsn').read_text())
expected={'swimlanes':0,'lists':1,'cards':2,'attachments':1,'activities':1,
          'card_members':1,'card_assignees':1,'card_labels':1,'card_custom_field_values':1,
          'card_dependencies':2,'card_comments':2,'checklists':1,'checklist_items':1}
tables=('boards','swimlanes','lists','cards','board_labels','custom_fields','custom_field_boards',
        'custom_field_dropdown_items','card_members','card_assignees','card_labels','card_custom_field_values',
        'card_dependencies','card_comments','checklists','checklist_items','attachments','activities')
class Details(HTMLParser):
    def __init__(self,body):
        super().__init__();self.names={};self.counts={};self.inputs={};self.capture=None
        self.feed(body.decode())
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='dt' and 'data-delete-kind' in attrs:
            self.capture=(self.names,attrs['data-delete-kind']);self.names[attrs['data-delete-kind']]=''
        if tag=='dd' and 'data-delete-count' in attrs:
            self.capture=(self.counts,attrs['data-delete-count']);self.counts[attrs['data-delete-count']]=''
        if tag=='input' and 'name' in attrs:self.inputs[attrs['name']]=attrs
    def handle_data(self,text):
        if self.capture:self.capture[0][self.capture[1]]+=text
    def handle_endtag(self,tag):
        if tag in ('dt','dd'):self.capture=None

def run(request,database,session,base):
    attachment=stored(database,'dlfile')
    def cleanup():
        with sqlite3.connect(database) as con:
            con.execute('PRAGMA foreign_keys=ON')
            for table in ('attachments','activities'):con.execute('DELETE FROM '+table+" WHERE boardId='dlboard'")
            con.execute("DELETE FROM custom_fields WHERE id='dlfield'")
            con.execute("DELETE FROM boards WHERE id IN ('dlboard','dlother')")
        attachment.unlink(missing_ok=True)
    def seed():
        with sqlite3.connect(database) as con:
            for bid in ('dlboard','dlother'):con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES(?,?,?,'now')",(bid,bid,bid))
            for lane in ('dllane','dlotherlane'):con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(?,'dlboard',?,0,'now')",(lane,lane))
            for lid,lane in [('dllist','dllane'),('dlkeeplist','dlotherlane')]:
                con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'dlboard',?,?,0,'now')",(lid,lane,lid))
            for cid,bid,lid,lane,parent in [('dlcard','dlboard','dllist','dllane',''),('dlchild','dlboard','dlkeeplist','dlotherlane','dlcard'),('dlkeep','dlboard','dlkeeplist','dlotherlane',''),('dlforeign','dlother','','','')]:
                con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,parentId,title,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,?,?,?,?,?,'u','now','now','now')",(cid,bid,lid,lane,parent,cid))
            con.execute("INSERT INTO board_labels(boardId,id,name,color) VALUES('dlboard','dllabel','Retained label','red')")
            for table,key,value in [('card_members','userId','u'),('card_assignees','userId','u'),('card_labels','labelId','dllabel')]:
                con.execute('INSERT INTO '+table+'(cardId,'+key+") VALUES('dlcard',?)",(value,))
            con.execute("INSERT INTO custom_fields(id,name,type,modifiedAt) VALUES('dlfield','Retained field','text','now')")
            con.execute("INSERT INTO custom_field_boards(customFieldId,boardId) VALUES('dlfield','dlboard')")
            con.execute("INSERT INTO custom_field_dropdown_items(customFieldId,id,name) VALUES('dlfield','dldrop','Retained dropdown')")
            con.execute("INSERT INTO card_custom_field_values(cardId,customFieldId,value) VALUES('dlcard','dlfield','Value')")
            for source,target in [('dlcard','dlkeep'),('dlkeep','dlcard'),('dlforeign','dlcard')]:
                con.execute('INSERT INTO card_dependencies(cardId,targetCardId) VALUES(?,?)',(source,target))
            con.execute("INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES('dlcomment','dlboard','dlcard','u','Comment','now','now')")
            # Card ownership drives this cascade even with legacy duplicated board metadata.
            con.execute("INSERT INTO card_comments(id,boardId,cardId,userId,text,createdAt,modifiedAt) VALUES('dlcrosscomment','dlother','dlcard','u','Legacy comment','now','now')")
            con.execute("INSERT INTO checklists(id,cardId,boardId,title,sort,createdAt,modifiedAt) VALUES('dlcheck','dlcard','dlboard','Checklist',0,'now','now')")
            con.execute("INSERT INTO checklist_items(id,checklistId,cardId,boardId,title,sort,modifiedAt) VALUES('dlitem','dlcheck','dlcard','dlboard','Item',0,'now')")
            con.execute("INSERT INTO attachments(id,boardId,cardId,name,size,createdAt) VALUES('dlfile','dlboard','dlcard','note.bin',5,'now')")
            con.execute("INSERT INTO activities(id,activityType,boardId,cardId,createdAt) VALUES('dlactivity','createCard','dlboard','dlcard','now')")
        attachment.parent.mkdir(parents=True,exist_ok=True);attachment.write_bytes(b'a\0b\r\n')
    def state():
        with sqlite3.connect(database) as con:
            return [con.execute('SELECT * FROM '+table+' ORDER BY '+','.join(str(i+1) for i in range(len(con.execute('PRAGMA table_info('+table+')').fetchall())))).fetchall() for table in tables]
    def preview(tag,explicit=True,posted=None):
        row=next(row for row in catalog if row['tag']==tag)
        local=json.loads((root/'i18n/data'/row['file']).read_text());words={key:local.get(key) or value for key,value in english.items()}
        query=dict(id='dlboard',view='all',sessionId=session)
        if explicit:query['lang']=tag
        status,_,body=request('GET','/board?'+urlencode(query),extra_headers={'Accept-Language':'fi'});assert status==200
        form=Forms();form.feed(body.decode());fields=next(fields for action,fields in form.forms if action=='/board/move')
        fields.update(sel_list='dllist',action_delete='caption only');fields.update(posted or {})
        status,headers,body=request('POST','/board/move',fields,extra_headers={'Accept-Language':'fi'})
        assert status==200 and headers['Content-Language']==tag.replace('_','-')
        doc=Details(body)
        assert {kind:int(value) for kind,value in doc.counts.items()}==expected,(tag,doc.counts)
        captions={key:words[key] for key in ('swimlanes','lists','cards','attachments','activities','checklists')}
        captions.update({'card_'+key:words['cards']+' / '+words[key] for key in ('members','assignees','labels')})
        captions.update(card_custom_field_values=words['cards']+' / '+words['custom-fields'],card_dependencies=words['card-dependencies'],
                        card_comments=words['comments'],checklist_items=words['checklists']+' / '+words['r-item'])
        assert doc.names==captions,(tag,doc.names)
        assert doc.inputs['action_confirm-delete']['value']==words['confirm']
        assert ('<title>'+html.escape(words['confirm']+' / '+words['r-delete-selected'],quote=False)+'</title>').encode() in body
        page=Page(body);assert page.captions('/board')==[words['cancel']],(tag,'cancel')
        assert b'This includes' not in body and b'confirm-delete' in body
        form=Forms();form.feed(body.decode());return next(fields for action,fields in form.forms if action=='/board/move')
    def deleted():
        with sqlite3.connect(database) as con:
            assert con.execute("SELECT count(*) FROM cards WHERE id IN ('dlcard','dlchild')").fetchone()==(0,)
            assert con.execute("SELECT count(*) FROM lists WHERE id='dllist'").fetchone()==(0,)
            for table,where in [('boards',"id='dlboard'"),('cards',"id='dlkeep'"),('cards',"id='dlforeign'"),('board_labels',"id='dllabel'"),('custom_fields',"id='dlfield'"),('custom_field_boards',"customFieldId='dlfield'"),('custom_field_dropdown_items',"id='dldrop'")]:
                assert con.execute('SELECT count(*) FROM '+table+' WHERE '+where).fetchone()==(1,),(table,where)
            assert con.execute("SELECT count(*) FROM card_dependencies WHERE cardId IN ('dlcard','dlkeep')").fetchone()==(0,)
            assert con.execute("SELECT count(*) FROM card_dependencies WHERE cardId='dlforeign' AND targetCardId='dlcard'").fetchone()==(1,)
            for table,where in [('attachments',"id='dlfile'"),('activities',"id='dlactivity'"),('card_members',"cardId='dlcard'"),('card_assignees',"cardId='dlcard'"),('card_labels',"cardId='dlcard'"),('card_custom_field_values',"cardId='dlcard'"),('card_comments',"id IN ('dlcomment','dlcrosscomment')"),('checklists',"id='dlcheck'"),('checklist_items',"id='dlitem'")]:
                assert con.execute('SELECT count(*) FROM '+table+' WHERE '+where).fetchone()==(0,),table
        assert not attachment.exists()
    with sqlite3.connect(database) as con:profile=con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0]
    seed()
    try:
        before=state()
        for row in catalog:preview(row['tag'])
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps({'language':'ar','keep':True}),))
        preview('ar',False);preview('fi');preview('ar',False,{'lang':'unknown'})
        assert state()==before and attachment.read_bytes()==b'a\0b\r\n','Preview changed data or bytes'
        if os.environ.get('WELITE_UI')=='1':
            for tag in ('fi','ar','he'):
                cleanup();seed()
                subprocess.run([os.environ.get('NODE','node'),str(root/'tests/dellang.js'),base,session,tag],check=True)
                deleted()
        else:
            fields=preview('fi');fields['action_confirm-delete']='delete label is ignored'
            assert request('POST','/board/move',fields)[0]==302
            deleted()
    finally:
        cleanup()
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(profile,))
    print('PASS: installed native delete details/confirm/cancel, exact cascaded/inbound counts, retained definitions/foreign scope, no preview mutations and native confirmed deletion')

"""Selection edit captions use native keys without translating field names or user values."""
from html.parser import HTMLParser
import html
import json
import os
import re
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import urlencode
from layout import Forms
root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'i18n/locales.jsn').read_text())
english=json.loads((root/'i18n/data/en.jsn').read_text())
card_id='edit& "漢'
class EditDoc(HTMLParser):
    def __init__(self,body):
        super().__init__();self.legends=[];self.labels=[];self.capture='';self.textarea=False;self.inputs={};self.targets=[];self.textareas=[]
        self.feed(body.decode())
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='legend':self.capture='legend';self.legends.append('')
        if tag=='label':
            self.capture='label';self.labels.append('')
            if 'for' in attrs:self.targets.append(attrs['for'])
        if tag=='textarea':self.textarea=True;self.textareas.append(attrs)
        if tag=='input' and attrs.get('name'):self.inputs[attrs['name']]=attrs
    def handle_data(self,text):
        if self.capture=='legend':self.legends[-1]+=text
        if self.capture=='label' and not self.textarea:self.labels[-1]+=text
    def handle_endtag(self,tag):
        if tag in ('legend','label'):self.capture=''
        if tag=='textarea':self.textarea=False

def run(request,database,session,base):
    def state(include_modified=True):
        with sqlite3.connect(database) as con:
            result=[]
            for table in ('boards','swimlanes','lists','cards'):
                columns=[row[1] for row in con.execute('PRAGMA table_info('+table+')') if include_modified or row[1]!='modifiedAt']
                result.append(con.execute('SELECT '+','.join('"'+name+'"' for name in columns)+' FROM '+table+' ORDER BY id').fetchall())
            return result
    with sqlite3.connect(database) as con:
        uid=con.execute("SELECT id FROM users WHERE username='administrator'").fetchone()[0]
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('editlang','Edit <user>','editlang','now')")
        con.execute("INSERT INTO swimlanes(id,boardId,title,color,createdAt) VALUES('editlane','editlang','Lane <user>','red','now')")
        con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,color,createdAt) VALUES('editlist','editlang','editlane','List <user>','red','now')")
        con.execute("INSERT INTO cards(id,boardId,listId,swimlaneId,title,color,description,userId,createdAt,modifiedAt,dateLastActivity) VALUES(?,'editlang','editlist','editlane',?,'red',?,?,'now','now','now')",(card_id,'Card <user> & 漢字','Description <user> & 漢字',uid))
    before=state();before_content=state(False)
    def edit(tag,explicit=True,posted=None):
        row=next(row for row in catalog if row['tag']==tag)
        local=json.loads((root/'i18n/data'/row['file']).read_text())
        words={key:local.get(key) or value for key,value in english.items()}
        query=dict(id='editlang',view='all',sessionId=session)
        if explicit:query['lang']=tag
        status,_,body=request('GET','/board?'+urlencode(query),extra_headers={'Accept-Language':'fi'})
        assert status==200
        forms=Forms();forms.feed(body.decode())
        fields=next(fields for action,fields in forms.forms if action=='/board/move')
        fields.update(sel_card=card_id,sel_list='editlist',sel_swimlane='editlane',action_edit='not the command')
        fields.update(posted or {})
        status,headers,body=request('POST','/board/move',fields,extra_headers={'Accept-Language':'fi'})
        assert status==200 and headers['Content-Language']==tag.replace('_','-')
        doc=EditDoc(body)
        assert sorted(doc.legends)==sorted(words[k] for k in ('swimlane','list','card')),(tag,doc.legends)
        assert doc.inputs['action_save']['value']==words['save'],(tag,'save')
        assert doc.labels.count(words['title']+' ')==3,(tag,doc.labels)
        assert doc.labels.count(words['allboards.workspace-color']+' ')==3,(tag,doc.labels)
        assert words['description'] in doc.labels,(tag,'description')
        assert ('<title>'+html.escape(words['edit']+' / '+words['multi-selection'],quote=False)+'</title>').encode() in body
        assert 'title_card_'+card_id in doc.inputs and 'title_list_editlist' in doc.inputs and 'title_swimlane_editlane' in doc.inputs
        assert doc.inputs['title_card_'+card_id]['value']=='Card <user> & 漢字'
        assert b'Card <user>' not in body and b'Description <user>' not in body
        assert b'(hex, e.g.' not in body and b'<code>#ffee22</code>' in body
        assert len(doc.textareas)==1 and doc.textareas[0]['name']=='description_card_'+card_id
        target=doc.textareas[0]['id']
        assert re.fullmatch(r'desc_[0-9a-f]{64}',target) and doc.targets==[target]

        forms=Forms();forms.feed(body.decode())
        return next(fields for action,fields in forms.forms if action=='/board/move')
    with sqlite3.connect(database) as con:
        profile=con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0]
    try:
        for row in catalog:edit(row['tag'])
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps({'language':'ar','keep':True}),))
        edit('ar',False)
        edit('fi')
        edit('ar',False,{'lang':'unknown'})
        fields=edit('fi');fields.update({'action_save':'delete','title_card_'+card_id:'','title_list_editlist':'List <user>','title_swimlane_editlane':'Lane <user>'})
        assert request('POST','/board/move',fields)[0]==400
        assert state()==before,'Edit rendering or rejected native save changed board content'
        if os.environ.get('WELITE_UI')=='1':
            subprocess.run([os.environ.get('NODE','node'),str(root/'tests/editlang.js'),base,session],check=True)
        assert state(False)==before_content,'Native edit/save round trip changed user content'
    finally:
        with sqlite3.connect(database) as con:
            con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(profile,))
            con.execute("DELETE FROM cards WHERE boardId='editlang'")
            con.execute("DELETE FROM lists WHERE boardId='editlang'")
            con.execute("DELETE FROM swimlanes WHERE boardId='editlang'")
            con.execute("DELETE FROM boards WHERE id='editlang'")
    print('PASS: installed native edit headings/kinds/field/save labels, stable field names/user values, profile/query selection and rejected native save without content changes')

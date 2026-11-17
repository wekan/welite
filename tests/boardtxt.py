"""Native board links, titles and empty/not-found states over real HTTP."""
import html
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import urlencode,parse_qs,urlsplit
from homelang import Page
root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'i18n/locales.jsn').read_text())
english=json.loads((root/'i18n/data/en.jsn').read_text())

class BoardPage(Page):
    def __init__(self,body):self.maps=[];super().__init__(body)
    def handle_starttag(self,tag,attrs):
        if tag=='table' and 'data-board-map' in dict(attrs):self.maps.append(dict(attrs))
        super().handle_starttag(tag,attrs)

def run(request,database,administrator,base):
    with sqlite3.connect(database) as con:
        profile=con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0]
        for bid,title in [('boardtxt','Board <user>'),('boardnone','No lanes <user>')]:
            con.execute("INSERT INTO boards(id,title,slug,permission,createdAt) VALUES(?,?,?,'public','now')",(bid,title,bid))
        for lid,order in [('txtlane',0),('txtlane2',1),('txtempty',2)]:
            con.execute("INSERT INTO swimlanes(id,boardId,title,sort,createdAt) VALUES(?,'boardtxt',?,?,'now')",(lid,lid,order))
        con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES('boardtxt','/boardtxt','Configured title','html4','auto','anon','now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,binding,options_json,createdAt,modifiedAt) VALUES('boardtxt','boardtxt','dataview','board',?,'now','now')",(json.dumps({'boardId':'protected'}),))
        for lid,lane,order in [('txtlist','txtlane',0),('txtlist2','txtlane',1),('txtlist3','txtlane2',0),('txtlist4','txtlane2',1)]:
            con.execute("INSERT INTO lists(id,boardId,swimlaneId,title,sort,createdAt) VALUES(?,'boardtxt',?,'List <user>',?,'now')",(lid,lane,order))
    def check(tag,session='',query=None,header='en',board='boardtxt'):
        row=next(row for row in catalog if row['tag']==tag)
        local=json.loads((root/'i18n/data'/row['file']).read_text())
        words={key:local.get(key) or value for key,value in english.items()}
        fields=dict(id=board,view='all');fields.update(query or {})
        if session:fields['sessionId']=session
        status,headers,body=request('GET','/board?'+urlencode(fields),extra_headers={'Accept-Language':header})
        assert headers['Content-Language']==tag.replace('_','-')
        assert 'Accept-Language' in headers['Vary'] and 'Set-Cookie' not in headers
        assert ('<title>'+html.escape(words['board'],quote=False)+'</title>').encode() in body,(tag,'title')
        if board in ('missing-txt','protected'):
            assert status==404 and html.escape(words['board-not-found'],quote=False).encode() in body
            assert b'Board &lt;user&gt;' not in body
            return
        assert status==200
        page=BoardPage(body)
        assert page.captions('/')==[words['all-boards']],(tag,'all-boards',page.items)
        assert len(page.maps)==1 and page.maps[0]['summary']==words['board']+' / '+words['view'],(tag,page.maps)
        assert page.maps[0]['data-board-map']==board
        legend=words['color-yellow']+': '+words['current']+'; *: '+words['cards']+'; -: '+words['no-items-message']
        assert html.escape(legend,quote=False).encode() in body,(tag,'legend')
        arrows={'left':'<','right':'>','up':'^','down':'v'}
        native=[(attrs,text) for name,attrs,text in page.items if name=='a' and 'data-view-dir' in attrs]
        if board=='boardtxt':assert len(native)>=2,(tag,native)
        for attrs,text in native:
            assert attrs['dir']=='ltr' and text==words['view']+' '+arrows[attrs['data-view-dir']],(tag,attrs,text)

        all_captions=[text for name,attrs,text in page.items if name=='a' and parse_qs(urlsplit(attrs['href']).query).get('view')==['all']]
        assert all_captions==[words['view-all']],(tag,'view-all')
        assert html.escape(words['no-items-message'],quote=False).encode() in body,(tag,'empty')
        assert b'Board <user>' not in body and b'List <user>' not in body
    try:
        for row in catalog:check(row['tag'],query={'lang':row['tag']})
        for tag in ('en','fi','ar','he'):
            check(tag,query={'lang':tag},board='boardnone')
            check(tag,query={'lang':tag},board='missing-txt')
            check(tag,query={'lang':tag},board='protected')
            status,headers,body=request('GET','/boardtxt?'+urlencode({'lang':tag}))
            local=json.loads((root/'i18n/data'/(tag+'.jsn')).read_text())
            assert status==200 and headers['Content-Language']==tag
            assert html.escape(local['board-not-found'],quote=False).encode() in body
            assert b'Card &lt;test&gt;' not in body

        check('fi',header='fi')
        with sqlite3.connect(database) as con:con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps({'language':'ar'}),))
        check('ar',administrator,header='fi')
        check('fi',administrator,{'lang':'fi'},'he')
        check('fi','invalid',header='fi')
        if os.environ.get('WELITE_UI')=='1':
            subprocess.run([os.environ.get('NODE','node'),str(root/'tests/boardtxt.js'),base],check=True)
        check('en',header='en')
    finally:
        with sqlite3.connect(database) as con:
            con.execute("DELETE FROM page_widgets WHERE pageId='boardtxt'")
            con.execute("DELETE FROM pages WHERE id='boardtxt'")
            con.execute("DELETE FROM lists WHERE boardId='boardtxt'")
            con.execute("DELETE FROM swimlanes WHERE boardId='boardtxt'")
            con.execute("DELETE FROM boards WHERE id IN ('boardtxt','boardnone')")
            con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(profile,))
    print('PASS: all installed native board link/title/empty captions, translated no-lane/not-found states, profile/query/header selection and escaped user titles')

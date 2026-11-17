"""Published board-list views use the frame's resolved language and independent direction."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import urlencode,parse_qs,urlsplit
from homelang import Page
from layout import Forms
root=Path(__file__).resolve().parents[1]

def run(request,database,administrator,member,base):
    with sqlite3.connect(database) as con:
        profiles=con.execute("SELECT id,profile_json FROM users WHERE username IN ('administrator','member')").fetchall()
        uid=con.execute("SELECT id FROM users WHERE username='member'").fetchone()[0]
        con.execute("INSERT INTO boards(id,title,slug,createdAt) VALUES('viewlang','View <private>','viewlang','now')")
        con.execute("INSERT INTO board_members(boardId,userId) VALUES('viewlang',?)",(uid,))
        con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES('viewlang','/viewlang','Language view','html4','auto','anon','now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,binding,createdAt,modifiedAt) VALUES('viewlang','viewlang','dataview','boards','now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,label,target,sort,createdAt,modifiedAt) VALUES('viewlink','viewlang','link','State link','/viewlang#spot',1,'now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,label,target,sort,createdAt,modifiedAt) VALUES('viewbutton','viewlang','button','State button','/viewlang/action',2,'now','now')")
        con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps({'language':'ar','keep':True}),))
        con.execute("UPDATE users SET profile_json=? WHERE username='member'",(json.dumps({'language':'he','keep':True}),))
    def check(tag,session='',query=None,header='fi',direction=None):
        query={} if query is None else dict(query)
        if session:query['sessionId']=session
        status,headers,body=request('GET','/viewlang?'+urlencode(query),extra_headers={'Accept-Language':header})
        assert status==200 and 'Set-Cookie' not in headers
        assert headers['Content-Language']==tag
        assert 'Accept-Language' in headers['Vary']
        expected_dir=direction or ('rtl' if tag in ('ar','he') else 'ltr')
        assert ('dir="'+expected_dir+'"').encode() in body
        local=json.loads((root/'i18n/data'/ (tag+'.jsn')).read_text())
        parsed=Page(body)
        assert ('h2',{},local['boards']) in parsed.items,(tag,parsed.items)
        visible='viewlang' in parsed.board_ids()
        assert visible==(session in (administrator,member)),(tag,visible)
        for name,attrs,_ in parsed.items:
            if name=='a' and urlsplit(attrs['href']).path=='/board':
                assert parse_qs(urlsplit(attrs['href']).query).get('lang')==[tag],attrs
        link=next(attrs['href'] for name,attrs,_ in parsed.items if name=='a' and urlsplit(attrs['href']).fragment=='spot')
        link_query=parse_qs(urlsplit(link).query)
        assert link_query.get('lang')==[tag],link
        if session in (administrator,member):
            assert link_query.get('sessionId')==[session],link
            forms=Forms();forms.feed(body.decode())
            fields=next(fields for action,fields in forms.forms if action=='/viewlang/action')
            assert fields['lang']==tag and fields['sessionId']==session,fields
            assert fields['auth_action']=='widget:viewbutton' and len(fields['auth_hash'])==64
        else:
            assert 'sessionId' not in link_query,link
        return body
    try:
        check('fi')
        check('ar',administrator)
        check('he',member)
        check('fi',administrator,{'lang':'fi'},'he')
        check('ar',administrator,{'lang':'unknown'},'fi')
        check('he','invalid',header='fi;q=0.1,he;q=0.9')
        for direction,tag in [('rtl','fi'),('ltr','ar')]:
            with sqlite3.connect(database) as con:con.execute("UPDATE pages SET dir=? WHERE id='viewlang'",(direction,))
            check(tag,query={'lang':tag},direction=direction)
        with sqlite3.connect(database) as con:con.execute("UPDATE pages SET dir='auto' WHERE id='viewlang'")
        if os.environ.get('WELITE_UI')=='1':
            subprocess.run([os.environ.get('NODE','node'),str(root/'tests/viewlang.js'),base,administrator,member],check=True)
        check('en',header='en')
        with sqlite3.connect(database) as con:
            assert json.loads(con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0])=={'language':'ar','keep':True}
            assert json.loads(con.execute("SELECT profile_json FROM users WHERE username='member'").fetchone()[0])=={'language':'he','keep':True}
    finally:
        with sqlite3.connect(database) as con:
            con.execute("DELETE FROM page_widgets WHERE pageId='viewlang'")
            con.execute("DELETE FROM pages WHERE id='viewlang'")
            con.execute("DELETE FROM board_members WHERE boardId='viewlang'")
            con.execute("DELETE FROM boards WHERE id='viewlang'")
            con.executemany('UPDATE users SET profile_json=? WHERE id=?',[(profile,uid) for uid,profile in profiles])
    print('PASS: published board-list captions/links match query/profile/header frame language, independent saved direction, anonymous/private isolation and unchanged profiles')

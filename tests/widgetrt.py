"""Published board widgets propagate trusted page direction to rendering/mutation."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import parse_qs,urlsplit,urlencode
from layout import Forms

def run(request,database,session,member,base):
    with sqlite3.connect(database) as con:
        original=con.execute("SELECT listId,swimlaneId,sort FROM cards WHERE id='card'").fetchone()
        for direction in ['auto','rtl','ltr']:
            identity='wb-'+direction
            con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES(?,?,?,'html4',?,'admin','now','now')",(identity,'/'+identity,'Board widget',direction))
            con.execute("INSERT INTO page_widgets(id,pageId,type,binding,options_json,createdAt,modifiedAt) VALUES(?,?,'dataview','board',?,'now','now')",('wv-'+direction,identity,json.dumps(dict(boardId='protected'))))
    def form(direction,tag,rtl):
        path='/wb-'+direction+'?'+urlencode(dict(sessionId=session,lang=tag))
        status,headers,body=request('GET',path)
        assert status==200 and headers['Content-Language']==tag
        assert (body.index(b'data-list="doing"')<body.index(b'data-list="todo"'))==rtl
        parser=Forms();parser.feed(body.decode())
        fields=next(fields for action,fields in parser.forms if action=='/board/move')
        assert fields['boardWidget']=='wv-'+direction and fields['back']=='/wb-'+direction
        return fields
    def card():
        with sqlite3.connect(database) as con:return con.execute("SELECT listId FROM cards WHERE id='card'").fetchone()[0]
    try:
        for direction,tag,rtl in [('rtl','fi',True),('ltr','ar',False),('auto','ar',True),('auto','fi',False)]:
            start=card();logical_next=start=='todo'
            physical_right=logical_next!=rtl
            move='right' if physical_right else 'left'
            for step in [move,'left' if move=='right' else 'right']:
                fields=form(direction,tag,rtl)
                status,headers,_=request('POST','/board/move',dict(fields,dir=step,sel_card='card'))
                assert status==302,(direction,tag,status)
                location=urlsplit(headers['Location'])
                assert location.path=='/wb-'+direction and parse_qs(location.query)['lang']==[tag]
                if step==move:assert card()!=start
            assert card()==start
        for change in ['missing','disabled','binding','board']:
            fields=form('rtl','fi',True);before=card()
            with sqlite3.connect(database) as con:
                if change=='disabled':con.execute("UPDATE pages SET enabled=0 WHERE id='wb-rtl'")
                if change=='binding':con.execute("UPDATE page_widgets SET binding='boards' WHERE id='wv-rtl'")
                if change=='board':con.execute("UPDATE page_widgets SET options_json=? WHERE id='wv-rtl'",(json.dumps(dict(boardId='other')),))
            if change=='missing':fields['boardWidget']='missing-widget'
            try:
                status,headers,_=request('POST','/board/move',dict(fields,dir='left',sel_card='card'))
                assert status==400 and headers['Content-Language']=='fi'
                assert card()==before
            finally:
                with sqlite3.connect(database) as con:
                    con.execute("UPDATE pages SET enabled=1 WHERE id='wb-rtl'")
                    con.execute("UPDATE page_widgets SET binding='board',options_json=? WHERE id='wv-rtl'",(json.dumps(dict(boardId='protected')),))
        # A board writer cannot borrow a saved direction from an admin-only page.
        with sqlite3.connect(database) as con:
            permissions=con.execute("SELECT isReadOnly,isCommentOnly FROM board_members WHERE boardId='protected' AND userId=(SELECT id FROM users WHERE username='member')").fetchone()
            con.execute("UPDATE board_members SET isReadOnly=0,isCommentOnly=0 WHERE boardId='protected' AND userId=(SELECT id FROM users WHERE username='member')")
        try:
            status,_,body=request('GET','/board?'+urlencode(dict(id='protected',view='all',sessionId=member,lang='fi')))
            assert status==200
            parser=Forms();parser.feed(body.decode())
            fields=next(fields for action,fields in parser.forms if action=='/board/move')
            before=card()
            status,_,_=request('POST','/board/move',dict(fields,boardWidget='wv-rtl',dir='left',sel_card='card'))
            assert status==400 and card()==before
        finally:
            with sqlite3.connect(database) as con:
                con.execute("UPDATE board_members SET isReadOnly=?,isCommentOnly=? WHERE boardId='protected' AND userId=(SELECT id FROM users WHERE username='member')",permissions)
        if os.environ.get('WELITE_UI')=='1':
            root=Path(__file__).resolve().parent
            subprocess.run([os.environ.get('NODE','node'),str(root/'widgetrt.js'),base,session],check=True)
        print('PASS: board widget fixed/auto RTL rendering and physical moves, origin redirects, invalid/stale/disabled/binding context refusal and unchanged rejected card data')
    finally:
        with sqlite3.connect(database) as con:
            con.execute("UPDATE cards SET listId=?,swimlaneId=?,sort=? WHERE id='card'",original)
            con.execute("DELETE FROM page_widgets WHERE pageId IN ('wb-auto','wb-rtl','wb-ltr')")
            con.execute("DELETE FROM pages WHERE id IN ('wb-auto','wb-rtl','wb-ltr')")

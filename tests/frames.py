"""Consistent viewer metadata on normal page frames and posted selection forms."""
from html.parser import HTMLParser
import json
import sqlite3
from layout import Forms
class Document(HTMLParser):
    def __init__(self):super().__init__();self.html={};self.body={}
    def handle_starttag(self,tag,attrs):
        if tag=='html':self.html=dict(attrs)
        if tag=='body':self.body=dict(attrs)
def check_frames(request,database,session,editor):
    with sqlite3.connect(database) as con:
        original=con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0]
        con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(json.dumps(dict(language='ar',keep=dict(value='unchanged'))),))
        con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES('frames','/frames','Frames','html4','auto','admin','now','now')")
    def check(url,tag='ar',rtl=True):
        status,headers,body=request('GET',url,extra_headers={'Accept-Language':'fi'})
        assert status==200,(url,status)
        document=Document();document.feed(body.decode())
        assert headers['Content-Language']==tag,(url,headers)
        assert 'Accept-Language' in headers['Vary']
        assert document.html['lang']==tag
        assert (document.html.get('dir')=='rtl')==rtl,(url,document.html)
        assert (document.body.get('dir')=='rtl')==rtl
        return body
    try:
        for route in ['/?sessionId=','/board?id=protected&sessionId=','/admin?sessionId=','/admin/people?sessionId=','/designer?sessionId=','/frames?sessionId=']:
            check(route+session)
        check(editor)
        check('/frames?sessionId='+session+'&lang=fi','fi',False)
        # Fixed page direction wins while content language still follows the viewer.
        check('/layout?sessionId='+session+'&lang=fi','fi',True)
        for action in ['edit','delete']:
            body=check('/board?id=protected&view=all&lang=ar&sessionId='+session)
            forms=Forms();forms.feed(body.decode())
            fields=next(fields for path,fields in forms.forms if path=='/board/move')
            status,headers,body=request('POST','/board/move',dict(fields,action=action,sel_card='card'))
            assert status==200 and headers['Content-Language']=='ar'
            document=Document();document.feed(body.decode())
            assert document.html['lang']=='ar' and document.html['dir']=='rtl'
            assert b'name="lang" value="ar"' in body
        def error(method,url,fields,status,tag='ar'):
            result,headers,body=request(method,url,fields,extra_headers={'Accept-Language':'fi'})
            assert result==status,(method,url,result,status)
            document=Document();document.feed(body.decode())
            assert headers['Content-Language']==tag,(url,headers)
            assert 'Accept-Language' in headers['Vary']
            assert document.html['lang']==tag
            assert (document.html.get('dir')=='rtl')==(tag=='ar')
            assert (document.body.get('dir')=='rtl')==(tag=='ar')
        missing='/designer/page?id=missing-frame&sessionId='+session
        error('GET',missing,None,404)
        error('GET',missing+'&lang=fi',None,404,'fi')
        error('GET','/board?id=missing-frame&sessionId='+session,None,404)
        error('GET','/board?id=missing-frame&sessionId='+session+'&lang=fi',None,404,'fi')
        error('GET','/missing-frame?sessionId='+session,None,404)
        error('POST','/designer/widget/move',dict(sessionId=session,lang='fi'),403,'fi')
        error('POST','/designer/widget/move',dict(sessionId=session,lang='unknown'),403)
        body=check('/designer?sessionId='+session)
        forms=Forms();forms.feed(body.decode())
        fields=next(fields for path,fields in forms.forms if path=='/designer/page/save')
        error('POST','/designer/page/save',dict(fields,action='unknown'),400)
        body=check(editor)
        forms=Forms();forms.feed(body.decode())
        fields=next(fields for path,fields in forms.forms if path=='/designer/widget/move')
        error('POST','/designer/widget/move',dict(fields,widgetId='missing-frame',dir='left'),404)
        with sqlite3.connect(database) as con:
            original_card=con.execute("SELECT title,listId,swimlaneId FROM cards WHERE id='card'").fetchone()
        for tag in ['ar','fi']:
            body=check('/board?id=protected&view=all&sessionId='+session)
            forms=Forms();forms.feed(body.decode())
            fields=next(fields for path,fields in forms.forms if path=='/board/move')
            error('POST','/board/move',dict(fields,action='unknown',sel_card='card',lang=tag),400,tag)
        with sqlite3.connect(database) as con:
            assert con.execute("SELECT title,listId,swimlaneId FROM cards WHERE id='card'").fetchone()==original_card
        with sqlite3.connect(database) as con:
            assert json.loads(con.execute("SELECT profile_json FROM users WHERE username='administrator'").fetchone()[0])==dict(language='ar',keep=dict(value='unchanged'))
    finally:
        with sqlite3.connect(database) as con:
            con.execute("UPDATE users SET profile_json=? WHERE username='administrator'",(original,))
            con.execute("DELETE FROM pages WHERE id='frames'")
    print('PASS: home/board/admin/Designer/published/selection language and direction metadata, profile/header/query/posted state, fixed overrides, Designer error frames and unchanged profiles')

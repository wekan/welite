"""Locale survives actual board/Designer/admin links, GET forms and signed mutations."""
from html import escape
from html.parser import HTMLParser
from pathlib import Path
import json
import sqlite3
from urllib.parse import parse_qs,urlsplit,urlencode
from layout import Forms
class Links(HTMLParser):
    def __init__(self):super().__init__();self.links=[]
    def handle_starttag(self,tag,attrs):
        if tag=='a':self.links.append(dict(attrs).get('href',''))
def parsed(body):
    result=Links();result.feed(body.decode());return result.links
def check_navigation(request,database,session):
    def language(url):
        params=parse_qs(urlsplit(url).query)
        assert params.get('lang')==['ar'],url
        return params
    home_body=request('GET','/?'+urlencode(dict(sessionId=session,lang='ar')))[2]
    for link in parsed(home_body):
        if urlsplit(link).path in ['/board','/admin','/sign-in','/register']:
            params=language(link)
            if urlsplit(link).path in ['/sign-in','/register']:assert 'sessionId' not in params
    board='/board?'+urlencode(dict(id='protected',view='all',sessionId=session,lang='ar'))
    status,_,body=request('GET',board);assert status==200
    links=parsed(body)
    for link in links:
        if urlsplit(link).path in ['/','/board']:language(link)
    forms=Forms();forms.feed(body.decode())
    move=next(fields for action,fields in forms.forms if action=='/board/move')
    assert move['lang']=='ar'
    status,headers,_=request('POST','/board/move',dict(move,action='clear'))
    assert status==302;language(headers['Location'])
    assert b'dir="rtl"' in request('GET',headers['Location'])[2]
    status,headers,_=request('GET','/designer?sessionId=invalid&lang=ar')
    assert status==302 and headers['Location']=='/sign-in?lang=ar'
    table=dict(source='users',rowKey='id',pageSize=1,editUrl='/designer/page',search=['username'],columns=[dict(name='username',label='User',editable=True)])
    with sqlite3.connect(database) as con:
        con.execute("INSERT INTO boards(id,title,slug,permission,createdAt,modifiedAt) VALUES('nav&lang=fi','URL board','nav-query','public','now','now')")
        for uid,name in [('navu1','A&lang=fi'),('navu2','B&lang=ar')]:
            con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,loginDisabled) VALUES(?,?,'now','now',1)",(uid,name))
        con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES('navpage','/navtest','Navigation','html4','auto','admin','now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,options_json,createdAt,modifiedAt) VALUES('navtable','navpage','table',?,'now','now')",(json.dumps(table),))
        con.execute("INSERT INTO page_widgets(id,pageId,type,label,target,sort,createdAt,modifiedAt) VALUES('navlink','navpage','link','Fragment','/navtest#spot',1,'now','now')")
    try:
        body=request('GET','/?'+urlencode(dict(sessionId=session,lang='ar')))[2]
        unusual=next(link for link in parsed(body) if parse_qs(urlsplit(link).query).get('id')==['nav&lang=fi'])
        language(unusual)
        status,_,body=request('GET',unusual)
        assert status==200 and b'URL board' in body
        home='/designer?'+urlencode(dict(sessionId=session,lang='ar'))
        status,headers,body=request('GET',home)
        assert status==200 and headers['Content-Language']=='ar' and 'Set-Cookie' not in headers
        arabic=json.loads((Path(__file__).resolve().parents[1]/'i18n/data/ar.jsn').read_text())
        for key in ('page','storage-enabled','actions','yes','edit','preview','r-export'):
            assert ('>'+escape(arabic[key],quote=False)+'<').encode() in body,key
        assert b'dir="rtl"' in body
        edit=next(link for link in parsed(body) if urlsplit(link).path=='/designer/page'
                  and parse_qs(urlsplit(link).query).get('id')==['navpage'])
        status,_,editor=request('GET',edit)
        assert status==200
        for key in ('edit','preview'):
            assert ('>'+escape(arabic[key],quote=False)+'<').encode() in editor,key
        for key in ('add','delete'):
            assert ('type="submit" value="'+escape(arabic[key])+'"').encode() in editor,key
        for form in (body,editor):
            assert ('for="page-title">'+escape(arabic['title'],quote=False)+'<').encode() in form
            assert ('type="submit" value="'+escape(arabic['save'])+'"').encode() in form
            assert b'name="action" value="save"' in form
            assert b'<option value="admin"' in form
        assert b'<option value="admin" selected="selected">' in editor
        for link in parsed(body):
            if urlsplit(link).path in ['/designer/page','/navtest','/designer/export','/designer/page/export']:language(link)
        forms=Forms();forms.feed(body.decode())
        save=next(fields for action,fields in forms.forms if action=='/designer/page/save')
        assert save['lang']=='ar'
        status,headers,_=request('POST','/designer/page/save',dict(save,action='save',pageId='navpage',url='/navtest',title='Updated',cols='1',doctype='html4',dir='auto',minRole='admin'))
        assert status==302;language(headers['Location'])
        status,_,body=request('GET','/navtest?'+urlencode(dict(sessionId=session,lang='ar',tq_navtable='&lang=')))
        assert status==200
        links=parsed(body)
        fragment=next(link for link in links if urlsplit(link).fragment=='spot')
        language(fragment);assert parse_qs(urlsplit(fragment).query)['sessionId']==[session]
        next_page=next(link for link in links if 'tp_navtable=' in link)
        params=language(next_page);assert params['tq_navtable']==['&lang='] and params['sessionId']==[session]
        forms=Forms();forms.feed(body.decode())
        assert any(fields.get('lang')=='ar' for _,fields in forms.forms)
        status,_,body=request('GET','/admin?'+urlencode(dict(sessionId=session,lang='ar')))
        assert status==200
        for link in parsed(body):
            if urlsplit(link).path in ['/designer','/admin/people']:language(link)
        # A request without explicit state does not inherit an earlier request's choice.
        body=request('GET','/board?id=protected&sessionId='+session)[2]
        assert b'name="lang"' not in body
    finally:
        with sqlite3.connect(database) as con:
            con.execute("DELETE FROM page_widgets WHERE pageId='navpage'")
            con.execute("DELETE FROM pages WHERE id='navpage'")
            con.execute("DELETE FROM users WHERE id IN ('navu1','navu2')")
            con.execute("DELETE FROM boards WHERE id='nav&lang=fi'")
    print('PASS: locale in board/Designer/admin links, hidden GET/POST fields, mutation redirects, safe re-login, encoded search, fragments and request isolation')

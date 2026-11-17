"""Data-table structural RTL, visible-column mapping and editable URLs."""
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import sqlite3
import subprocess
from urllib.parse import parse_qs,urlsplit,urlencode
class Headers(HTMLParser):
    def __init__(self):super().__init__();self.headers=[];self.capture=False
    def handle_starttag(self,tag,attrs):
        if tag=='th':self.capture=True;self.headers.append('')
    def handle_data(self,data):
        if self.capture:self.headers[-1]+=data
    def handle_endtag(self,tag):
        if tag=='th':self.capture=False

def run(request,database,session,base):
    options=dict(source='users',rowKey='id',pageSize=1,editUrl='/designer/page',search=['username'],columns=[
        dict(name='username',label='First column',editable=True),dict(name='isAdmin',label='Second column')])
    with sqlite3.connect(database) as con:
        for number in range(3):
            con.execute("INSERT INTO users(id,username,createdAt,modifiedAt,loginDisabled) VALUES(?,?,'now','now',1)",('tabrtl'+str(number),'Table fixture '+str(number)))
        con.execute("INSERT INTO pages(id,url,title,doctype,dir,minRole,createdAt,modifiedAt) VALUES('tabrtl','/tabrtl','Table directions','html4','auto','admin','now','now')")
        con.execute("INSERT INTO page_widgets(id,pageId,type,options_json,createdAt,modifiedAt) VALUES('tabrtl','tabrtl','table',?,'now','now')",(json.dumps(options),))
    try:
        for tag,expected in [('ar',['Second column','First column']),('fi',['First column','Second column'])]:
            path='/tabrtl?'+urlencode(dict(sessionId=session,lang=tag,tp_tabrtl=2))
            status,headers,body=request('GET',path)
            assert status==200 and headers['Content-Language']==tag
            parsed=Headers();parsed.feed(body.decode());assert parsed.headers==expected,(tag,parsed.headers)
            assert (body.index(b'Page 2 /')<body.index(b'<form method="GET">'))==(tag=='ar')
            assert (body.index(b'tp_tabrtl=3')<body.index(b'tp_tabrtl=1'))==(tag=='ar')
            from langnav import parsed as links
            edits=[url for url in links(body) if parse_qs(urlsplit(url).query).get('field')==['username']]
            assert edits and all(parse_qs(urlsplit(url).query)['lang']==[tag] for url in edits)
            status,_,body=request('GET',path+'&tc_tabrtl=username')
            assert status==200
            parsed=Headers();parsed.feed(body.decode());assert parsed.headers==['First column']
            status,_,body=request('GET',path+'&tc_tabrtl=username&tq_tabrtl=Table%20fixture')
            assert status==200
            next_url=next(url for url in links(body) if parse_qs(urlsplit(url).query).get('tp_tabrtl')==['3'])
            query=parse_qs(urlsplit(next_url).query)
            assert query['tc_tabrtl']==['username'] and query['tq_tabrtl']==['Table fixture'] and query['lang']==[tag]
        if os.environ.get('WELITE_UI')=='1':
            subprocess.run([os.environ.get('NODE','node'),str(Path(__file__).with_suffix('.js')),base,session],check=True,timeout=60)
        print('PASS: structurally mirrored data-table headers/cells, selected column mapping and locale-preserving editable URLs')
    finally:
        with sqlite3.connect(database) as con:
            con.execute("DELETE FROM page_widgets WHERE pageId='tabrtl'")
            con.execute("DELETE FROM pages WHERE id='tabrtl'")
            con.execute("DELETE FROM users WHERE id IN ('tabrtl0','tabrtl1','tabrtl2')")

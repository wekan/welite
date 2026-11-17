"""Denied administrator frames use the denied viewer's own language context."""
import json
import sqlite3
from urllib.parse import urlencode
from frames import Document

def run(request,database,admin,member):
    with sqlite3.connect(database) as con:
        originals=con.execute("SELECT username,profile_json FROM users WHERE username IN ('administrator','member')").fetchall()
        for name,language in [('administrator','he'),('member','ar')]:
            con.execute('UPDATE users SET profile_json=? WHERE username=?',(json.dumps(dict(language=language,keep=name)),name))
    def denied(method,path,session,lang='',tag='ar'):
        fields=dict(sessionId=session)
        if lang:fields['lang']=lang
        url=path+('?'+urlencode(fields) if method=='GET' else '')
        status,headers,body=request(method,url,fields if method=='POST' else None,extra_headers={'Accept-Language':'fi'})
        assert status==403,(method,path,status)
        doc=Document();doc.feed(body.decode())
        assert headers['Content-Language']==tag,(path,headers)
        assert 'Accept-Language' in headers['Vary']
        assert doc.html['lang']==tag
        assert (doc.html.get('dir')=='rtl')==(tag in ['ar','he'])
        assert (doc.body.get('dir')=='rtl')==(tag in ['ar','he'])
    try:
        for method,path in [('GET','/admin'),('GET','/admin/people'),('POST','/admin/people'),
                            ('GET','/admin/domains'),('POST','/admin/domains'),
                            ('GET','/designer'),('POST','/designer/widget/move')]:
            denied(method,path,member)
            denied(method,path,member,'fi','fi')
            denied(method,path,member,'unknown')
        for method in ['GET','POST']:
            denied(method,'/admin/domains',admin,tag='he')
            denied(method,'/admin/domains',admin,'fi','fi')
        with sqlite3.connect(database) as con:
            for name,language in [('administrator','he'),('member','ar')]:
                assert json.loads(con.execute('SELECT profile_json FROM users WHERE username=?',(name,)).fetchone()[0])==dict(language=language,keep=name)
    finally:
        with sqlite3.connect(database) as con:
            for name,profile in originals:con.execute('UPDATE users SET profile_json=? WHERE username=?',(profile,name))
    print('PASS: tenant/global administrator denial retains status, viewer-specific profile/query/posted language, matching metadata and unchanged profiles')

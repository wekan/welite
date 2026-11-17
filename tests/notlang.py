"""Unknown UI tenants/routes and hidden boards retain public viewer metadata."""
import json
from urllib.parse import urlencode
from frames import Document
import sqlite3

def run(request,data,session):
    def check(method,path,lang,header,expected,host='lost.example',message=b'Unknown domain'):
        fields=dict(lang=lang)
        url=path+('&' if '?' in path else '?')+urlencode(fields) if method=='GET' else path
        status,headers,body=request(method,url,fields if method=='POST' else None,host=host,extra_headers={'Accept-Language':header})
        assert status==404,(method,path,status)
        assert headers['Content-Type'].startswith('text/html')
        assert headers['Content-Language']==expected
        assert 'Accept-Language' in headers['Vary']
        doc=Document();doc.feed(body.decode())
        assert doc.html['lang']==expected
        assert (doc.html.get('dir')=='rtl')==(expected in ['ar','he'])
        assert (doc.body.get('dir')=='rtl')==(expected in ['ar','he'])
        assert message in body
        return body
    for method,path in [('GET','/'),('GET','/sign-in'),('POST','/sign-in'),
                        ('GET','/register'),('POST','/register'),('GET','/two-factor/setup'),
                        ('POST','/two-factor/confirm'),('GET','/board?id=protected'),
                        ('POST','/board/move'),('GET','/admin'),('GET','/designer'),
                        ('POST','/designer/widget/move'),('GET','/missing-route')]:
        for lang,header,expected in [('ar','fi','ar'),('fi','ar','fi'),('unknown','he','he')]:
            check(method,path,lang,header,expected)
    with sqlite3.connect(data/'admin/files/db/wekan.db') as con:
        for table in ['domains','tenantdirs']:
            assert con.execute('SELECT 1 FROM '+table+' WHERE host=?',('lost.example',)).fetchone() is None
    for path in ['/board?id=protected','/board?id=missing-frame','/board?id=protected&sessionId=invalid']:
        body=check('GET',path,'ar','fi','ar',host='localhost',message=b'Board not found')
        assert b'Private title' not in body and b'Card &lt;test&gt;' not in body
    check('GET','/missing-route?sessionId='+session,'fi','ar','fi',host='localhost',message=b'Not found')
    # API tenant failures continue to use their own JSON handler.
    status,headers,body=request('GET','/api/boards',host='lost.example')
    assert status==404 and headers['Content-Type'].startswith('application/json')
    assert isinstance(json.loads(body),dict)
    print('PASS: unknown UI tenant/route and inaccessible-board 404 metadata, query/posted/header language, no tenant creation or private content and JSON API errors')

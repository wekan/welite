"""JSON/ZIP imports use the editor's rules and cannot partially replace pages."""
from layout import Forms
from urllib.parse import urlencode
from pathlib import Path
import copy
import io
import json
import sqlite3
import zipfile

def run(request,db,session):
    home='/designer?sessionId='+session
    def fields(path):
        parser=Forms()
        parser.feed(request('GET',home)[2].decode())
        return [data for action,data in parser.forms if action==path][0]
    def upload(path, data, name, override=None):
        form=fields(path) if override is None else override
        boundary='welite-boundary-12345'
        body=b''
        for key,value in form.items():
            body+=f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode()
        body+=f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode()+data+f'\r\n--{boundary}--\r\n'.encode()
        return request('POST',path,body,content_type='multipart/form-data; boundary='+boundary)
    def page(url='/imported',title='Original'):
        return {'welite_page':1,'page':dict(url=url,title=title,cols=2,doctype='html4',dir='auto',minRole='admin',enabled=True),'widgets':[dict(type='label',label='Original widget',row=0,col=0,rowspan=1,colspan=1,sort=0,options_json='{}')]}
    def snapshot():
        with sqlite3.connect(db) as con:
            return '\n'.join(con.iterdump())
    before=snapshot()
    assert upload('/designer/page/import',json.dumps(page('/anonymous-upload')).encode(),'denied.wlp',{})[0] in [302,403]
    assert snapshot()==before,'Anonymous multipart import changed data'
    invalid_token=fields('/designer/page/import');invalid_token['auth_hash']='bad'
    assert upload('/designer/page/import',json.dumps(page('/bad-token-upload')).encode(),'denied.wlp',invalid_token)[0]==403
    assert snapshot()==before,'Bad-token multipart import changed data'
    assert upload('/designer/page/import',json.dumps(page()).encode(),'page.wlp')[0]==302
    exported=request('GET','/designer/page/export?'+urlencode(dict(url='/imported',sessionId=session)))
    assert exported[0]==200 and json.loads(exported[2])['page']['title']=='Original'
    assert 'filename="page.wlp"' in exported[1]['Content-Disposition']
    # Shared rule failures must retain the old page ID, widgets and every other row.
    invalid=[]
    bad=page();bad['page']['url']='//evil.example';invalid.append(bad)
    bad=page();bad['page']['minRole']='unknown';invalid.append(bad)
    bad=page();bad['page']['cols']=0;invalid.append(bad)
    bad=page();bad['widgets']=[None];invalid.append(bad)
    bad=page();bad['widgets'][0]['type']='unknown';invalid.append(bad)
    bad=page();bad['widgets'][0]['options_json']='[]';invalid.append(bad)
    bad=page();bad['widgets'][0]['target']='javascript:alert(1)';invalid.append(bad)
    bad=page();bad['widgets'][0]['colspan']=3;invalid.append(bad)
    bad=page();bad['widgets'][0]['rowspan']=2;bad['widgets'].append(dict(type='label',label='overlap',row=1,col=0));invalid.append(bad)
    bad=page();bad['welite_page']=2;invalid.append(bad)
    for bad in invalid:
        before=snapshot()
        status,_,body=upload('/designer/page/import',json.dumps(bad).encode(),'bad.wlp')
        assert status==400,(bad,status,body)
        assert snapshot()==before,'Invalid JSON changed database'
    # Prove rollback on a real write failure after the old page has been deleted.
    with sqlite3.connect(db) as con:
        con.execute("CREATE TRIGGER fail_import BEFORE INSERT ON page_widgets WHEN NEW.label='fail-trigger' BEGIN SELECT RAISE(ABORT,'forced import failure'); END")
    fail=page();fail['widgets'][0]['label']='fail-trigger'
    before=snapshot()
    assert upload('/designer/page/import',json.dumps(fail).encode(),'fail.wlp')[0]==400
    assert snapshot()==before,'Failed SQL replacement was not rolled back'
    def archive(pages, manifest=None, names=None):
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as out:
            for i,doc in enumerate(pages):
                out.writestr(names[i] if names else f'p{i+1:07}.wlp',json.dumps(doc))
            out.writestr('manifest.jsn',json.dumps(manifest or dict(welite_pages=1,count=len(pages),urls=[p['page']['url'] for p in pages])))
        return stream.getvalue()
    first=page(title='New title'); second=page('/zipsecond','Second')
    zipfail=copy.deepcopy(fail);zipfail['page']['url']='/zipfail'
    for bundle in [archive([first,invalid[5]]),archive([first,zipfail]),archive([first,first]),archive([first],dict(welite_pages=1,count=2,urls=['/imported'])),archive([first],names=['../escape.wlp']),archive([first],names=['MANIFEST.JSN']),b'not-a-zip']:
        before=snapshot()
        assert upload('/designer/import',bundle,'pages.zip')[0]==400
        assert snapshot()==before,'ZIP import partially changed database'
    assert upload('/designer/import',archive([first,second]),'pages.zip')[0]==302
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT title FROM pages WHERE url='/imported'").fetchone()[0]=='New title'
        assert con.execute("SELECT title FROM pages WHERE url='/zipsecond'").fetchone()[0]=='Second'
    # Raw JSON shares exactly the form token, carried in explicit headers.
    raw=page('/rawjson','日本語 / العربية')
    raw['widgets'][0]['label']='Suomi 日本語 العربية'
    token=fields('/designer/page/import')
    headers={'X-Welite-Action':token['auth_action'],'X-Welite-Counter':token['auth_counter'],'X-Welite-Hash':token['auth_hash']}
    assert request('POST','/designer/page/import?sessionId='+session,json.dumps(raw).encode(),extra_headers=headers)[0]==302
    with sqlite3.connect(db) as con:
        assert con.execute("SELECT title FROM pages WHERE url='/rawjson'").fetchone()[0]=='日本語 / العربية'
    # A token is still single-use, including when transported in headers.
    assert request('POST','/designer/page/import?sessionId='+session,json.dumps(raw).encode(),extra_headers=headers)[0]==403
    disabled=page('/disabled','Disabled page');disabled['page']['enabled']=False
    assert upload('/designer/page/import',json.dumps(disabled).encode(),'off.wlp')[0]==302
    with sqlite3.connect(db) as con:
        disabled_id=con.execute("SELECT id FROM pages WHERE url='/disabled'").fetchone()[0]
    assert request('GET','/designer/page/export?'+urlencode(dict(id=disabled_id,sessionId=session)))[0]==200
    status,_,data=request('GET','/designer/export?sessionId='+session)
    assert status==200
    with zipfile.ZipFile(io.BytesIO(data)) as bundle:
        docs=[json.loads(bundle.read(name)) for name in bundle.namelist() if name.endswith('.wlp')]
        assert any(doc['page']['url']=='/disabled' and not doc['page']['enabled'] for doc in docs)
        assert all(len(Path(name).stem)<=8 and len(Path(name).suffix)<=4 for name in bundle.namelist())
    assert upload('/designer/import',data,'round.zip')[0]==302
    print('PASS: validated JSON/ZIP imports, rollback on bad models and SQL failures, raw JSON token replay, disabled-page round trip and DOS 8.3 exports')

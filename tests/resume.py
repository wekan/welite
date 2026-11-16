"""Meteor token digests and typed atomic resume-array edits through both backends."""
from concurrent.futures import ThreadPoolExecutor
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def digest(raw):return base64.b64encode(hashlib.sha256(raw.encode()).digest()).decode()
def q(value):return "'"+value.replace("'","''")+"'"
with tempfile.TemporaryDirectory(prefix='wlresume-',dir=os.environ['TMPDIR']) as directory:
    tmp=Path(directory)
    def build(source,out,flags=(),name=None):
        out.mkdir(exist_ok=True)
        result=subprocess.run([os.environ.get('FPC','fpc'),*flags,'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),*(['-o'+str(out/name)] if name else []),str(source)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
    build(root/'tests/resume.lpr',tmp/'pure')
    for raw in ['secret','with +/=-_','Meteor 🔑 日本語','a\0b','x'*4096]:
        result=subprocess.check_output([str(tmp/'pure/resume')],input=json.dumps(dict(mode='hash',token=raw))+'\n',text=True)
        assert json.loads(result)==dict(hash=digest(raw)),raw[:30]
    for raw in ['', 'x'*4097]:
        result=subprocess.check_output([str(tmp/'pure/resume')],input=json.dumps(dict(mode='hash',token=raw))+'\n',text=True)
        assert json.loads(result)==dict(error='invalid')
    build(root/'src/wlfunc.lpr',tmp/'ext',['-Cg','-dWLSQLEXT'],'wlfunc.so')
    for backend,flags in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        out=tmp/backend;build(root/'tests/sjsql.lpr',out,flags);db=out/'main.db'
        env=dict(os.environ);env.pop('WELITE_SQLITE_EXT',None)
        if backend=='cli':env['WELITE_SQLITE_EXT']=str(tmp/'ext/wlfunc.so')
        def sql(text,mode='query'):
            result=subprocess.run([str(out/'sjsql'),str(db),mode],input=text,env=env,capture_output=True,text=True,timeout=30)
            assert result.returncode==0,result.stderr
            return json.loads(result.stdout) if mode=='query' else result.stdout.strip()
        for storage in ['TEXT','BLOB']:
            table='docs_'+storage.lower()
            assert sql('CREATE TABLE '+table+'(_ferretdb_sjson '+storage+' NOT NULL) STRICT;','exec')=='ok'
            wrap=(lambda value:'jsonb('+value+')') if storage=='BLOB' else (lambda value:value)
            assert sql('INSERT INTO '+table+' VALUES('+wrap("wl_sjson('{\"_id\":\"u\",\"unknown\":{\"keep\":true}}','','{}')")+');','exec')=='ok'
            def read():return json.loads(sql('SELECT json(_ferretdb_sjson) FROM '+table+';')[0][0])
            def edit(command):
                return sql('UPDATE '+table+' SET _ferretdb_sjson='+wrap('wl_resume(json(_ferretdb_sjson),'+q(json.dumps(command))+')')+';','exec')
            assert edit(dict(op='remove',hashedToken=digest('absent')))=='ok' and 'services' not in read()
            assert edit(dict(op='append',hashedToken=digest('first'),when=-1))=='ok'
            current=read();resume=current['services']['resume'];assert resume['loginTokens']==[dict(hashedToken=digest('first'),when=-1)]
            schema=current['$s']['p']['services']['$s']['p']['resume']['$s']['p']['loginTokens']['i'][0]
            assert schema['$s']['p']['when']==dict(t='date')
            before=read()
            for command in [dict(op='append',hashedToken=digest('first'),when=1),dict(op='append',hashedToken='a'*64,when=1),dict(op='append',hashedToken=digest('x').rstrip('='),when=1),dict(op='append',hashedToken=digest('x'),when='2026-11-16'),dict(op='append',hashedToken=digest('x'),when=1.5),dict(op='append',hashedToken=digest('x'),when=2**63),dict(op='append',hashedToken=digest('x'),when=1,token='never-store'),dict(op='clear',hashedToken=digest('first')),dict(op='unknown')]:
                assert edit(command)=='error',command
                assert read()==before,'Rejected resume edit changed its source'
            assert edit(dict(op='append',hashedToken=digest('second'),when=2**63-1))=='ok'
            assert edit(dict(op='remove',hashedToken=digest('first')))=='ok'
            current=read();assert current['services']['resume']['loginTokens']==[dict(hashedToken=digest('second'),when=2**63-1)]
            assert current['$s']['p']['services']['$s']['p']['resume']['$s']['p']['loginTokens']['i'][0]['$s']['p']['when']==dict(t='date')
            with ThreadPoolExecutor(max_workers=16) as pool:
                results=list(pool.map(lambda i:edit(dict(op='append',hashedToken=digest('unique-'+str(i)),when=1794835200000+i)),range(16)))
            assert results==['ok']*16,results
            assert len(read()['services']['resume']['loginTokens'])==17,'Concurrent appends lost another token'
            with ThreadPoolExecutor(max_workers=16) as pool:
                results=list(pool.map(lambda i:edit(dict(op='append',hashedToken=digest('same'),when=1794835200000+i)),range(16)))
            assert results.count('ok')==1 and results.count('error')==15,results
            assert edit(dict(op='clear'))=='ok'
            current=read();assert current['services']['resume']['loginTokens']==[] and current['unknown']==dict(keep=True)
            # Malformed containers are never replaced silently.
            for document in [dict(services=None),dict(services=dict(resume='bad')),dict(services=dict(resume=dict(loginTokens=None))),dict(services=dict(resume=dict(loginTokens={})))]:
                assert sql('UPDATE '+table+' SET _ferretdb_sjson='+wrap('wl_sjson('+q(json.dumps(document))+",'','{}')")+';','exec')=='ok'
                before=read();assert edit(dict(op='append',hashedToken=digest('new'),when=1))=='error' and read()==before
                if isinstance(document.get('services'),dict) and isinstance(document['services'].get('resume'),dict):
                    assert edit(dict(op='clear'))=='ok' and read()['services']['resume']['loginTokens']==[]
        print('PASS: '+backend+' Meteor SHA256/base64 hashes, typed Date append/remove/clear, strict input, TEXT/JSONB atomic writes, 16 concurrent distinct tokens and one duplicate winner')

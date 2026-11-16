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
            def replace(document):
                assert sql('UPDATE '+table+' SET _ferretdb_sjson='+wrap('wl_sjson('+q(json.dumps(document))+",'','{}')")+';','exec')=='ok'
            def state(raw,at=1000,life=1000):
                return sql('SELECT wl_rescheck(json(_ferretdb_sjson),'+q(digest(raw))+','+str(at)+','+str(life)+') FROM '+table+';')[0][0]
            entries=[dict(hashedToken=digest('numeric'),when=99),dict(hashedToken=digest('fraction'),when=99.9),dict(token='legacy',when=1),dict(hashedToken=digest('missing')),dict(hashedToken=digest('string'),when='100')]
            replace(dict(services=dict(resume=dict(loginTokens=entries,keep=True)),unknown=dict(keep=True)))
            assert edit(dict(op='append',hashedToken=digest('dated'),when=100))=='ok'
            assert state('dated',1099)=='valid' and state('dated',1100)=='expired'
            assert state('dated',100,0.5)=='expired'
            assert state('dated',100,1.5)=='valid' and state('dated',101,1.5)=='expired'
            assert state('numeric',1098)=='valid' and state('numeric',1099)=='expired'
            assert state('fraction',1098)=='valid' and state('fraction',1099)=='expired'
            assert state('missing')=='invalid' and state('string')=='invalid'
            assert state('absent')=='absent' and state('legacy')=='absent'
            assert state('dated',0)=='valid','Future-issued timestamps must follow the explicit lifetime policy'
            for at,life in [(1000,0),(1000,-1),(8640000000000001,1000),(0,17280000000000001)]:assert state('dated',at,life)=='invalid'
            original=read()
            assert edit(dict(op='expire',before=100,hashedToken=digest('dated')))=='error' and read()==original
            assert edit(dict(op='expire',before=2**63-1))=='error' and read()==original
            assert edit(dict(op='expire',before=100))=='ok'
            current=read();remaining=current['services']['resume']['loginTokens']
            assert remaining==[entries[3],entries[4],dict(hashedToken=digest('dated'),when=100)]
            assert current['services']['resume']['keep'] is True and current['unknown']==dict(keep=True)
            assert state('dated',1099)=='valid','Pruning shifted or lost the retained Date schema'
            replace(dict(services=dict(resume=dict(loginTokens=[dict(hashedToken=digest('one'),when=1),dict(token='one',when=2),dict(hashedToken=digest('other'),when=3),'unknown']))))
            assert edit(dict(op='revoke',token='one'))=='ok'
            assert read()['services']['resume']['loginTokens']==[dict(hashedToken=digest('other'),when=3),'unknown']
            # Duplicate hash records are ambiguous even if only one is unexpired.
            replace(dict(services=dict(resume=dict(loginTokens=[dict(hashedToken=digest('duplicate'),when=1),dict(hashedToken=digest('duplicate'),when=1000)]))))
            assert state('duplicate',1000)=='invalid'
            for stamp,at,life,expected in [(8640000000000000,0,1,'invalid'),(8640000000000000-1,8640000000000000-1,1,'valid'),(-8640000000000000,-8640000000000000,1,'valid'),(-8640000000000000,-8640000000000000+1,1,'expired'),(2**63-1,0,1,'invalid')]:
                replace(dict(services=dict(resume=dict(loginTokens=[dict(hashedToken=digest('edge'),when=stamp)]))))
                assert state('edge',at,life)==expected,(stamp,at,life)
            # Malformed containers are never replaced silently.
            for document in [dict(services=None),dict(services=dict(resume='bad')),dict(services=dict(resume=dict(loginTokens=None))),dict(services=dict(resume=dict(loginTokens={})))]:
                assert sql('UPDATE '+table+' SET _ferretdb_sjson='+wrap('wl_sjson('+q(json.dumps(document))+",'','{}')")+';','exec')=='ok'
                before=read();assert edit(dict(op='append',hashedToken=digest('new'),when=1))=='error' and read()==before
                if isinstance(document.get('services'),dict) and isinstance(document['services'].get('resume'),dict):
                    assert edit(dict(op='clear'))=='ok' and read()['services']['resume']['loginTokens']==[]
        print('PASS: '+backend+' Meteor SHA256/base64 hashes, typed Date append/remove/clear, strict input, TEXT/JSONB atomic writes, 16 concurrent distinct tokens, one duplicate winner, typed/legacy validity, expiry boundaries and pruning')

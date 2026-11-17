"""Definition batches validate all source BSON and stored administrative flags."""
from contextlib import contextmanager
import copy
import json
import os
from pathlib import Path
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
root=Path(__file__).resolve().parents[1]
@contextmanager
def connect(path):
    con=sqlite3.connect(path)
    try:
        with con:yield con
    finally:con.close()
def schema(value):
    if isinstance(value,dict):return dict(t='object',**{'$s':{'$k':list(value),'p':{key:schema(item) for key,item in value.items()}}})
    if isinstance(value,list):return dict(t='array',i=[schema(item) for item in value])
    return dict(t='null' if value is None else 'bool' if isinstance(value,bool) else 'long' if isinstance(value,int) else 'string')
def typed(value):return dict(value,**{'$s':schema(value)['$s']})
board="board ' 漢"
with tempfile.TemporaryDirectory(prefix='wldefb-',dir=os.environ['TMPDIR']) as directory:
    for backend,options in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=Path(directory)/(backend+mode);out.mkdir();db=out/'source.db'
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*options,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/defbatch.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            def run(expected,env=None,memory=False):
                def cap_memory():
                    import resource
                    resource.setrlimit(resource.RLIMIT_AS,(96*1024*1024,96*1024*1024))
                result=subprocess.run([str(out/'defbatch'),str(db),board],env=env,capture_output=True,text=True,timeout=180,preexec_fn=cap_memory if memory else None)
                assert result.returncode==0 and result.stdout.strip()==str(expected),(result.stdout,result.stderr,expected)
            for storage in ['text','blob']:
                db.unlink(missing_ok=True)
                with connect(db) as con:
                    con.executescript("CREATE TABLE owned(_ferretdb_sjson ANY) STRICT; CREATE TABLE _wl_models(name TEXT,table_name TEXT); CREATE TABLE _ferretdb_collections(name TEXT,table_name TEXT); INSERT INTO _wl_models VALUES('custom_fields','owned'); INSERT INTO _ferretdb_collections VALUES('customFields','owned'); CREATE VIEW custom_fields AS SELECT json_extract(_ferretdb_sjson,'$._id') id FROM owned; CREATE VIEW custom_field_boards AS SELECT json_extract(d._ferretdb_sjson,'$._id') customFieldId,b.value boardId FROM owned d,json_each(json_extract(d._ferretdb_sjson,'$.boardIds')) b;")
                    con.execute('CREATE INDEX owned_id ON owned(json_extract(_ferretdb_sjson,\'$."_id"\'))')
                expression='jsonb(?)' if storage=='blob' else '?'
                def insert(document):
                    with connect(db) as con:con.execute('INSERT INTO owned VALUES('+expression+')',(json.dumps(document),))
                def clear():
                    with connect(db) as con:con.execute('DELETE FROM owned')
                run(0)
                original=typed(dict(_id="field ' 漢",boardIds=[board]))
                for flag in ['missing',None,False,True,12,'false']:
                    clear();doc=copy.deepcopy(original)
                    if flag!='missing':doc=typed(dict(_id="field ' 漢",boardIds=[board],adminOnly=flag))
                    insert(doc);run('error' if flag in [12,'false'] else 1 if flag is True else 0)
                # JSON.stringify can turn invalid nonboolean BSON into null.
                for value,kind,extra in [(8640000000000001,'date',{}),('NaN','double',{})]:
                    clear();doc=typed(dict(_id='typed-flag',boardIds=[board],adminOnly=value));doc['$s']['p']['adminOnly']=dict(t=kind,**extra);insert(doc);run('error')
                clear();insert(original);insert(original);run('error')
                clear();insert(typed(dict(_id=12,boardIds=[board])));run('error')
                clear();insert(original)
                with connect(db) as con:con.execute("INSERT INTO _ferretdb_collections VALUES('customFields','owned')")
                run('error')
                with connect(db) as con:con.execute('DELETE FROM _ferretdb_collections WHERE rowid=(SELECT max(rowid) FROM _ferretdb_collections)')
                with connect(db) as con:
                    con.execute('DROP VIEW custom_fields');con.execute("CREATE VIEW custom_fields AS SELECT 'absent' id")
                    con.execute('DROP VIEW custom_field_boards');con.execute("CREATE VIEW custom_field_boards AS SELECT 'absent' customFieldId,'board '' 漢' boardId")
                run('error')
                with connect(db) as con:
                    con.execute('DROP VIEW custom_fields');con.execute("CREATE VIEW custom_fields AS SELECT json_extract(_ferretdb_sjson,'$._id') id FROM owned")
                    con.execute('DROP VIEW custom_field_boards');con.execute("CREATE VIEW custom_field_boards AS SELECT json_extract(d._ferretdb_sjson,'$._id') customFieldId,b.value boardId FROM owned d,json_each(json_extract(d._ferretdb_sjson,'$.boardIds')) b")
                run(0)
                if backend=='cli' and mode=='normal' and storage=='text':
                    wrapper=out/'tracebin';wrapper.mkdir();trace=out/'calls';cli=shutil.which('sqlite3');assert cli
                    script=wrapper/'sqlite3';script.write_text('#!/bin/sh\nprintf x >> '+shlex.quote(str(trace))+'\nexec '+shlex.quote(cli)+' "$@"\n');script.chmod(0o700)
                    env=dict(os.environ,PATH=str(wrapper)+os.pathsep+os.environ['PATH'])
                    trace.write_text('');run(0,env);one=trace.stat().st_size;assert one>0
                    for index in range(130):insert(typed(dict(_id='field '+str(index),boardIds=[board],adminOnly=False)))
                    trace.write_text('');run(0,env);assert trace.stat().st_size==one,'Per-definition subprocess regression'
                insert(typed(dict(_id='private',boardIds=[board],adminOnly=True)));run(1)
                bad=typed(dict(_id='late',boardIds=[board]));bad['$s']['p']['unknown']=dict(t='string');insert(bad);run('error')
                clear();insert(original);bad=typed(dict(_id='other',boardIds=['other']));bad['$s']['p']['unknown']=dict(t='string');insert(bad);run(0)
                with connect(db) as con:con.execute('DROP TABLE owned')
                run('error')
            db.unlink()
            with connect(db) as con:
                con.executescript((root/'src/schema.sql').read_text())
                con.execute("INSERT INTO custom_fields(id,name,type,modifiedAt,currencyCode,settings_json) VALUES('native','Native','text','now','EUR',?)",(json.dumps(dict(future=dict(value='漢'))),))
                con.execute("INSERT INTO custom_field_boards VALUES('native',?)",(board,))
            run(0)
            with connect(db) as con:con.execute("UPDATE custom_fields SET adminOnly=1")
            run(1)
            for settings in ['{broken','[]','{"currencyCode":"shadow"}','{"dropdownItems":[]}','{"future":1,"future":2}']:
                with connect(db) as con:
                    con.execute('PRAGMA ignore_check_constraints=ON')
                    con.execute('UPDATE custom_fields SET settings_json=?',(settings,))
                run('error')
            with connect(db) as con:con.execute("UPDATE custom_fields SET settings_json='{}'")
            for flag in ['false',2,0.5]:
                with connect(db) as con:
                    con.execute('PRAGMA ignore_check_constraints=ON')
                    con.execute('UPDATE custom_fields SET adminOnly=?',(flag,))
                run('error')
            with connect(db) as con:
                con.execute('UPDATE custom_fields SET adminOnly=0')
                con.execute('PRAGMA ignore_check_constraints=ON')
                con.execute("INSERT INTO custom_fields(id,name,type,modifiedAt,settings_json,adminOnly) VALUES('outside','Other','text','now','broken','false')")
                con.execute("INSERT INTO custom_field_boards VALUES('outside','other')")
            run(0)
            if mode=='normal' and sys.platform.startswith('linux'):
                large=json.dumps(dict(future='x'*65536))
                with connect(db) as con:
                    con.execute('DELETE FROM custom_field_boards');con.execute('DELETE FROM custom_fields')
                    con.execute("WITH RECURSIVE seq(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM seq WHERE n<2048) INSERT INTO custom_fields(id,name,type,modifiedAt,settings_json) SELECT 'memory '||n,'Memory','text','now',? FROM seq",(large,))
                    con.execute('INSERT INTO custom_field_boards SELECT id,? FROM custom_fields',(board,))
                    count,size=con.execute('SELECT count(*),sum(length(settings_json)) FROM custom_fields').fetchone()
                    assert count==2048 and size>128*1024*1024,(count,size)
                run(0,memory=True)
                with connect(db) as con:
                    con.execute('PRAGMA ignore_check_constraints=ON')
                    con.execute("UPDATE custom_fields SET settings_json='broken' WHERE id='memory 2048'")
                run('error',memory=True)
                print('PASS:',backend,'over 128 MiB of native settings under a 96 MiB address-space limit')
            print('PASS:',backend,mode,'TEXT/JSONB/native definition batches, storage flags, settings, cardinality/ownership, late corruption and other-board isolation')

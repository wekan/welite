"""Complete BSON source batches preserve cardinality, ownership and CLI cost."""
import copy
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shlex
import shutil
import sqlite3
import subprocess
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
    return dict(t='null' if value is None else 'long' if isinstance(value,int) else 'string')
def typed(value):return dict(value,**{'$s':schema(value)['$s']})
with tempfile.TemporaryDirectory(prefix='wlcfsb-',dir=os.environ['TMPDIR']) as directory:
    for backend,options in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=Path(directory)/(backend+mode);out.mkdir();db=out/'source.db'
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*options,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/cfsbatch.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            def run(expected,env=None):
                result=subprocess.run([str(out/'cfsbatch'),str(db),"board ' 漢"],env=env,capture_output=True,text=True)
                assert result.returncode==0 and result.stdout.strip()==str(expected),(result.stdout,result.stderr,expected)
            for storage in ['text','blob']:
                db.unlink(missing_ok=True)
                with connect(db) as con:
                    con.executescript('CREATE TABLE owned(_ferretdb_sjson ANY) STRICT; CREATE TABLE _wl_models(name TEXT,table_name TEXT); CREATE TABLE _ferretdb_collections(name TEXT,table_name TEXT); INSERT INTO _wl_models VALUES(\'cards\',\'owned\'); INSERT INTO _ferretdb_collections VALUES(\'cards\',\'owned\'); CREATE VIEW cards AS SELECT json_extract(_ferretdb_sjson,\'$._id\') id,json_extract(_ferretdb_sjson,\'$.boardId\') boardId FROM owned;')
                    con.execute('CREATE INDEX owned_id ON owned(json_extract(_ferretdb_sjson,\'$."_id"\'))')
                expression='jsonb(?)' if storage=='blob' else '?'
                def insert(document):
                    with connect(db) as con:con.execute('INSERT INTO owned VALUES('+expression+')',(json.dumps(document),))
                def clear():
                    with connect(db) as con:con.execute('DELETE FROM owned')
                run(1)
                original=typed(dict(_id="card ' 漢",boardId="board ' 漢"))
                for fields in ['missing',None,[],{},[dict(_id='f')],[dict(_id='f',value=None)]]:
                    clear();doc=copy.deepcopy(original)
                    if fields!='missing':doc=typed(dict(_id="card ' 漢",boardId="board ' 漢",customFields=fields))
                    insert(doc);run(1)
                    broken=copy.deepcopy(doc);broken['$s']['p']['unknown']=dict(t='string')
                    clear();insert(broken);run(0)
                for invalid in [['scalar'],[dict(_id=['not a scalar'])]]:
                    clear();insert(typed(dict(_id='invalid',boardId="board ' 漢",customFields=invalid)));run(0)
                clear();insert(typed(dict(_id=12,boardId="board ' 漢")));run(0)
                clear();insert(original);insert(original);run(0)
                clear();insert(original)
                with connect(db) as con:con.execute("INSERT INTO _ferretdb_collections VALUES('cards','owned')")
                run(0)
                with connect(db) as con:con.execute('DELETE FROM _ferretdb_collections WHERE rowid=(SELECT max(rowid) FROM _ferretdb_collections)')
                with connect(db) as con:
                    con.execute('DROP VIEW cards');con.execute("CREATE VIEW cards AS SELECT 'absent' id,'board '' 漢' boardId")
                run(0)
                with connect(db) as con:
                    con.execute('DROP VIEW cards');con.execute("CREATE VIEW cards AS SELECT json_extract(_ferretdb_sjson,'$._id') id,json_extract(_ferretdb_sjson,'$.boardId') boardId FROM owned")
                clear();insert(original);run(1)
                if backend=='cli' and mode=='normal' and storage=='text':
                    wrapper=out/'tracebin';wrapper.mkdir();trace=out/'calls';cli=shutil.which('sqlite3');assert cli
                    script=wrapper/'sqlite3';script.write_text('#!/bin/sh\nprintf x >> '+shlex.quote(str(trace))+'\nexec '+shlex.quote(cli)+' "$@"\n');script.chmod(0o700)
                    env=dict(os.environ,PATH=str(wrapper)+os.pathsep+os.environ['PATH'])
                    trace.write_text('');run(1,env);one=trace.stat().st_size;assert one>0
                    for index in range(70):insert(typed(dict(_id='card '+str(index),boardId="board ' 漢",customFields=[dict(_id='f',value='value')])))
                    trace.write_text('');run(1,env);assert trace.stat().st_size==one,'Per-card subprocess regression'
                    late=typed(dict(_id='late',boardId="board ' 漢"));late['$s']['p']['unknown']=dict(t='string');insert(late);run(0)
                # Invalid full metadata outside the requested board stays out of scope.
                clear();insert(original);bad=typed(dict(_id='other',boardId='other'));bad['$s']['p']['unknown']=dict(t='string');insert(bad);run(1)
                with connect(db) as con:con.execute('DROP TABLE owned')
                run(0)
            with connect(db) as con:
                con.executescript('DROP VIEW cards; CREATE TABLE cards(id TEXT,boardId TEXT); DROP TABLE _wl_models; DROP TABLE _ferretdb_collections;')
            run(1)
            print('PASS:',backend,mode,'TEXT/JSONB complete source batches, null/missing fields, corrupt metadata, missing/duplicate sources, ownership and native fallback')

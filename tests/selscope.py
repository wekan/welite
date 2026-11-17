"""Typed root scope predicates, ownership pins and indexed physical identity probes."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def schema(value):
    if isinstance(value,dict):return dict(t='object',**{'$s':{'$k':list(value),'p':{key:schema(item) for key,item in value.items()}}})
    if isinstance(value,list):return dict(t='array',i=[schema(item) for item in value])
    return dict(t='null' if value is None else 'long' if isinstance(value,int) else 'string')
def typed(value):return dict(value,**{'$s':schema(value)['$s']})
owner='0123456789abcdef01234567'
def q(text):return "'"+text.replace("'","''")+"'"
with tempfile.TemporaryDirectory(prefix='wlscope-',dir=os.environ['TMPDIR']) as directory:
    for backend,extra in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=Path(directory)/(backend+mode);out.mkdir()
            result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*extra,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/selscope.lpr')],capture_output=True,text=True)
            assert result.returncode==0,result.stdout+result.stderr
            count=0
            for table,path in [('cards','boardId'),('attachments','meta.boardId')]:
                for storage in ['text','blob']:
                    database=out/'scope.db'
                    def setup():
                        database.unlink(missing_ok=True)
                        with sqlite3.connect(database) as con:
                            con.executescript('CREATE TABLE owned(_ferretdb_sjson ANY) STRICT; CREATE INDEX owned_id ON owned(json_extract(_ferretdb_sjson,\'$._id\')); CREATE TABLE _wl_models(name TEXT PRIMARY KEY,table_name TEXT,spec TEXT,version INTEGER); CREATE TABLE _ferretdb_collections(name TEXT,table_name TEXT,settings TEXT);')
                            # Match the exact quoted JSON path used by the production root index.
                            con.execute('DROP INDEX owned_id');con.execute('CREATE INDEX owned_id ON owned(json_extract(_ferretdb_sjson,\'$."_id"\'))')
                            spec=dict(table=table,collection=table,fields=[dict(name='id',path='_id'),dict(name='boardId',path=path)])
                            con.execute('INSERT INTO _wl_models VALUES(?,?,?,1)',(table,'owned',json.dumps(spec)))
                            con.execute('INSERT INTO _ferretdb_collections VALUES(?,?,?)',(table,'owned','{"uuid":"original"}'))
                            con.execute('CREATE VIEW '+table+' AS SELECT json_extract(_ferretdb_sjson,\'$._id\') id,json_extract(_ferretdb_sjson,'+q('$.'+path)+') boardId FROM owned')
                            for identity,kind,value in [('plain','string',owner),('regex','regex',owner),('oid','objectId',owner),('number','long',7),('null','null',None),('missing','missing',None),('foreign','string','foreign')]:
                                plain=dict(_id=identity)
                                if kind!='missing':
                                    if table=='cards':plain['boardId']=value
                                    else:plain['meta']=dict(boardId=value)
                                document=typed(plain)
                                if kind not in ['missing','long','null','string']:
                                    node=document['$s']['p'] if table=='cards' else document['$s']['p']['meta']['$s']['p']
                                    node['boardId']=dict(t=kind,**({'o':''} if kind=='regex' else {}))
                                expression='jsonb(?)' if storage=='blob' else '?'
                                con.execute('INSERT INTO owned VALUES('+expression+')',(json.dumps(document),))
                            document=typed(dict(_id=owner,**({'boardId':owner} if table=='cards' else {'meta':dict(boardId=owner)})))
                            document['$s']['p']['_id']=dict(t='objectId')
                            con.execute('INSERT INTO owned VALUES('+('jsonb(?)' if storage=='blob' else '?')+')',(json.dumps(document),))
                    def run(command):
                        result=subprocess.run([str(out/'selscope'),str(database)],input=json.dumps(dict(dict(table=table,match=owner),**command))+'\n',capture_output=True,text=True)
                        assert result.returncode==0,result.stderr
                        actual=json.loads(result.stdout)
                        if 'expression' in actual:
                            expression=actual.pop('expression')
                            with sqlite3.connect(database) as con:
                                plan=con.execute('EXPLAIN QUERY PLAN SELECT id FROM '+table+' WHERE '+command.get('column','boardId')+'='+q(owner)+' AND '+expression).fetchall()
                            actual['indexed']=any('owned_id' in row[3] for row in plan)
                        return actual
                    setup();actual=run({});assert actual==dict(ids=['plain'],indexed=True),actual;count+=1
                    assert run(dict(column='id'))['ids']==[];count+=1
                    mutations=["UPDATE _wl_models SET version=2;","UPDATE _ferretdb_collections SET settings='{\"uuid\":\"changed\"}';",
                               'DROP VIEW '+table+'; CREATE VIEW '+table+" AS SELECT json_extract(_ferretdb_sjson,'$._id') id,'foreign' boardId FROM owned;"]
                    for mutation in mutations:
                        setup();assert run(dict(after=mutation))==dict(error=True);count+=1
                    setup();assert run(dict(before='DELETE FROM _wl_models;'))==dict(error=True);count+=1
                    setup();assert run(dict(before="UPDATE _wl_models SET spec=json_set(spec,'$.fields[1].path','wrong');"))==dict(error=True);count+=1
                    setup()
                    duplicate=typed(dict(_id=owner,**({'boardId':owner} if table=='cards' else {'meta':dict(boardId=owner)})))
                    assert run(dict(column='id',after='INSERT INTO owned VALUES('+q(json.dumps(duplicate))+');'))==dict(error=True);count+=1
                    setup()
                    with sqlite3.connect(database) as con:
                        con.execute('DROP VIEW '+table)
                        con.execute('CREATE VIEW '+table+' AS SELECT json_extract(_ferretdb_sjson,\'$._id\') id,'+q(owner)+' boardId FROM owned')
                    # The displayed foreign row cannot borrow a canonical source value.
                    assert run({})['ids']==['plain'];count+=1
                    for cast_column in ['id','boardId']:
                        setup()
                        plain=dict(_id='7' if cast_column=='id' else 'plain')
                        value='7' if cast_column=='boardId' else owner
                        if table=='cards':plain['boardId']=value
                        else:plain['meta']=dict(boardId=value)
                        with sqlite3.connect(database) as con:
                            con.execute('DELETE FROM owned')
                            con.execute('INSERT INTO owned VALUES('+('jsonb(?)' if storage=='blob' else '?')+')',(json.dumps(typed(plain)),))
                            con.execute('DROP VIEW '+table)
                            id_expr="json_extract(_ferretdb_sjson,'$._id')"
                            board_expr='json_extract(_ferretdb_sjson,'+q('$.'+path)+')'
                            if cast_column=='id':id_expr='CAST('+id_expr+' AS INTEGER)'
                            else:board_expr='CAST('+board_expr+' AS INTEGER)'
                            con.execute('CREATE VIEW '+table+' AS SELECT '+id_expr+' id,'+board_expr+' boardId FROM owned')
                        assert run(dict(match=value))['ids']==[];count+=1

            native=out/'native.db'
            with sqlite3.connect(native) as con:con.executescript("CREATE TABLE cards(id TEXT,boardId TEXT); INSERT INTO cards VALUES('native','"+owner+"');")
            result=subprocess.run([str(out/'selscope'),str(native)],input=json.dumps(dict(match=owner))+'\n',capture_output=True,text=True)
            assert result.returncode==0 and json.loads(result.stdout)==dict(ids=['native'],expression='1'),result.stdout+result.stderr
            print('PASS:',backend,mode,count,'TEXT/JSONB typed scope, nested mapping, identity/epoch/view pins and indexed probes; native behavior retained')

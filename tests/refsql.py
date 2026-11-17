"""Execute generated typed-reference/cascade SQL with normal and checked functions."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def typed(value,overrides=None):
    return dict(value,**{'$s':{'$k':list(value),'p':{name:dict(t=(overrides or {}).get(name,'null' if item is None else 'long' if isinstance(item,int) else 'string'),**({'o':''} if (overrides or {}).get(name)=='regex' else {})) for name,item in value.items()}}})
fields=[dict(name='id',path='_id'),dict(name='boardId',path='boardId')]
model=dict(table='lists',fields=fields,managed=[],foreignKeys=[dict(column='boardId',parent='boards',key='id',delete='CASCADE')])
models=[dict(table='boards',fields=[fields[0]],foreignKeys=[]),model]
commands=[dict(model=model,tables=dict(boards='pboards',lists='plists')),dict(mode='delete',models=models,tables=dict(boards='pboards',lists='plists'))]
owner='0123456789abcdef01234567'
parent=typed(dict(_id=owner,unknown=0),dict(unknown='date'))
source=typed(dict(_id='child',boardId=owner))
cases=[(parent,source,True),(parent,typed(dict(_id='null',boardId=None)),True),(parent,typed(dict(_id='missing')),True),
       (parent,typed(dict(_id='wrong',boardId='foreign')),False),
       (typed(dict(_id=owner),dict(_id='objectId')),source,False),
       (parent,typed(dict(_id='regex',boardId=owner),dict(boardId='regex')),False),
       (parent,typed(dict(_id='oid',boardId=owner),dict(boardId='objectId')),False),
       (typed(dict(_id="board ' 漢")),typed(dict(_id='quoted',boardId="board ' 漢")),True),
       (typed(dict(_id='Board')),typed(dict(_id='case',boardId='board')),False)]
bad=copy.deepcopy(parent);bad['$s']['$k'].remove('_id');cases.append((bad,source,False))
cases.extend([(bad,typed(dict(_id='null',boardId=None)),True),(bad,typed(dict(_id='missing')),True)])
with tempfile.TemporaryDirectory(prefix='wlrefsql-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        def build(source_path,dest,extra=()):
            result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,*extra,'-Fu'+str(root/'src'),'-FU'+str(dest),'-FE'+str(dest),str(source_path)],capture_output=True,text=True)
            assert result.returncode==0,result.stdout+result.stderr
        build(root/'tests/refkind.lpr',out)
        result=subprocess.run([str(out/'refkind')],input='\n'.join(json.dumps(value) for value in commands)+'\n',capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        generated=[json.loads(line)['sql'] for line in result.stdout.splitlines()]
        ext=out/'ext';ext.mkdir();build(root/'src/wlfunc.lpr',ext,('-Cg','-dWLSQLEXT','-o'+str(ext/'wlfunc.so')))
        con=sqlite3.connect(':memory:');con.enable_load_extension(True);con.load_extension(str(ext/'wlfunc.so'))
        con.executescript('CREATE TABLE pboards(_ferretdb_sjson ANY) STRICT; CREATE TABLE plists(_ferretdb_sjson ANY) STRICT; CREATE TABLE probe(_ferretdb_sjson ANY) STRICT; CREATE TRIGGER refs BEFORE INSERT ON probe BEGIN '+generated[0]+' END;')
        for parent_storage in ['text','blob']:
            for child_storage in ['text','blob']:
                for parent_doc,child_doc,expected in cases:
                    con.executescript('DELETE FROM pboards; DELETE FROM probe;')
                    expr='jsonb(?)' if parent_storage=='blob' else '?'
                    con.execute('INSERT INTO pboards VALUES('+expr+')',(json.dumps(parent_doc),));con.commit()
                    expr='jsonb(?)' if child_storage=='blob' else '?'
                    try:
                        with con:con.execute('INSERT INTO probe VALUES('+expr+')',(json.dumps(child_doc),))
                    except sqlite3.DatabaseError:
                        assert not expected,(mode,parent_storage,child_storage,parent_doc,child_doc)
                    else:assert expected,(mode,parent_storage,child_storage,parent_doc,child_doc)
                    assert con.execute('SELECT count(*) FROM probe').fetchone()==(int(expected),)
        con.executescript('DELETE FROM pboards; DELETE FROM probe;')
        con.execute('INSERT INTO pboards VALUES(?)',(json.dumps(parent),));con.commit()
        legacy=typed(dict(_id='repair',boardId=owner,unknown=0),dict(boardId='regex',unknown='date'))
        for value in [owner,None]:
            repaired=con.execute("SELECT wl_model(?,?,?,'update')",(json.dumps(legacy),json.dumps(dict(boardId=value)),json.dumps(model))).fetchone()[0]
            document=json.loads(repaired)
            assert document['boardId']==value and document['$s']['p']['boardId']==dict(t='null' if value is None else 'string'),document
            assert document['unknown']==0 and document['$s']['p']['unknown']==dict(t='date'),document
            with con:con.execute('INSERT INTO probe VALUES(?)',(repaired,))
        con.executescript("CREATE VIEW boards AS SELECT json_extract(_ferretdb_sjson,'$._id') id FROM pboards; CREATE VIEW lists AS SELECT json_extract(_ferretdb_sjson,'$._id') id,json_extract(_ferretdb_sjson,'$.boardId') boardId FROM plists; CREATE TRIGGER list_delete INSTEAD OF DELETE ON lists BEGIN DELETE FROM plists WHERE json_extract(_ferretdb_sjson,'$._id')=OLD.id; END; CREATE TRIGGER board_delete INSTEAD OF DELETE ON boards BEGIN "+generated[1]+"DELETE FROM pboards WHERE json_extract(_ferretdb_sjson,'$._id')=OLD.id; END;")
        for storage in ['text','blob']:
            expr='jsonb(?)' if storage=='blob' else '?'
            for parent_kind in ['string','objectId']:
                con.executescript('DELETE FROM pboards; DELETE FROM plists;')
                con.execute('INSERT INTO pboards VALUES('+expr+')',(json.dumps(typed(dict(_id=owner),dict(_id=parent_kind))),))
                children=[typed(dict(_id='real',boardId=owner)),typed(dict(_id='regex',boardId=owner),dict(boardId='regex')),typed(dict(_id='oid',boardId=owner),dict(boardId='objectId'))]
                for child in children:con.execute('INSERT INTO plists VALUES('+expr+')',(json.dumps(child),))
                before=con.execute('SELECT _ferretdb_sjson FROM plists ORDER BY rowid').fetchall();con.commit()
                with con:con.execute('DELETE FROM boards WHERE id=?',(owner,))
                remaining=con.execute('SELECT _ferretdb_sjson FROM plists ORDER BY rowid').fetchall()
                assert remaining==(before[1:] if parent_kind=='string' else before),(mode,storage,parent_kind)
                assert con.execute('SELECT count(*) FROM pboards').fetchone()==(0,)
        con.close()
        print('PASS:',mode,len(cases)*4,'TEXT/JSONB reference cases, explicit repairs, typed owner cascades, unchanged lookalikes and invalid-write rollback')

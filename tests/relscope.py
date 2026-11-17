"""Embedded selection identities, duplicate shadows and descriptor/view ownership."""
from contextlib import contextmanager
import copy
import json
import os
from pathlib import Path
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
def q(value):return "'"+value.replace("'","''")+"'"
def ident(value):return '"'+value.replace('"','""')+'"'
def path(value):return '$.'+'.'.join('"'+part+'"' for part in value.split('.'))
def schema(value):
    if isinstance(value,dict):return dict(t='object',**{'$s':{'$k':list(value),'p':{key:schema(item) for key,item in value.items()}}})
    if isinstance(value,list):return dict(t='array',i=[schema(item) for item in value])
    return dict(t='null' if value is None else 'bool' if isinstance(value,bool) else 'long' if isinstance(value,int) else 'string')
def typed(value):return dict(value,**{'$s':schema(value)['$s']})
def node(document,name):
    current=document
    for part in name.split('.')[:-1]:current=current[part]
    return current,name.split('.')[-1]
def meta(document,name):
    current=document['$s']['p']
    for part in name.split('.')[:-1]:current=current[part]['$s']['p']
    return current,name.split('.')[-1]
names=['board_labels','card_members','card_assignees','card_labels','card_custom_field_values','card_dependencies','custom_field_boards','custom_field_dropdown_items']
owner="parent ' 漢";key='0123456789abcdef01234567'
with tempfile.TemporaryDirectory(prefix='wlrelscope-',dir=os.environ['TMPDIR']) as directory:
    for backend,extra in [('linked',[]),('cli',['-dWLDB_CLI'])]:
        for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
            out=Path(directory)/(backend+mode);out.mkdir();db=out/'scope.db'
            built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*extra,*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/relscope.lpr')],capture_output=True,text=True)
            assert built.returncode==0,built.stdout+built.stderr
            def run(command):
                result=subprocess.run([str(out/'relscope'),str(db)],input=json.dumps(dict(dict(table=name,owner=owner),**command))+'\n',capture_output=True,text=True)
                assert result.returncode==0,result.stderr
                answer=json.loads(result.stdout)
                if 'rows' in answer:assert answer['bindingCount']==2,answer
                return answer
            cases=0
            for name in names:
                specs=run(dict(mode='spec'));spec=specs['relation'];parent=specs['root'];fields=spec['fields'];keys=spec['keys'];pk=spec['parentKey']
                columns=[pk]+[field['name'] for field in fields]
                for storage in ['text','blob']:
                    def setup(elements,change=None):
                        db.unlink(missing_ok=True)
                        with connect(db) as con:
                            con.executescript('CREATE TABLE owned(_ferretdb_sjson ANY) STRICT; CREATE TABLE _wl_models(name TEXT,table_name TEXT,spec TEXT,version INTEGER); CREATE TABLE _ferretdb_collections(name TEXT,table_name TEXT,settings TEXT);')
                            con.execute('CREATE INDEX owned_id ON owned(json_extract(_ferretdb_sjson,\'$."_id"\'))')
                            con.execute('INSERT INTO _wl_models VALUES(?,?,?,1)',(parent['table'],'owned',json.dumps(parent)))
                            con.execute('INSERT INTO _wl_models VALUES(?,?,?,1)',(name,'owned',json.dumps(spec)))
                            con.execute('INSERT INTO _ferretdb_collections VALUES(?,?,?)',(parent['collection'],'owned','{}'))
                            con.execute('CREATE VIEW '+ident(parent['table'])+' AS SELECT json_extract(_ferretdb_sjson,\'$."_id"\') id FROM owned')
                            exprs=['json_extract(p._ferretdb_sjson,\'$."_id"\') AS '+ident(pk)]
                            for field in fields:
                                value='e.value' if spec['scalar'] else 'json_extract(e.value,'+q(path(field['path']))+')'
                                if field['default'] is not None:value='COALESCE('+value+','+(q(field['default']) if isinstance(field['default'],str) else str(field['default']))+')'
                                exprs.append(value+' AS '+ident(field['name']))
                            con.execute('CREATE VIEW '+ident(name)+' AS SELECT '+','.join(exprs)+' FROM owned p,json_each(CASE WHEN json_type(p._ferretdb_sjson,'+q(path(spec['path']))+")='array' THEN json_extract(p._ferretdb_sjson,"+q(path(spec['path']))+") ELSE '[]' END) e")
                            value=dict(_id=owner);current=value
                            parts=spec['path'].split('.')
                            for part in parts[:-1]:current[part]={};current=current[part]
                            current[parts[-1]]=elements;document=typed(value)
                            if change:change(document)
                            con.execute('INSERT INTO owned VALUES('+('jsonb(?)' if storage=='blob' else '?')+')',(json.dumps(document),))
                    def element(identity=key):
                        if spec['scalar']:return identity
                        return {field['path']:identity if field['path']==keys[0] else field['default'] for field in fields if field['path'] in keys or field['default'] is not None}
                    def kind(index,value):
                        def apply(doc):
                            props,part=meta(doc,spec['path']);item=props[part]['i'][index]
                            target=item if spec['scalar'] else item['$s']['p'][keys[0]]
                            target.clear();target.update(t=value)
                            if value=='regex':target['o']=''
                        return apply
                    setup([element()]);answer=run({});assert len(answer['rows'])==1,answer;cases+=1
                    key_column=next(field['name'] for field in fields if field['path']==keys[0])
                    assert len(run(dict(column=key_column,match=key))['rows'])==1;cases+=1
                    with connect(db) as con:
                        plan=con.execute('EXPLAIN QUERY PLAN SELECT 1 FROM '+ident(name)+' WHERE '+answer['expression']).fetchall()
                        details=' '.join(row[3] for row in plan)
                        assert 'SEARCH rs USING INDEX owned_id' in details and 'SCAN rs' not in details,details
                    cases+=1

                    setup([element()],kind(0,'regex'));assert run({})['rows']==[];cases+=1
                    setup([element()],kind(0,'objectId'));assert run({})['rows']==[];cases+=1
                    setup([element(7)]);assert run({})['rows']==[];cases+=1
                    setup([element('')]);assert run({})['rows']==[];cases+=1
                    setup([element(),element()],kind(1,'regex'));assert run({})==dict(error=True);cases+=1
                    setup([element(),element()]);assert run({})==dict(error=True);cases+=1
                    setup([element()],lambda doc:doc['$s']['p']['_id'].update(t='regex',o=''));assert run({})['rows']==[];cases+=1
                    setup([element()]);assert run(dict(after="UPDATE _wl_models SET version=2 WHERE name="+q(name)))==dict(error=True);cases+=1
                    setup([]);assert run(dict(after="UPDATE _wl_models SET version=2 WHERE name="+q(name)))==dict(error=True);cases+=1
                    setup([element()]);assert run(dict(after="UPDATE _ferretdb_collections SET settings='changed'"))==dict(error=True);cases+=1
                    setup([element()]);assert run(dict(after='DROP VIEW '+ident(name)+'; CREATE VIEW '+ident(name)+' AS SELECT '+','.join(q('x')+' AS '+ident(col) for col in columns)))==dict(error=True);cases+=1
                    setup([element()]);wrong=copy.deepcopy(spec);wrong['path']='wrong'
                    assert run(dict(before='UPDATE _wl_models SET spec='+q(json.dumps(wrong))+' WHERE name='+q(name)))==dict(error=True);cases+=1
                    setup([element()]);reordered=dict(reversed(list(spec.items())))
                    assert len(run(dict(before='UPDATE _wl_models SET spec='+q(json.dumps(reordered))+' WHERE name='+q(name)))['rows'])==1;cases+=1
                    setup([element()]);duplicate='INSERT INTO owned SELECT _ferretdb_sjson FROM owned;'
                    assert run(dict(after=duplicate))==dict(error=True);cases+=1
                    if name=='card_dependencies':
                        for value in ['missing',None,'related-to']:
                            item=element()
                            if value=='missing':item.pop('type')
                            else:item['type']=value
                            setup([item]);assert len(run({})['rows'])==1;cases+=1
                        setup([element()],lambda doc:doc['$s']['p']['cardDependencies']['i'][0]['$s']['p']['type'].update(t='regex',o=''))
                        assert run({})['rows']==[];cases+=1
                        setup([dict(cardId=key),dict(cardId=key,type=None)])
                        assert run({})==dict(error=True);cases+=1
            # Native SQL relations retain their existing TEXT contract and no private bindings.
            db.unlink()
            with connect(db) as con:
                con.execute('CREATE TABLE card_labels(cardId TEXT,labelId TEXT)');con.execute('INSERT INTO card_labels VALUES(?,?)',(owner,key))
            name='card_labels'
            result=subprocess.run([str(out/'relscope'),str(db)],input=json.dumps(dict(table=name,owner=owner))+'\n',capture_output=True,text=True)
            answer=json.loads(result.stdout);assert answer['rows']==[[owner,key]] and answer['expression']=='1' and answer['bindingCount']==0,answer
            print('PASS:',backend,mode,cases,'TEXT/JSONB embedded relation scopes, typed keys/owners, duplicate shadows, nested/default keys and pinned descriptors/views; native unchanged')

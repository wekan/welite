"""Typed managed card relations: metadata, presence, mapping and refusal."""
import copy
import json
import os
import sqlite3
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def schema(value):
    if isinstance(value,dict):return dict(t='object',**{'$s':{'$k':list(value),'p':{key:schema(item) for key,item in value.items()}}})
    if isinstance(value,list):return dict(t='array',i=[schema(item) for item in value])
    return dict(t='null' if value is None else 'bool' if isinstance(value,bool) else 'long' if isinstance(value,int) else 'double' if isinstance(value,float) else 'string')
def typed(value):return dict(value,**{'$s':schema(value)['$s']})
paths=['members','assignees','labelIds','customFields','cardDependencies']
plain=dict(_id='old',boardId='board',members=['u','U'],assignees=[],labelIds=None,customFields=[dict(_id='f',value=-7,opaque=dict(binary='AQID',timestamp=18446744073709551615)),dict(_id='missing-value'),dict(_id='null-value',value=None)],cardDependencies=[dict(cardId='old',opaque=dict(cardId='old'),type='related-to'),dict(cardId='external')])
source=typed(plain)
props=source['$s']['p']['customFields']['i'][0]['$s']['p']
props['value']=dict(t='date');props['opaque']['$s']['p'].update(binary=dict(t='binData',s=128),timestamp=dict(t='timestamp'))
target=typed(dict(_id='new',boardId='board',title='Clone',opaque='keep',members=['injected']))
maps=dict(cards={'old':'new','other':'new-other'})
def case(src=source,dst=target,mapping=maps):return dict(source=json.dumps(src),target=json.dumps(dst),maps=mapping)
cases=[case()]
for shape in ['missing',None,[],{},'legacy']:
    value=dict(_id='old',boardId='board')
    if shape!='missing':value.update({path:shape for path in paths})
    cases.append(case(typed(value)))
for mutate in [lambda s:s.update(_id='foreign'),lambda s:s.update(boardId='foreign'),lambda s:s['members'].append('u'),lambda s:s['customFields'].append(copy.deepcopy(s['customFields'][0])),lambda s:s['cardDependencies'].append(dict(cardId='old',type='related-to')),lambda s:s['customFields'][0].update(_id=7)]:
    value=copy.deepcopy(plain);mutate(value);cases.append(case(typed(value)))
wrong=copy.deepcopy(source);wrong['$s']['p']['members']['i'][0]=dict(t='regex',o='');cases.append(case(wrong))
cases.extend([case(mapping=dict(cards={'old':'other'})),case(mapping=dict(cards={'old':'new','bad':1})),case(dst=typed(dict(_id='new',boardId='foreign')))])
with tempfile.TemporaryDirectory(prefix='wlclrel-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/clrel.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        result=subprocess.run([str(out/'clrel')],input='\n'.join(json.dumps(value) for value in cases)+'\n',capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        actual=[json.loads(line) for line in result.stdout.splitlines()]
        expected=copy.deepcopy(source);expected.update(_id='new',title='Clone',opaque='keep');expected['cardDependencies'][0]['cardId']='new'
        for path in paths:
            assert actual[0][path]==expected[path],actual[0]
            assert actual[0]['$s']['p'][path]==source['$s']['p'][path],actual[0]
        assert actual[0]['title']=='Clone' and actual[0]['opaque']=='keep'
        for index,shape in enumerate(['missing',None,[],{},'legacy'],1):
            for path in paths:
                if shape=='missing':assert path not in actual[index] and path not in actual[index]['$s']['p'],actual[index]
                else:assert actual[index][path]==shape,actual[index]
        assert actual[6:]==[dict(error=True)]*(len(cases)-6),actual
        print('PASS:',mode,len(cases),'typed relation schema/presence cases, selected/external/opaque references, duplicate and foreign-binding refusal')
        ext=out/'ext';ext.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B','-Cg','-dWLSQLEXT',*flags,'-Fu'+str(root/'src'),'-FU'+str(ext),'-FE'+str(ext),'-o'+str(ext/'wlfunc.so'),str(root/'src/wlfunc.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        database=out/'copy.db'
        with sqlite3.connect(database) as con:con.execute('CREATE TABLE dst(id TEXT PRIMARY KEY,d ANY) STRICT')
        def q(text):return "'"+text.replace("'","''")+"'"
        for index,value in enumerate(cases):
            with sqlite3.connect(database) as con:
                con.execute('DELETE FROM dst')
                con.execute('INSERT INTO dst VALUES(?,?)',('text',value['target']))
                con.execute('INSERT INTO dst VALUES(?,jsonb(?))',('blob',value['target']))
                before=con.execute('SELECT * FROM dst ORDER BY id').fetchall()
            expression='wl_clone_rel(json(d),'+q(value['source'])+','+q(json.dumps(value['maps']))+')'
            sql=f"SELECT load_extension({q(str(ext/'wlfunc.so'))}); BEGIN IMMEDIATE; UPDATE dst SET d=CASE WHEN typeof(d)='blob' THEN jsonb({expression}) ELSE {expression} END; SELECT json_object('storage',typeof(d),'doc',json(d)) FROM dst ORDER BY id; COMMIT;"
            result=subprocess.run(['sqlite3','-batch','-bail',str(database)],input=sql,capture_output=True,text=True)
            if index<6:
                assert result.returncode==0,result.stderr
                rows=[json.loads(line) for line in result.stdout.splitlines() if line.strip()]
                assert [row['storage'] for row in rows]==['blob','text'],rows
                assert all(row['doc']==actual[index] for row in rows),rows
            else:
                assert result.returncode!=0,(index,result.stdout)
                with sqlite3.connect(database) as con:assert con.execute('SELECT * FROM dst ORDER BY id').fetchall()==before
        print('PASS:',mode,'actual SQL extension TEXT/JSONB preservation and invalid-copy transaction rollback')

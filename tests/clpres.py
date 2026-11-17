"""Clone projection preserves mapped BSON presence while applying intentional edits."""
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
    return dict(t='null' if value is None else 'bool' if isinstance(value,bool) else 'long' if isinstance(value,int) else 'double' if isinstance(value,float) else 'string')
def typed(value):return dict(value,**{'$s':schema(value)['$s']})
def field(name,path=None,kind='scalar',type='TEXT',required=False,default=None):return dict(name=name,path=path or name,kind=kind,type=type,required=required,default=default)
model=dict(table='cards',collection='cards',managed=['customFields'],fields=[field('id','_id',required=True),field('title',required=True,default='Untitled'),field('type',required=True,default='card'),field('userId',required=True),field('archived',kind='bool',type='INTEGER',required=True,default=0),field('endAt',kind='date'),field('createdAt',kind='date',required=True),field('cardId','meta.cardId'),field('label','meta.label',default='fallback'),field('sort',type='REAL',default=0),field('cardNumber',type='INTEGER',default=0),field('extra_json',path='',kind='extra',required=True,default='{}')])
# field() deliberately defaults paths; the remainder has an explicitly empty path.
model['fields'][-1]['path']=''
plain=dict(_id='old',title='Root',userId=None,archived=None,endAt=-9223372036854775808,createdAt=0,meta=dict(cardId='old-other',opaque='AQID'),opaque='keep',customFields=[dict(_id='f',value='managed')])
source=typed(plain);source['$s']['p']['endAt']=dict(t='date');source['$s']['p']['createdAt']=dict(t='date');source['$s']['p']['meta']['$s']['p']['opaque']=dict(t='binData',s=128)
before=dict(id='old',title='Root',type='card',userId=None,archived=0,endAt='-9223372036854775808',createdAt='1970-01-01T00:00:00.000Z',cardId='old-other',label='fallback',sort=0,cardNumber=0,extra_json='{}')
after=dict(before,id='new',title='Root Copy',createdAt='2026-11-17T00:00:00.000Z',cardId='new-other',sort=42,cardNumber=72)
def case(src=source,old=before,new=after,**extra):return dict(source=json.dumps(src),model=model,before=old,after=new,**extra)
cases=[case()]
for shape in ['missing',None,{}]:
    value=copy.deepcopy(plain);value.pop('userId');value.pop('archived')
    if shape=='missing':value.pop('meta')
    else:value['meta']=shape
    old=dict(before,cardId=None);new=dict(after,cardId=None)
    cases.append(case(typed(value),old,new))
value=copy.deepcopy(source);value['$s']['p']['meta']['$s']['p']['cardId']=dict(t='regex',o='');cases.append(case(value))
value=copy.deepcopy(source);value['title']=7;value['$s']['p']['title']=dict(t='long');cases.append(case(value,dict(before,title='7'),dict(after,title='7')))
value=copy.deepcopy(source);value['_wl_clone']=1;value['$s']['$k'].append('_wl_clone');value['$s']['p']['_wl_clone']=dict(t='long');cases.append(case(value))
ordinary=copy.deepcopy(value);ordinary['userId']='u';ordinary['$s']['p']['userId']=dict(t='string')
ordinary_patch=dict(after,userId='u');ordinary_patch.pop('extra_json')
cases.append(case(ordinary,patch=ordinary_patch,ordinary=True))
positive=len(cases)
for patch in [{},{'id':'old'},{'id':7},{'id':'new','unknown':'invalid'}]:cases.append(case(patch=patch))
value=copy.deepcopy(source);value['$s']['p']['_id']=dict(t='regex',o='');cases.append(case(value))
for envelope in [dict(_wl_clone=2,source=json.dumps(source),columns=dict(id='new')),dict(_wl_clone=1,source=json.dumps(source),columns=[],extra=True),dict(_wl_clone=1,source='{}',columns=dict(id='new'))]:cases.append(case(envelope=envelope))
with tempfile.TemporaryDirectory(prefix='wlclpres-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        def build(source_path,dest,extra=()):
            result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,*extra,'-Fu'+str(root/'src'),'-FU'+str(dest),'-FE'+str(dest),str(source_path)],capture_output=True,text=True)
            assert result.returncode==0,result.stdout+result.stderr
        build(root/'tests/clpres.lpr',out)
        result=subprocess.run([str(out/'clpres')],input='\n'.join(json.dumps(value) for value in cases)+'\n',capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        actual=[json.loads(line) for line in result.stdout.splitlines()]
        assert len(actual)==len(cases),result.stdout
        first=actual[0]['doc'];patch=actual[0]['patch']
        assert set(patch)=={'id','title','createdAt','cardId','sort','cardNumber'},patch
        assert first['_id']=='new' and first['title']=='Root Copy' and first['sort']==42 and first['cardNumber']==72,first
        assert first['userId'] is None and first['archived'] is None and 'type' not in first and 'label' not in first['meta'],first
        assert first['endAt']==plain['endAt'] and first['$s']['p']['endAt']==source['$s']['p']['endAt'],first
        assert first['meta']['cardId']=='new-other' and first['$s']['p']['meta']['$s']['p']['opaque']==dict(t='binData',s=128),first
        assert first['$s']['p']['meta']['$s']['$k']==source['$s']['p']['meta']['$s']['$k'],first
        assert 'customFields' not in first and first['opaque']=='keep' and first['$s']['p']['createdAt']==dict(t='date'),first
        for index,shape in enumerate(['missing',None,{}],1):
            doc=actual[index]['doc'];assert 'userId' not in doc and 'archived' not in doc and 'type' not in doc,doc
            if shape=='missing':assert 'meta' not in doc,doc
            else:assert doc['meta']==shape,doc
        assert 'cardId' not in actual[4]['patch'] and actual[4]['doc']['meta']['cardId']=='old-other',actual[4]
        assert actual[4]['doc']['$s']['p']['meta']['$s']['p']['cardId']==dict(t='regex',o=''),actual[4]
        assert 'title' not in actual[5]['patch'] and actual[5]['doc']['title']==7 and actual[5]['doc']['$s']['p']['title']==dict(t='long'),actual[5]
        assert actual[6]['doc']['_wl_clone']==1 and 'type' not in actual[6]['doc'],actual[6]
        assert actual[7]['doc']['_wl_clone']==1 and actual[7]['doc']['type']=='card' and actual[7]['doc']['archived'] is False,actual[7]
        assert actual[positive:]==[dict(error=True)]*(len(cases)-positive),actual
        print('PASS:',mode,len(cases),'mapped presence/type, nested parent, intended patch and invalid clone identity/envelope cases')
        ext=out/'ext';ext.mkdir();build(root/'src/wlfunc.lpr',ext,('-Cg','-dWLSQLEXT','-o'+str(ext/'wlfunc.so')))
        database=out/'copy.db'
        with sqlite3.connect(database) as con:con.execute('CREATE TABLE dst(id TEXT PRIMARY KEY,d ANY) STRICT')
        def q(text):return "'"+text.replace("'","''")+"'"
        for index,value in enumerate(cases):
            columns=actual[index].get('patch',value.get('patch',dict(id='new')))
            envelope=value.get('envelope',dict(_wl_clone=1,source=value['source'],columns=columns))
            previous=value['source'] if value.get('ordinary') else json.dumps(envelope)
            supplied=columns if value.get('ordinary') else value['after']
            expression=f"wl_model({q(previous)},{q(json.dumps(supplied))},{q(json.dumps(model))},'insert')"
            with sqlite3.connect(database) as con:con.execute('DELETE FROM dst')
            sql=f"SELECT load_extension({q(str(ext/'wlfunc.so'))}); BEGIN IMMEDIATE; INSERT INTO dst VALUES('text',{expression}),('blob',jsonb({expression})); SELECT json_object('storage',typeof(d),'doc',json(d)) FROM dst ORDER BY id; COMMIT;"
            result=subprocess.run(['sqlite3','-batch','-bail',str(database)],input=sql,capture_output=True,text=True)
            if index<positive:
                assert result.returncode==0,result.stderr
                rows=[json.loads(line) for line in result.stdout.splitlines() if line.strip()]
                assert [row['storage'] for row in rows]==['blob','text'] and all(row['doc']==actual[index]['doc'] for row in rows),rows
            else:
                assert result.returncode!=0,(index,result.stdout)
                with sqlite3.connect(database) as con:assert con.execute('SELECT count(*) FROM dst').fetchone()==(0,)
        print('PASS:',mode,'actual SQL clone envelopes, TEXT/JSONB output and invalid-insert rollback')

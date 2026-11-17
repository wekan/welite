"""Root seeds retain BSON schemas while excluding reconstructed managed relations."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def schema(value):
    if isinstance(value,dict):return dict(t='object',**{'$s':{'$k':list(value),'p':{key:schema(item) for key,item in value.items()}}})
    if isinstance(value,list):return dict(t='array',i=[schema(item) for item in value])
    return dict(t='null' if value is None else 'bool' if isinstance(value,bool) else 'long' if isinstance(value,int) else 'double' if isinstance(value,float) else 'string')
plain=dict(_id='old',title='Title',opaque=dict(date=-7,long=9007199254740993,binary='AQID',oid='0123456789abcdef01234567',timestamp=18446744073709551615,regex='漢.*',nan='NaN',zero=-0.0,nullable=None,members=['unrelated']),customFields=[dict(_id='f',value='managed')],members=['u'],labelIds=['l'])
source=dict(plain,**{'$s':schema(plain)['$s']})
props=source['$s']['p']['opaque']['$s']['p']
props.update(date=dict(t='date'),binary=dict(t='binData',s=128),oid=dict(t='objectId'),timestamp=dict(t='timestamp'),regex=dict(t='regex',o='im'),nan=dict(t='double'))
model=dict(table='cards',collection='cards',managed=['customFields','members','labelIds'],fields=[
    dict(name='id',path='_id',kind='scalar',type='TEXT',required=True,default=None),
    dict(name='title',path='title',kind='scalar',type='TEXT',required=True,default=None),
    dict(name='extra_json',path='',kind='extra',type='TEXT',required=True,default='{}')])
cases=[dict(source=json.dumps(source),model=model),dict(source=json.dumps(source),model=model,mode='project',patch=dict(id='new',title='Title Copy',extra_json=json.dumps(dict(opaque=plain['opaque']))))]
for managed in [None,'customFields',[7],[''],['.'],['opaque.date.child']]:
    bad=copy.deepcopy(model);bad['managed']=managed;cases.append(dict(source=json.dumps(source),model=bad))
bad=copy.deepcopy(source);bad['$s']['p']['opaque']['$s']['p']['date']['t']='bool';cases.append(dict(source=json.dumps(bad),model=model))
with tempfile.TemporaryDirectory(prefix='wlclseed-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/clseed.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        result=subprocess.run([str(out/'clseed')],input='\n'.join(json.dumps(case) for case in cases)+'\n',capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        actual=[json.loads(line) for line in result.stdout.splitlines()]
        for index in [0,1]:
            assert actual[index]['opaque']==plain['opaque'],actual[index]
            assert actual[index]['$s']['p']['opaque']==source['$s']['p']['opaque'],actual[index]
            assert all(key not in actual[index] and key not in actual[index]['$s']['p'] for key in model['managed']),actual[index]
        assert actual[0]['_id']=='old' and actual[1]['_id']=='new' and actual[1]['title']=='Title Copy'
        assert actual[2:]==[dict(error=True)]*(len(cases)-2),actual
        print('PASS:',mode,'typed unknown roots, nested BSON schemas, reconstructed-array exclusion, insert overlay and invalid source/path refusal')

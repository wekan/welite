"""Typed custom JSON projections and JavaScript Date serialization oracle."""
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile

root=Path(__file__).resolve().parents[1]

def typed(value, kind=None):
    if kind is not None:return dict(t=kind)
    if value is None:return dict(t='null')
    if isinstance(value, bool):return dict(t='bool')
    if isinstance(value, str):return dict(t='string')
    if isinstance(value, int):return dict(t='long')
    if isinstance(value, float):return dict(t='double')
    if isinstance(value, list):return dict(t='array',i=[typed(item) for item in value])
    return {'t':'object','$s':{'$k':list(value),'p':{key:typed(item) for key,item in value.items()}}} if value else {'t':'object','$s':{}}

def source(rows, kinds=None):
    doc=dict(_id='card',customFields=rows,unknown='private')
    schema=typed(doc)['$s']
    for index, kind in (kinds or {}).items():
        schema['p']['customFields']['i'][index]['$s']['p']['value']=typed(None,kind)
    return dict(doc,**{'$s':schema})

values=[0,-1,1,-1001,1234,2**63-1,-(2**63),8640000000000000,-8640000000000000,
        8640000000000001,-8640000000000001,-62167219200000,-62198755200000,
        253402300799999,253402300800000,-2203977600000,951782400000]
rng=random.Random(173)
values += [rng.randint(-8640000000000000,8640000000000000) for _ in range(160)]
oracle=subprocess.check_output([os.environ.get('NODE','node'),'-e',
    'let a=JSON.parse(process.argv[1]);process.stdout.write(JSON.stringify(a.map(x=>new Date(Number(x)))));',
    json.dumps([str(value) for value in values])],text=True)
dates=json.loads(oracle)
inputs=[source([dict(_id='date',value=value)],{0:'date'}) for value in values]
expected=[[dict(_id='date',value=value)] for value in dates]
rows=[dict(_id='text',value='["literal"]',unknown='do not expose'),dict(_id='bool',value=False),
      dict(_id='number',value=9007199254740993),dict(_id='array',value=['漢','\\quoted\\']),
      dict(_id='empty',value=[]),dict(_id='null',value=None),dict(_id='missing'),
      dict(_id='nan',value='NaN'),dict(_id='infinity',value='Infinity')]
inputs.append(source(rows,{7:'double',8:'double'}))
expected.append([{key:value for key,value in row.items() if key in ['_id','value']} for row in rows])
expected[-1][-2]['value']=None;expected[-1][-1]['value']=None
zero_index=len(inputs)
inputs.append(source([dict(_id='zero',value=-0.0)]))
expected.append([dict(_id='zero',value=0)])
for item in [[],{}]:
    inputs.append(source(item));expected.append([])
bad=source([dict(_id='bad',value=0)],{0:'date'});bad['customFields'][0]['value']='not integer'
inputs.append(bad);expected.append(dict(error='invalid'))
bad=source([dict(_id='bad',value=0)],{0:'date'});del bad['$s']['p']['customFields']['i'][0]['$s']['p']['value']
inputs.append(bad);expected.append(dict(error='invalid'))
inputs.append(source([dict(_id=7,value='bad')]));expected.append(dict(error='invalid'))
# Neither malformed dates nor missing metadata may leak a partially built response.
inputs.append(source([dict(_id='good',value='ok'),dict(_id='bad',value='bad')],{1:'date'}))
expected.append(dict(error='invalid'))
with tempfile.TemporaryDirectory(prefix='wlcfjson-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        dest=Path(directory)/mode;dest.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(dest),'-FE'+str(dest),str(root/'tests/cfjson.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        result=subprocess.run([str(dest/'cfjson')],input='\n'.join(json.dumps(item,ensure_ascii=False) for item in inputs)+'\n',capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        lines=result.stdout.splitlines()
        assert '-0' not in lines[zero_index], lines[zero_index]
        actual=[json.loads(line) for line in lines]
        assert len(actual)==len(expected),(len(actual),len(expected))
        for i,(got,want) in enumerate(zip(actual,expected)):
            assert got==want,(mode,i,inputs[i],got,want)
        print('PASS:',mode,len(values),'Node Date oracle vectors, typed values, private metadata omission and invalid-source refusal')

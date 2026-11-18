"""Initialize only absent managed arrays while preserving typed source siblings."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
def typed(value):
    def schema(item):
        if isinstance(item,dict):return dict(t='object',**{'$s':dict(p={k:schema(v) for k,v in item.items()},**{'$k':list(item)})})
        if isinstance(item,list):return dict(t='array',i=[schema(v) for v in item])
        return dict(t='null' if item is None else 'string' if isinstance(item,str) else 'long')
    return dict(value,**{'$s':schema(value)['$s']})
model=dict(table='custom_field_dropdown_items',path='settings.dropdownItems',scalar=False,fields=[dict(name='id',path='_id',kind='scalar',required=True,default=None),dict(name='name',path='name',kind='scalar',required=True,default=None),dict(name='sort',path='sort',kind='scalar',required=False,default=None)],keys=['_id'])
with tempfile.TemporaryDirectory(prefix='wlrelin-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        build=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/relinit.lpr')],capture_output=True,text=True)
        assert build.returncode==0,build.stdout+build.stderr
        cases=[];sources=[]
        for settings in [None,{},dict(currencyCode='EUR',future=9007199254740993)]:
            source=typed(dict(_id='field',unknown=9007199254740993,**({} if settings is None else dict(settings=settings))))
            sources.append(source);cases.append(dict(source=json.dumps(source),command=json.dumps(dict(op='init',old={},values={})),model=json.dumps(model)))
        for value in [None,[],[dict(_id='one',name='One')],'bad',{}]:
            cases.append(dict(source=json.dumps(typed(dict(_id='field',settings=dict(dropdownItems=value)))),command=json.dumps(dict(op='init',old={},values={})),model=json.dumps(model)))
        for value in [None,'bad',[],42]:
            cases.append(dict(source=json.dumps(typed(dict(_id='field',settings=value))),command=json.dumps(dict(op='init',old={},values={})),model=json.dumps(model)))
        for command in [dict(op='init',old=dict(_id='one'),values={}),dict(op='init',old={},values=dict(name='bad')),dict(op='init',old={},values={},extra=True)]:
            cases.append(dict(source=json.dumps(sources[1]),command=json.dumps(command),model=json.dumps(model)))
        appended=typed(dict(_id='field',unknown=9007199254740993,settings=dict(dropdownItems=[])))
        cases.append(dict(source=json.dumps(appended),command=json.dumps(dict(op='append',old={},values=dict(id='one',name='One'))),model=json.dumps(model)))
        legacy=typed(dict(_id='field',settings=dict(dropdownItems=[dict(_id='one',name='Legacy',extra=9007199254740993)])))
        legacy['$s']['p']['settings']['$s']['p']['dropdownItems']['i'][0]['$s']['p']['name']=dict(t='regex',o='i')
        cases.append(dict(source=json.dumps(legacy),command=json.dumps(dict(op='update',old=dict(_id='one'),values=dict(name='Legacy'))),model=json.dumps(model)))
        result=subprocess.run([str(out/'relinit')],input=''.join(json.dumps(case)+'\n' for case in cases),capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        rows=[json.loads(line) for line in result.stdout.splitlines()];assert len(rows)==len(cases)
        for source,row in zip(sources,rows):
            assert row['settings']['dropdownItems']==[] and row['unknown']==source['unknown']
            assert row['$s']['p']['unknown']==source['$s']['p']['unknown']
            assert row['$s']['p']['settings']['$s']['p']['dropdownItems']==dict(t='array',i=[])
            for key,value in source.get('settings',{}).items():assert row['settings'][key]==value
        assert all(row==dict(error='invalid') for row in rows[3:-2]),rows
        assert rows[-2]['settings']['dropdownItems']==[dict(_id='one',name='One')],rows[-2]
        assert rows[-2]['$s']['p']['unknown']==appended['$s']['p']['unknown']
        props=rows[-1]['$s']['p']['settings']['$s']['p']['dropdownItems']['i'][0]['$s']['p']
        assert props['name']==dict(t='string') and props['extra']==dict(t='long'),rows[-1]
        print('PASS:',mode,'missing-only managed array initialization, typed sibling retention and existing/null/invalid-command refusal')

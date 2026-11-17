"""Checked settings parsing plus metadata-free typed definition serialization."""
import json
import os
from pathlib import Path
import subprocess
import sqlite3
import tempfile
root=Path(__file__).resolve().parents[1]
valid=[{},dict(currencyCode='EUR'),dict(stringtemplateFormat='__card__ 漢',stringtemplateSeparator=''),
       dict(jiraTimeField='original',jiraEstimateFieldId='customfield_'+'1'*20,jiraEstimateUnit='x'*78+'😀'),
       dict(future=dict(flag=True,values=[None,'漢',3.5]))]
invalid=[None,[],False,'bad',dict(currencyCode=7),dict(currencyCode='\0'),dict(stringtemplateSeparator=None),
         dict(jiraTimeField='bad'),dict(jiraEstimateFieldId='customfield_'),dict(jiraEstimateFieldId='customfield_'+'1'*21),
         dict(jiraEstimateUnit='x'*79+'😀'),dict(dropdownItems=[])]
cases=[({},dict(ok=True,settings={}))]
cases += [(dict(settings=value),dict(ok=True,settings=value)) for value in valid]
cases += [(dict(settings=value),dict(ok=False)) for value in invalid]
cases.append((dict(settings=json.dumps(valid[-1])),dict(ok=True,settings=valid[-1])))
source={'_id':'field','settings':{'currencyCode':'EUR'},'modifiedAt':-1,
        '$s':{'$k':['_id','settings','modifiedAt'],'p':{'_id':{'t':'string'},'settings':{'t':'object','$s':{'$k':['currencyCode'],'p':{'currencyCode':{'t':'string'}}}},'modifiedAt':{'t':'date'}}}}
cases.append((dict(mode='document',document=json.dumps(source)),dict(_id='field',settings=dict(currencyCode='EUR'),modifiedAt='1969-12-31T23:59:59.999Z')))
with tempfile.TemporaryDirectory(prefix='wlcfspec-',dir=os.environ['TMPDIR']) as directory:
    native=Path(directory)/'native.db'
    with sqlite3.connect(native) as con:
        con.executescript((root/'src/schema.sql').read_text())
        con.execute("INSERT INTO custom_fields(id,name,type,currencyCode,stringtemplateFormat,stringtemplateSeparator,settings_json,createdAt,modifiedAt) VALUES('read','Legacy','dropdown','EUR','__card__','',?, '1970-01-01T00:00:00.000Z','1970-01-01T00:00:00.001Z')",(json.dumps(dict(jiraTimeField='remaining')),))
        con.executemany("INSERT INTO custom_field_boards VALUES('read',?)",[('b',),('a',)])
        con.executemany("INSERT INTO custom_field_dropdown_items(customFieldId,id,name,sort) VALUES('read',?,?,?)",[('one','漢',1),('two','Two',0)])
    native_expected=dict(_id='read',name='Legacy',type='dropdown',showOnCard=False,automaticallyOnCard=False,alwaysOnCard=False,showLabelOnMiniCard=False,showSumAtTopOfList=False,createdAt='1970-01-01T00:00:00.000Z',modifiedAt='1970-01-01T00:00:00.001Z',boardIds=['a','b'],settings=dict(jiraTimeField='remaining',currencyCode='EUR',stringtemplateFormat='__card__',stringtemplateSeparator='',dropdownItems=[dict(_id='two',name='Two'),dict(_id='one',name='漢')]))
    cases.append((dict(mode='read',path=str(native),id='read'),native_expected))
    cases.append((dict(mode='read',path=str(native),id='missing'),None))
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        built=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/cfspec.lpr')],capture_output=True,text=True)
        assert built.returncode==0,built.stdout+built.stderr
        result=subprocess.run([str(out/'cfspec')],input='\n'.join(json.dumps(case) for case,_ in cases)+'\n',capture_output=True,text=True)
        assert result.returncode==0,result.stderr
        actual=[json.loads(line) for line in result.stdout.splitlines()]
        assert actual==[expected for _,expected in cases],(mode,actual,cases)
        print('PASS:',mode,'settings object/scalars/remainder, schema regex/UTF-16 limits, unsupported-array refusal and typed full-document JSON')

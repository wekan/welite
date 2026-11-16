"""Shared lifetime kernel against JavaScript Number/Date arithmetic."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
node=os.environ.get('NODE','node')
cases=[(stamp,days) for stamp in [0,-1,1,-1001,1794832496789,8640000000000000,-8640000000000000]
       for days in ['', '0', '-0', '90', '36500', '0.5', '.00000001', '1e-8',
                    '1.23456789012345', '0.000000011574074074074073', '1e-300']]
cases += [(0,value) for value in ['-1','36500.1','NaN','Infinity','1,5','0x10','1e309','1e','--1','.','1 2','']]
# The decimal syntax/resource policy is explicit; Number accepts a few syntaxes
# deliberately outside it. Within the policy, execute the real JS operations.
script='''const cases=JSON.parse(process.argv[1]);
console.log(JSON.stringify(cases.map(([stamp,text])=>{
 if(text.trim() && (!/^[+\\-\\d.eE]+$/.test(text.trim()) || !/\\d/.test(text)))return 'error';
 let days=Number(text);if(!Number.isFinite(days))return 'error';days=days||90;
 if(days<0||days>36500)return 'error';
 const expires=new Date(new Date(stamp).getTime()+days*86400000).getTime();
 return Number.isFinite(expires)?String(expires):'error';})));'''
expected=json.loads(subprocess.check_output([node,'-e',script,json.dumps(cases)],text=True))
with tempfile.TemporaryDirectory(prefix='wllife-',dir=os.environ['TMPDIR']) as directory:
    temp=Path(directory)
    for name,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=temp/name;out.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/lifetime.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        for (stamp,days),want in zip(cases,expected):
            got=subprocess.check_output([str(out/'lifetime'),str(stamp),days],text=True).strip()
            assert got==want,(name,stamp,days,got,want)
        print('PASS:',name,len(cases),'JavaScript fractional lifetime/default/date-boundary vectors')

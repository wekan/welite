"""Strict one-pass API path decoding, plus preservation and atomic normalization."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
keys=set(re.findall(r"RouteParams\['([^']+)'\]",(root/'src/wlapi.pas').read_text()))
known=set(re.findall(r"'([^']+)'",(root/'src/wlpath.pas').read_text().split('function DecodePathId')[0]))
assert keys<=known,(keys-known)
cases=[]
for encoded,decoded in [('', ''),('plain','plain'),('漢字','漢字'),('%E6%BC%A2%E5%AD%97','漢字'),
                        ('a+b','a+b'),('a%2Bb','a+b'),('%20',' '),('%2f','/'),('%5C','\\'),
                        ('%252F','%2F'),('%252B','%2B'),('%25','%'),('%2E%2E','..'),('%22%27','"\'')]:
    cases.append((dict(value=encoded),[True,decoded]))
for encoded in ['%','%0','%xz','%0G','%00','%01','%0A','%0d','%7F','%80','%C0%AF',
                '%ED%A0%80','%F4%90%80%80','%F0%80%80%80','%E6%BC','x%FF','\n']:
    cases.append((dict(value=encoded),[False,'']))
cases.append((dict(mode='all',value='%E6%BC%A2%252F+'),[True,True]+['漢%2F+']*len(keys)))
cases += [(dict(mode='request',board='b%20one',card='%252F'),[True,True,'b one','%2F']),
          (dict(mode='request',board='b%20one',card='%GG'),[False,False,'b%20one','%GG'])]
with tempfile.TemporaryDirectory(prefix='wlpath-',dir=os.environ['TMPDIR']) as directory:
    for mode,flags in [('normal',[]),('checked',['-Cr','-Co','-Ci','-Sa'])]:
        out=Path(directory)/mode;out.mkdir()
        result=subprocess.run([os.environ.get('FPC','fpc'),'-B',*flags,'-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/pathid.lpr')],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        run=subprocess.run([str(out/'pathid')],input='\n'.join(json.dumps(case) for case,_ in cases)+'\n',text=True,capture_output=True)
        assert run.returncode==0,run.stderr
        actual=[json.loads(line) for line in run.stdout.splitlines()]
        assert actual==[expected for _,expected in cases],(mode,actual,cases)
        print('PASS:',mode,'strict UTF-8/percent path IDs, literal plus, single-pass decoding, query isolation, atomic failure and API key coverage')

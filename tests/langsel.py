"""Server locale selection, weighted negotiation and disk/embedded catalog safety."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wllocale-',dir=os.environ['TMPDIR']) as directory:
    out=Path(directory)
    built=subprocess.run([os.environ.get('FPC','fpc'),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/langsel.lpr')],capture_output=True,text=True)
    assert built.returncode==0,built.stdout+built.stderr
    catalog=json.loads((root/'i18n/locales.jsn').read_text())
    def run(query='',profile='',header='',path=root/'i18n',embedded=False):
        args=['embedded',str(path/'locales.jsn')] if embedded else [str(path)]
        return subprocess.check_output([str(out/'langsel'),*args,query,profile,header],text=True).splitlines()
    def check(tag,rtl=False,**kwargs):
        lines=run(**kwargs)
        assert lines[:4]==['loaded',str(len(catalog)),tag,'rtl' if rtl else 'ltr'],(kwargs,lines)
    check('fi',query='FI',profile='ar',header='de',rtl=False)
    check('ar',query='../en',profile='ar',header='de',rtl=True)
    check('de',header='ar;q=0.2,de;q=0.8',rtl=False)
    check('ar',header='de;q=0,ar;q=0.8',rtl=True)
    check('en',header='ar;q=NaN,de;q=2,fi;q=-1,he;q=0.1234')
    check('de',header='de;q=0.5,fi;q=0.500')
    check('en',header='ar;q=0,*;q=0.5')
    check('ar',query='ar-SA',rtl=True)
    check('he-IL',query='iw-IL',rtl=True)
    check('ar',header='ar;Q=1',rtl=True)
    check('en',query='arbitrary',header='en')
    check('en',header='ar,'+'x'*8192)
    check('fi',query='fi',embedded=True)
    for row in catalog:
        check(row['tag'],query=row['key'],rtl=row['rtl'])
    case=out/'bad';case.mkdir()
    for broken in [[],{},catalog[:-1]+[catalog[0]], [dict(row,rtl='true') if row['tag']=='en' else row for row in catalog], [dict(row,file='../en.jsn') if row['tag']=='en' else row for row in catalog], [row for row in catalog if row['tag']!='en']]:
        (case/'locales.jsn').write_text(json.dumps(broken))
        assert run(query='ar',path=case)[:4]==['fallback','1','en','ltr']
    (case/'locales.jsn').write_bytes(b' '* (16*1024*1024+1))
    assert run(query='ar',path=case)[:4]==['fallback','1','en','ltr']
    assert run(query='ar',path=case,embedded=True)[:4]==['fallback','1','en','ltr']
    (case/'locales.jsn').write_text('{malformed')
    assert run(query='ar',path=case)[:4]==['fallback','1','en','ltr']
print('PASS: all catalog identities/directions, explicit/profile/header precedence, weighted/invalid/excluded ranges, aliases/parents, disk/embedded, malformed catalog fallback and traversal refusal')

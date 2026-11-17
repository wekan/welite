"""Per-page flat translation lookup with English/explicit fallback and literal tokens."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wlxlate-',dir=os.environ['TMPDIR']) as directory:
    out=Path(directory)
    result=subprocess.run([os.environ.get('FPC','fpc'),'-B','-Fu'+str(root/'src'),'-FU'+str(out),'-FE'+str(out),str(root/'tests/xlate.lpr')],capture_output=True,text=True)
    assert result.returncode==0,result.stdout+result.stderr
    def text(language,key,fallback='explicit fallback',path=root/'i18n'):
        return subprocess.check_output([str(out/'xlate'),str(path),language,key,fallback],text=True)
    english=json.loads((root/'i18n/data/en.jsn').read_text())
    for row in json.loads((root/'i18n/locales.jsn').read_text()):
        local=json.loads((root/'i18n/data'/row['file']).read_text())
        assert text(row['tag'],'username')==(local.get('username') or english['username']),row['tag']
    fixture=out/'fixture';(fixture/'data').mkdir(parents=True)
    records=[dict(key=tag,code=tag,tag=tag,name=tag,rtl=False,file=tag+'.jsn') for tag in ['en','fi']]
    (fixture/'locales.jsn').write_text(json.dumps(records))
    (fixture/'data/en.jsn').write_text(json.dumps(dict(key='English',empty='English empty',typed='English type',token='__card__ %1$s %d',fallback='English only')))
    (fixture/'data/fi.jsn').write_text(json.dumps(dict(key='<b>Suomi & "teksti"</b>',empty='',typed=False,token='__card__ %1$s %d')))
    assert text('fi','key',path=fixture)=='<b>Suomi & "teksti"</b>'
    for key,expected in [('empty','English empty'),('typed','English type'),('token','__card__ %1$s %d'),('fallback','English only'),('unknown','explicit fallback')]:assert text('fi',key,path=fixture)==expected
    for bad in ['{invalid','[]','null']:
        (fixture/'data/fi.jsn').write_text(bad)
        assert text('fi','key',path=fixture)=='English'
    (fixture/'data/en.jsn').unlink()
    assert text('fi','key',path=fixture)=='explicit fallback'
print('PASS: every installed language username, UTF-8/literal markup/tokens, missing/empty/wrong-type keys, malformed files and English/explicit fallbacks')

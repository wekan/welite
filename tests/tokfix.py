"""Unambiguous placeholder repair preserves prose, URL bytes and untouched translations."""
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('welite_tokfix',root/'releases/tokfix.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
cases=[
 ('Hello __user__','مرحبا __اسم__','مرحبا __user__'),
 ('__board__ __card__','X __Board__ Y __Card__','X __board__ Y __card__'),
 ('on __siteName__','osoitteessa __url__','osoitteessa __siteName__'),
 ('%1$s done','%s terminé','%1$s terminé'),
 ('%02d done','%02x fini','%02d fini'),
 ('%{count} items','%{nombre} éléments','%{count} éléments'),
 ('__user__ URL','__name__ https://x/%D8%B9?q=%20','__user__ https://x/%D8%B9?q=%20'),
 ('__user__ %D','__name__ https://x/%D8%B9 %D','__user__ https://x/%D8%B9 %D'),
]
for source,before,expected in cases:
    changed=module.repair(source,before)
    assert changed==expected,(source,before,changed)
    assert module.tokens(changed)==module.tokens(source)
    assert module.prose(changed)==module.prose(before)
for source,before in [('__user__ __card__','__nom__ __carte__'),('__user__ __card__','__user__ __user__'),('%s %s','ajouté'),('%s','%s'),('__user__','__nom__ + __broken'),('__user__','___nom___'),('__user__','__nom__ + __名前 空白__')]:assert module.repair(source,before) is None
assert module.tokens('https://x/%D8%B9/%20')==Counter()
assert module.tokens('https://x/%s/%1$s/__name__')==Counter({'%s':1,'%1$s':1,'__name__':1})
assert module.tokens('https://x/%%20f')==Counter()
assert module.tokens('https://x/__foo%20bar__/%{foo%20bar}')==Counter({'__foo%20bar__':1,'%{foo%20bar}':1})
assert module.tokens('100% of text')==Counter()
with tempfile.TemporaryDirectory(prefix='wltok-',dir=os.environ['TMPDIR']) as directory:
    out=Path(directory);data=out/'data';data.mkdir()
    source=dict(rename='Hello __user__',missing='%s %s',human='Keep')
    local=dict(rename='مرحبا __اسم__',missing='ajouté',human='Garder')
    (data/'en.jsn').write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n')
    file=data/'xx.jsn';file.write_text(json.dumps(local,ensure_ascii=False,indent=2)+'\n');original=file.read_bytes()
    args=['python3',str(root/'releases/tokfix.py'),'--data',str(data)]
    subprocess.run(args,check=True,capture_output=True);assert file.read_bytes()==original
    assert subprocess.run(args+['--apply','--record',str(file)],capture_output=True).returncode!=0
    assert file.read_bytes()==original
    record=out/'done.jsn'
    record.write_text(json.dumps(dict(version=1,keys={'xx.jsn':'invalid'})))
    assert subprocess.run(args+['--apply','--record',str(record)],capture_output=True).returncode!=0
    assert file.read_bytes()==original
    record.unlink()
    invalid=data/'zz.jsn';invalid.write_text('{"bad":"\\ud800"}')
    assert subprocess.run(args+['--apply'],capture_output=True).returncode!=0
    assert file.read_bytes()==original
    invalid.unlink()
    elsewhere=out/'elsewhere.jsn';elsewhere.write_bytes(original)
    (data/'alias.jsn').symlink_to(elsewhere)
    subprocess.run(args+['--apply','--record',str(record)],check=True,capture_output=True)
    assert elsewhere.read_bytes()==original

    after=json.loads(file.read_text());assert after==dict(local,rename='مرحبا __user__')
    assert list(after)==list(local) and after['human']==local['human'] and after['missing']==local['missing']
    assert json.loads(record.read_text())['keys']=={'xx.jsn':['rename']}
    before=file.read_bytes();subprocess.run(args+['--apply'],check=True,capture_output=True);assert file.read_bytes()==before
    # All recorded production repairs must keep the English argument inventory.
    manifest=root/'tests/tokdone.jsn'
    if manifest.exists():
        english=module.load(root/'i18n/data/en.jsn')
        for filename,keys in json.loads(manifest.read_text())['keys'].items():
            values=module.load(root/'i18n/data'/filename)
            for key in keys:assert module.tokens(values[key])==module.tokens(english[key]),(filename,key)
print('PASS: Unicode/case/printf/named tokens, prose preservation, URL octets, ambiguous/repeated refusal, dry run, human text/key order, idempotence and recorded inventories')

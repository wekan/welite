"""Language metadata conversion and no-dangling installed catalogs."""
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('convlang',root/'releases/convlang.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
fixture='''const languageMetadata = [
 ["en", "en", "en", "English", false],
 ["xx", "xx", "xx", "A comma, ] and \\"quote\\"", true],
];
const languageLoaders = {
 "en": () => import("./data/en.i18n.json"),
 "xx": () => import("./data/xx.i18n.json"),
};
export default languages;
'''
rows=module.parse(fixture)
assert rows[1]['name']=='A comma, ] and "quote"' and rows[1]['rtl'] is True
assert module.parse(module.render(rows))==rows
for bad in [fixture.replace('./data/xx.i18n.json','./data/../xx.i18n.json'),fixture.replace('["xx", "xx",','["en", "xx",'),fixture.replace('"xx", "A comma','"../xx", "A comma'),fixture.replace('false],','"false"],')]:
    try:module.parse(bad)
    except (ValueError,TypeError):pass
    else:raise AssertionError('Invalid metadata accepted')
with tempfile.TemporaryDirectory(prefix='wlcat-',dir=os.environ['TMPDIR']) as directory:
    out=Path(directory);(out/'data').mkdir();(out/'data/en.jsn').write_text('{}')
    source=out/'input.js';source.write_text(fixture)
    args=['python3',str(root/'releases/convlang.py'),str(source),str(out/'langs.jsn')]
    subprocess.run(args,check=True,capture_output=True)
    assert json.loads((out/'locales.jsn').read_text())==rows[:1]
    before=(out/'langs.jsn').read_bytes(),(out/'locales.jsn').read_bytes()
    source.write_text('export default not_supported;')
    assert subprocess.run(args,capture_output=True).returncode!=0
    assert before==((out/'langs.jsn').read_bytes(),(out/'locales.jsn').read_bytes())
    assert (out/'data/en.jsn').read_text()=='{}'
    installed=json.loads((root/'i18n/locales.jsn').read_text())
    assert module.parse((root/'i18n/langs.jsn').read_text())==installed
    assert all((root/'i18n/data'/row['file']).is_file() for row in installed)
    assert any(row['tag']=='en' for row in installed)
    assert any(row['tag']=='fi' and row['name']=='Suomi' for row in installed)
    assert any(row['tag']=='he' and row['rtl'] for row in installed)
    assert all(re.fullmatch(r'[A-Za-z0-9_-]{1,8}\.jsn',row['file']) for row in installed)
    assert len({row['file'].casefold() for row in installed})==len({row['file'] for row in installed})
    for tag in ('ckb','ks','ps','sd','ur'):
        assert any(row['tag']==tag and row['rtl'] for row in installed)
    for tag,file in [('km_KH','km_KH.jsn'),('ru_RU','ru_RU.jsn'),('pt-PT','pt_PT.jsn'),('pt_PT','pt_PT.jsn')]:
        assert next(row for row in installed if row['tag']==tag)['file']==file
        assert len(Path(file).stem)<=8
print('PASS: compact/literal metadata, Unicode/escaping, unsafe/duplicate refusal, installed files, no translation writes, matching data/browser catalogs')


arabic=json.loads((root/'i18n/data/ar.jsn').read_text())
english=json.loads((root/'i18n/data/en.jsn').read_text())
placeholder=re.compile(r'__[A-Za-z0-9_]+?__|%(?:\d+\$)?[A-Za-z%]')
for key in ('act-restoredCard','activity-checklist-completed','loading','archived','no-cards-found'):
    assert re.search(r'[؀-ۿ]',arabic[key]) and not re.search('[پچژگ]',arabic[key])
    assert sorted(placeholder.findall(arabic[key]))==sorted(placeholder.findall(english[key]))
print('PASS: corrected Arabic phrases retain English placeholder tokens')


persian=json.loads((root/'i18n/data/fa.jsn').read_text())
for key in ('act-moveCardToOtherBoard','email-enrollAccount-subject','email-invite-text','activity-delete-attach'):
    assert arabic[key]!=persian[key]
    assert sorted(placeholder.findall(arabic[key]))==sorted(placeholder.findall(english[key]))
print('PASS: Arabic activity and invitation phrases differ from the Persian catalog and preserve tokens')

# Arabic regional catalogs previously defaulted to English or French for these
# shared labels. Keep both the declared script and the positional arguments.
for tag in ('ar','ar-DZ','ar-EG','ary'):
    words=json.loads((root/'i18n'/'data'/f'{tag}.jsn').read_text())
    for key in ('activity-changedTitle','act-deleteCard','act-removeBoard','act-removeList','act-removeSwimlane'):
        assert re.search(r'[ء-ي]',words[key]),(tag,key)
        assert sorted(placeholder.findall(words[key]))==sorted(placeholder.findall(english[key])),(tag,key)
print('PASS: Arabic regional activity captions use Arabic and retain WeLite placeholders')

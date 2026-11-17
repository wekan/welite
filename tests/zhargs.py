"""Traditional Chinese attachment activity has native prose and exact arguments."""
import importlib.util
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
tokens=importlib.util.module_from_spec(spec);spec.loader.exec_module(tokens)
en=json.loads((root/'i18n/data/en.jsn').read_text());key='act-deleteAttachment'
for tag in ['zh-HK','zh-Hant','zh-TW']:
    data=json.loads((root/'i18n/data'/(tag+'.jsn')).read_text())
    assert list(data)==list(en)
    assert tokens.tokens(data[key])==tokens.tokens(en[key]),tag
    prose=tokens.prose(data[key])
    assert 'at swimlane' not in prose and 'swimlane' not in prose,tag
    assert data['swimlane'] in prose and '刪除' in prose,tag
print('PASS: Traditional Chinese attachment activity, native swimlane/deletion prose, rejected English fragment and exact argument inventories/key order')

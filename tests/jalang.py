"""Japanese Japan physical asset, native script and exact arguments."""
import importlib.util
import json
import re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
tokens=importlib.util.module_from_spec(spec);spec.loader.exec_module(tokens)
p=root/'i18n/data/ja-JP.jsn';assert p.is_file() and not p.is_symlink()
data=json.loads(p.read_text());en=json.loads((p.parent/'en.jsn').read_text())
assert list(data)==list(en)
for key,value in data.items():assert tokens.tokens(value)==tokens.tokens(en[key]),key
for key,word in [('username','ユーザー'),('list','リスト'),('card','カード'),('board-members-same-org-team-only','組織'),('click-to-change-zoom','変更')]:assert word in data[key],key
for key in ['board-members-same-org-team-only','click-to-change-zoom','grey-icons',
            'disable-self-registration','disable-forgot-password','hide-card-counter-list',
            'hide-board-member-list','hide-activities-of-all-boards','can-invite-if-same-mailDomainName']:
    assert data[key]!=en[key] and re.search('[ぁ-ゟァ-ヿ一-鿿]',data[key]),key
catalog=json.loads((root/'i18n/locales.jsn').read_text())
assert next(row for row in catalog if row['tag']=='ja-JP')['file']==p.name
print('PASS: physical Japanese Japan, native vocabulary/script and legacy prose, catalog identity, English key order and every token inventory')

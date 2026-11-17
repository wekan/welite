"""Colombian Spanish asset, legacy prose and exact source arguments."""
import importlib.util
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
tokens=importlib.util.module_from_spec(spec);spec.loader.exec_module(tokens)
p=root/'i18n/data/es-CO.jsn'
assert p.is_file() and not p.is_symlink()
data=json.loads(p.read_text());en=json.loads((p.parent/'en.jsn').read_text())
assert list(data)==list(en)
for key,value in data.items():assert tokens.tokens(value)==tokens.tokens(en[key]),key
for key,word in [('username','usuario'),('list','lista'),('card','tarjeta'),('grey-icons','grises'),('disable-forgot-password','contraseñas'),('can-invite-if-same-mailDomainName','correo')]:
    assert word in data[key].lower(),key
for key in ['board-members-same-org-team-only','click-to-change-zoom','grey-icons',
            'disable-self-registration','disable-forgot-password','hide-card-counter-list',
            'hide-board-member-list','hide-activities-of-all-boards','can-invite-if-same-mailDomainName']:
    assert data[key] and data[key]!=en[key],key
catalog=json.loads((root/'i18n/locales.jsn').read_text())
assert next(row for row in catalog if row['tag']=='es-CO')['file']=='es-CO.jsn'
print('PASS: physical Colombian Spanish, vocabulary/legacy prose, catalog identity, English key order and every token inventory')

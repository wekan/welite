"""French regional assets: physical files, declared language and source arguments."""
import importlib.util
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
tokens=importlib.util.module_from_spec(spec);spec.loader.exec_module(tokens)
en=json.loads((root/'i18n/data/en.jsn').read_text())
legacy=['board-members-same-org-team-only','click-to-change-zoom','grey-icons',
        'disable-self-registration','disable-forgot-password','hide-card-counter-list',
        'hide-board-member-list','hide-activities-of-all-boards','can-invite-if-same-mailDomainName']
catalog=json.loads((root/'i18n/locales.jsn').read_text())
for tag in ['fr-BE','fr-CA']:
    path=root/'i18n/data'/(tag+'.jsn')
    assert path.is_file() and not path.is_symlink()
    data=json.loads(path.read_text())
    assert list(data)==list(en)
    assert next(row for row in catalog if row['tag']==tag)['file']==path.name
    for key,value in data.items():assert tokens.tokens(value)==tokens.tokens(en[key]),(tag,key)
    assert "utilisateur" in data['username'].lower()
    assert 'liste' in data['list'].lower() and 'carte' in data['card'].lower()
    for key in legacy:assert data[key].strip() and data[key]!=en[key],(tag,key)
    assert 'organisation' in data['board-members-same-org-team-only'].lower()

# The base French locale also has complete argument inventories after contextual
# fence/search-example repairs; do not freeze human phrasing around those spans.
base=json.loads((root/'i18n/data/fr.jsn').read_text())
assert list(base)==list(en)
for key,value in base.items():assert tokens.tokens(value)==tokens.tokens(en[key]),key

print('PASS: French baseline/regional argument inventories, physical regional assets, vocabulary, legacy prose, catalog identities and English key order')

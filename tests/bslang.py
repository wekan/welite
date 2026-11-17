"""Bosnian asset, native terminology, compatibility prose and source arguments."""
import importlib.util
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
tokens=importlib.util.module_from_spec(spec);spec.loader.exec_module(tokens)
p=root/'i18n/data/bs.jsn';assert p.is_file() and not p.is_symlink()
data=json.loads(p.read_text());en=json.loads((p.parent/'en.jsn').read_text())
assert list(data)==list(en)
for key,value in data.items():assert tokens.tokens(value)==tokens.tokens(en[key]),key
for key,word in [('username','korisničko'),('board','tabla'),('card','kartica'),('list','lista'),('swimlane','traka'),('click-to-change-zoom','promjenu'),('click-to-change-zoom','uvećanja'),('disable-forgot-password','lozinke'),('can-invite-if-same-mailDomainName','e-pošte'),('attachment-limit-unit-bytes','bajtovi')]:assert word in data[key].lower(),key
for key in ['board-members-same-org-team-only','click-to-change-zoom','grey-icons',
            'disable-self-registration','disable-forgot-password','hide-card-counter-list',
            'hide-board-member-list','hide-activities-of-all-boards','can-invite-if-same-mailDomainName']:
    assert data[key] and data[key]!=en[key],key
catalog=json.loads((root/'i18n/locales.jsn').read_text())
row=next(row for row in catalog if row['tag']=='bs')
assert row['file']==p.name and row['name']=='Bosanski' and row['rtl'] is False
print('PASS: Bosnian asset/native terminology and legacy prose, native catalog identity, English key order and every token inventory')

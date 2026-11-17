"""Acehnese must not regress to the former Malay/Indonesian seed."""
import importlib.util
import json
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tokens',root/'releases/tokfix.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
english=json.loads((root/'i18n/data/en.jsn').read_text())
ace=json.loads((root/'i18n/data/ace.jsn').read_text())
assert list(ace)==list(english)
for key,value in ace.items():assert module.tokens(value)==module.tokens(english[key]),key
assert 'Nan' in ace['username'] and 'Ureueng' in ace['username']
assert 'Dapeuta' in ace['list']
activity=ace['act-addAttachment']
assert 'geutamah' in activity and ' bak ' in activity and 'dapeuta' in activity
assert 'menambahkan' not in activity and 'pada daftar' not in activity
assert ace['username']!='Nama Pengguna' and ace['list']!='Senarai'
assert ace['hide-card-counter-list'].startswith('Peusom')
assert 'keulabee' in ace['grey-icons']
assert 'keudroe' in ace['disable-self-registration']
assert 'nyang saban' in ace['board-members-same-org-team-only']
# Same-script checks use language-specific vocabulary, not just Latin characters.
markers=sum(bool(re.search(r'\b(?:geu[a-zôéèëö]+|ureueng|dapeuta|droeneueh|peusom|keudroe|nyang)\b',value,re.I)) for value in ace.values())
assert markers>100,markers
print('PASS: Acehnese vocabulary/core/activity/legacy labels, rejected seed anchors, English key order and every underscore/percent token inventory')

#!/usr/bin/env python3
"""Bring WeLite's catalogs (i18n/data/*.jsn) up to WeKan's own
(imports/i18n/data/*.i18n.json), the source of every WeKan prototype's
translations: each key a WeLite catalog has takes WeKan's text for it, in
the same language, so a correction made in WeKan reaches WeLite. A key
WeKan does not have stays as it is; the keys' order and the files' 2-space
form are kept.

    python3 -I releases/synclang.py ../../../imports/i18n/data
"""
import json
import sys
from pathlib import Path

WEKAN = Path(sys.argv[1])
DATA = Path(__file__).resolve().parent.parent / 'i18n/data'
LOCAL = {'cavalenc.jsn': 'ca@valencia', 'km_KH.jsn': 'km-KH', 'ru_RU.jsn': 'ru-RU', 'pt_PT.jsn': 'pt-PT'}

changed = files = 0
for f in sorted(DATA.glob('*.jsn')):
    if f.is_symlink():
        continue
    src = WEKAN / (LOCAL.get(f.name, f.stem) + '.i18n.json')
    if not src.exists():
        continue
    words = json.loads(src.read_text(encoding='utf-8'))
    have = json.loads(f.read_text(encoding='utf-8'))
    n = 0
    for key, value in have.items():
        if key in words and isinstance(words[key], str) and words[key] != value:
            have[key] = words[key]
            n += 1
    if n:
        f.write_text(json.dumps(have, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        changed += n
        files += 1
print('%d texts in %d catalogs' % (changed, files))

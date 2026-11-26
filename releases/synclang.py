#!/usr/bin/env python3
"""Bring WeLite's catalogs (i18n/data/*.jsn) up to WeKan's own
(imports/i18n/data/*.i18n.json), the source of every WeKan prototype's
translations: each key a WeLite catalog has takes WeKan's text for it, in
the same language, so a correction made in WeKan reaches WeLite. A key
WeKan does not have stays as it is; the files' 2-space form is kept.

A key en.jsn has that a catalog lacks is added from WeKan's catalog of the
same language, and every catalog keeps en.jsn's key order (tests/*lang.py
check it): a key added to en.jsn alone - as the enrollment texts of
2026-11-18 were - otherwise left the other catalogs a key short.

    python3 -I releases/synclang.py ../../../imports/i18n/data
"""
import json
import sys
from pathlib import Path

WEKAN = Path(sys.argv[1])
DATA = Path(__file__).resolve().parent.parent / 'i18n/data'
LOCAL = {'cavalenc.jsn': 'ca@valencia', 'km_KH.jsn': 'km-KH', 'ru_RU.jsn': 'ru-RU', 'pt_PT.jsn': 'pt-PT'}

ORDER = list(json.loads((DATA / 'en.jsn').read_text(encoding='utf-8')))
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
    if f.name != 'en.jsn':
        for key in ORDER:
            if key not in have and isinstance(words.get(key), str):
                have[key] = words[key]
                n += 1
        ordered = {key: have[key] for key in ORDER if key in have}
        ordered.update((key, value) for key, value in have.items() if key not in ordered)
        if list(ordered) != list(have):
            n += 1
        have = ordered
    if n:
        f.write_text(json.dumps(have, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        changed += n
        files += 1
print('%d texts in %d catalogs' % (changed, files))

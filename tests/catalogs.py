#!/usr/bin/env python3
"""WeLite's catalogs are WeKan's: every text a WeLite catalog
(i18n/data/*.jsn) has is WeKan's text for that key in the same language
(imports/i18n/data), placeholders and all - so no catalog keeps a
translation WeKan corrected, or one in another language than its own.

    WEKAN=/path/to/wekan python3 -I tests/catalogs.py

releases/synclang.py brings them up to WeKan's.
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEKAN = Path(os.environ.get('WEKAN', ROOT.parent.parent.parent)) / 'imports/i18n/data'
LOCAL = {'cavalenc.jsn': 'ca@valencia', 'km_KH.jsn': 'km-KH', 'ru_RU.jsn': 'ru-RU', 'pt_PT.jsn': 'pt-PT'}
TOKEN = re.compile(r'__[A-Za-z][A-Za-z0-9]*__|%\d*\$?[sd]')


def main():
    english = json.loads((WEKAN / 'en.i18n.json').read_text(encoding='utf-8'))
    stale, checked = [], 0
    for f in sorted((ROOT / 'i18n/data').glob('*.jsn')):
        if f.is_symlink():
            continue
        src = WEKAN / (LOCAL.get(f.name, f.stem) + '.i18n.json')
        if not src.exists():
            continue
        words = json.loads(src.read_text(encoding='utf-8'))
        for key, value in json.loads(f.read_text(encoding='utf-8')).items():
            if key not in words:
                continue
            checked += 1
            if value != words[key]:
                stale.append('%s %s: %r, WeKan %r' % (f.name, key, value, words[key]))
            # Negative: a placeholder is the English one, never translated.
            if key in english and sorted(TOKEN.findall(value)) != sorted(TOKEN.findall(english[key])):
                stale.append('%s %s: placeholders %r, English %r' % (f.name, key, TOKEN.findall(value), TOKEN.findall(english[key])))
    for line in stale[:20]:
        print('FAIL:', line)
    assert not stale, '%d texts differ from WeKan: run releases/synclang.py' % len(stale)
    assert checked > 100000, checked
    print('PASS: WeLite catalogs are WeKan\'s, %d texts' % checked)


if __name__ == '__main__':
    sys.exit(main())

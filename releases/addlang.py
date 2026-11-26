#!/usr/bin/env python3
"""Add WeKan's translation keys to WeLite's catalogs (i18n/data/*.jsn): for
each key a WeLite page starts to use, WeKan's text for it in each language
(imports/i18n/data), or WeKan's English when WeKan has no such catalog. A
catalog that has the key already is left as it is; releases/synclang.py
brings existing texts up to WeKan's.

    python3 -I releases/addlang.py ../../../imports/i18n/data key1 [key2 ...]

A key WeKan does not have is not added: a new string goes into WeKan's
catalogs first, for every language, and comes here from there.
"""
import json
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / 'i18n/data'
LOCAL = {'cavalenc.jsn': 'ca@valencia', 'km_KH.jsn': 'km-KH', 'ru_RU.jsn': 'ru-RU', 'pt_PT.jsn': 'pt-PT'}


def main():
    wekan, keys = Path(sys.argv[1]), sys.argv[2:]
    english = json.loads((wekan / 'en.i18n.json').read_text(encoding='utf-8'))
    missing = [k for k in keys if k not in english]
    assert not missing, 'not in WeKan\'s catalogs: %s' % ', '.join(missing)
    done = 0
    for f in sorted(DATA.glob('*.jsn')):
        if f.is_symlink():
            continue
        src = wekan / (LOCAL.get(f.name, f.stem) + '.i18n.json')
        words = json.loads(src.read_text(encoding='utf-8')) if src.exists() else english
        have = json.loads(f.read_text(encoding='utf-8'))
        add = [k for k in keys if k not in have]
        if not add:
            continue
        for k in add:
            have[k] = words.get(k, english[k])
        f.write_text(json.dumps(have, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        done += 1
    print('%d catalogs' % done)


if __name__ == '__main__':
    sys.exit(main())

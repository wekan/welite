#!/usr/bin/env python3
"""WeKan's canonical() of a history value (src/wlchhash.pas), as plain data.

    FPC=/path/to/fpc python3 -I tests/histhash.py

A changeHistory row's integrityHash is SHA-256 of canonical(): keys sorted,
arrays in order, numbers as JavaScript's JSON.stringify writes them
(models/lib/changeHistoryIntegrity.js). A rule's history rows hold whole
snapshots - arrays, numbers, nested objects - so WeLite's canonical text must
be WeKan's byte for byte, or WeKan reads every row WeLite wrote as tampered.
"""
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')


def js_number(x):
    # JSON.stringify of a number.
    if isinstance(x, bool):
        return 'true' if x else 'false'
    if isinstance(x, int) or (isinstance(x, float) and x.is_integer() and abs(x) < 1e21):
        return str(int(x))
    r = repr(float(x))
    if 'e' in r or 'E' in r:
        mant, exp = r.lower().split('e')
        exp = int(exp)
        if 1e-6 <= abs(x) < 1e21:
            return format(x, 'f').rstrip('0').rstrip('.') if exp < 0 else r
        if mant.endswith('.0'):
            mant = mant[:-2]
        return '%se%s%d' % (mant, '+' if exp >= 0 else '-', abs(exp))
    return r


def canonical(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return js_number(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return '[' + ','.join(canonical(x) for x in v) + ']'
    return '{' + ','.join('%s:%s' % (json.dumps(k, ensure_ascii=False), canonical(v[k])) for k in sorted(v)) + '}'


CASES = [
    {'rule': None},
    {'rule': {'_id': 'r1', 'title': 'Sääntö "x"', 'enabled': True, 'boardId': 'b', 'extraActionIds': ['a2', 'a3']},
     'trigger': {'activityType': 'createCard', 'advanced': {'preserve': True, 'depth': 2}, 'listName': '*'},
     'action': {'actionType': 'setDateRelative', 'days': 3, 'ratio': 2.5, 'tiny': 0.000001, 'tinier': 1.5e-7, 'big': 1e21,
                'neg': -0.25, 'pi': 3.141592653589793, 'zero': 0}},
    [1, [2, [3, None]], {'b': 1, 'a': 2, 'B': 3, '_k': 4}],
]
# Negative: canonical text is not JSON's own - key order and spacing differ.
assert canonical({'b': 1, 'a': 2}) != json.dumps({'b': 1, 'a': 2})


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='histhash.', dir=base) as name:
        tmp = Path(name)
        src = tmp / 'histcheck.lpr'
        lines = ['program histcheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, fpjson, jsonparser, wlsjson, wlchhash;',
                 'var D: TJSONData;', 'begin', '  SetMultiByteConversionCodePage(CP_UTF8); // as wlhttp.lpr']
        for c in CASES:
            lines += ["  D := GetJSON(%s); WriteLn(CanonicalHistoryValue(D)); D.Free;" % ("'" + json.dumps(c, ensure_ascii=True).replace("'", "''") + "'")]
        lines.append('end.')
        src.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        r = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert r.returncode == 0, r.stdout
        run = subprocess.run([str(out / 'histcheck')], capture_output=True)
        assert run.returncode == 0, run.stdout + run.stderr
        got = run.stdout.decode('utf-8').split('\n')
        failed = 0
        for c, line in zip(CASES, got):
            want = canonical(c)
            if line != want:
                failed += 1
                print('FAIL\n  got  %s\n  want %s' % (line, want))
        assert failed == 0, failed
    print('PASS: history canonical text, %d values' % len(CASES))


if __name__ == '__main__':
    sys.exit(main())

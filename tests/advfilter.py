#!/usr/bin/env python3
"""The Filter sidebar's Advanced Filter (src/wladvf.pas), as plain data.

    FPC=/path/to/fpc python3 -I tests/advfilter.py

A board with a text, a number, a dropdown, a date and a currency field and
four cards; each case is a filter and the cards it shows - or None for one
that does not parse, which shows no selection of its own. WeKan's examples
(advanced-filter-description) are among them.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

FIELDS = [('Field1', 'f1', 'text', []), ('Points', 'f2', 'number', []), ('Prio', 'f3', 'dropdown', ['High=o1', 'Low=o2']),
          ('Ends', 'f4', 'date', []), ('Price', 'f5', 'currency', []), ('Field 2', 'f6', 'text', [])]
# card: {field id: value or None}, and its @dueAt.
CARDS = {
    'a': ({'f1': "I'm", 'f2': '2', 'f3': 'o1', 'f4': '2026-06-04T10:00:00.000Z', 'f5': '10.50', 'f6': 'Value 2'}, '2026-09-01T12:00:00.000Z'),
    'b': ({'f1': 'Test case', 'f2': '5', 'f3': 'o2', 'f5': '10.5'}, ''),
    'c': ({'f1': 'other', 'f2': None, 'f4': '2026-06-05T00:30:00.000Z'}, '2026-08-01T00:00:00.000Z'),
    'd': ({}, ''),
    # A shared store's JSON date: milliseconds (2026-09-10T12:00:00Z).
    'e': ({}, '1789041600000'),
}
CASES = [
    ("Field1 == I\\'m", 'a'),
    ("Field1 == 'I\\'m'", None),          # a quote ends the text: unbalanced
    ('Field1 == /Tes.*/i', 'b'),
    ('Field1 == /tes.*/', ''),
    ('Field1 != /Tes.*/i', 'ac'),
    ("'Field 2' == 'Value 2'", 'a'),
    ('Points = 2', 'a'),
    ('Points > 1', 'ab'),
    ('Points >= 5 or Field1 == other', 'bc'),
    ('Points > 1 and not (Points > 2)', 'a'),
    ('Points GT 4', 'b'),
    ('Points > 2hours', None),
    ('Prio == High', 'a'),
    ('Prio != High', 'b'),
    ('Ends == 2026-06-04', 'a'),
    ('Ends > 2026-06-04', 'c'),
    ('Ends < 2026-06-05', 'a'),
    ('Price == 10.5', 'ab'),
    ('Price > 10.49', 'ab'),
    ('@dueAt = none', 'bd'),
    ('@dueAt != none', 'ace'),
    ("@dueAt < '2026-09-01'", 'c'),
    ('@dueAt >= 2026-09-01', 'ae'),
    ('( Points = 2 ) or ( Points = 5 )', 'ab'),
    ('Points = 2 or Points = 5 and Field1 == other', ''),   # left to right: (a or b) and c
    ('! Points = 2', 'bcde'),
    # Negative: no such field, an operator that is none, brackets that do not
    # close, a regex that does not compile, a dangling operator, depth.
    ('Nope == 1', None),
    ('Points ~ 1', None),
    ('( Points = 2', None),
    ('Points = 2 )', None),
    ('Field1 == /(/', None),
    ('Points = 2 and', None),
    ('@nodate = none', None),
    ('@dueAt > none', None),
    ('(' * 150 + 'Points = 2' + ')' * 150, None),
    ('', None),
]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='advfilter.', dir=base) as name:
        tmp = Path(name)
        L = ['program advcheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, wladvf;',
             'var F: array of TAdvField; C: array of TAdvCard; N: TAdvNode; i: Integer; S: string;', 'begin',
             '  SetLength(F, %d);' % len(FIELDS)]
        for i, (n, fid, kind, opts) in enumerate(FIELDS):
            L.append('  F[%d].Name := %s; F[%d].Id := %s; F[%d].Kind := %s;' % (i, q(n), i, q(fid), i, q(kind)))
            L.append('  SetLength(F[%d].Options, %d);' % (i, len(opts)))
            L += ['  F[%d].Options[%d] := %s;' % (i, j, q(o)) for j, o in enumerate(opts)]
        L.append('  SetLength(C, %d);' % len(CARDS))
        for i, (cid, (values, due)) in enumerate(CARDS.items()):
            L.append('  SetLength(C[%d].Values, %d);' % (i, len(values)))
            for j, (fid, v) in enumerate(values.items()):
                L.append('  C[%d].Values[%d].FieldId := %s; C[%d].Values[%d].Value := %s; C[%d].Values[%d].IsNull := %s;'
                         % (i, j, q(fid), i, j, q(v or ''), i, j, 'True' if v is None else 'False'))
            L.append('  C[%d].Dates[3] := %s;' % (i, q(due)))
        for text, _ in CASES:
            L += ['  N := ParseAdvancedFilter(%s, F);' % q(text), "  if N = nil then WriteLn('-') else begin S := '';",
                  '    for i := 0 to High(C) do if AdvancedFilterMatches(N, C[i]) then S := S + %s[i + 1];' % q(''.join(CARDS)),
                  "    WriteLn('=', S); N.Free; end;"]
        L.append('end.')
        src = tmp / 'advcheck.lpr'
        src.write_text('\n'.join(L) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        r = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert r.returncode == 0, r.stdout
        # The server's clock as UTC, so the days typed are UTC days here.
        got = subprocess.run([str(out / 'advcheck')], capture_output=True, check=True, text=True, env={**os.environ, 'TZ': 'UTC'}).stdout.split('\n')
        failed = 0
        for (text, want), line in zip(CASES, got):
            expect = '-' if want is None else '=' + want
            if line != expect:
                failed += 1
                print('FAIL: %r\n  got  %s\n  want %s' % (text[:80], line, expect))
        assert failed == 0, failed
    print('PASS: Advanced Filter, %d filters' % len(CASES))


if __name__ == '__main__':
    sys.exit(main())

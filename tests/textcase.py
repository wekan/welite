#!/usr/bin/env python3
"""Upper and lower case of UTF-8 text without a unicodestring manager
(src/wlcase.pas), as plain data.

    FPC=/path/to/fpc python3 -I tests/textcase.py

A WeLite binary installs no unicodestring manager, so WideUpperCase and
UTF8Decode give "no string conversion support" and an empty string (the Rules
page's descriptions were empty that way). Each case is checked against
Python's own case mapping; the negative cases are text that has no case, and
bytes that are not UTF-8, which stay as they are.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

WORDS = ['when a card is moved', 'Kun kortti siirretään', 'ÄÖÅ äöå', 'élève à la tâche', 'Šta je ŽELJA', 'ĳzer ŀ',
         'Καλημέρα ΚΌΣΜΕ', 'Привет МИР ёЁ', 'Їжак і ґанок', 'Ÿ ÿ', '12345 - !?', '日本語のカード', '']
BROKEN = b'abc\xff\xfe'


def q(s):
    return "'" + s.replace("'", "''") + "'"


def pas(b):
    # The bytes as a Pascal string: ASCII quoted, the rest #$xx.
    out, quoted = '', False
    for c in b:
        if 32 <= c < 127:
            if not quoted:
                out += "'"
                quoted = True
            out += "''" if c == 39 else chr(c)
        else:
            if quoted:
                out += "'"
                quoted = False
            out += '#$%02x' % c
    if quoted:
        out += "'"
    return out or "''"


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='textcase.', dir=base) as name:
        tmp = Path(name)
        L = ['program casecheck;', '{$mode objfpc}{$H+}', 'uses SysUtils, wlcase;',
             "procedure Hex(const S: string); var i: Integer; T: string; begin T := '';",
             '  for i := 1 to Length(S) do T := T + IntToHex(Ord(S[i]), 2); WriteLn(T); end;', 'begin']
        for w in WORDS + [None]:
            b = BROKEN if w is None else w.encode()
            L += ['  Hex(Utf8Lower(%s));' % pas(b), '  Hex(Utf8Upper(%s));' % pas(b), '  Hex(Utf8CapitalFirst(%s));' % pas(b)]
        L.append('end.')
        src = tmp / 'casecheck.lpr'
        src.write_text('\n'.join(L) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        r = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert r.returncode == 0, r.stdout
        got = subprocess.run([str(out / 'casecheck')], capture_output=True, check=True, text=True).stdout.split('\n')
        failed = 0
        k = 0
        for w in WORDS + [None]:
            if w is None:
                want = [BROKEN, BROKEN.upper(), b'Abc\xff\xfe']
            else:
                want = [w.lower().encode(), w.upper().encode(), (w[:1].upper() + w[1:]).encode()]
            for kind, exp in zip(('lower', 'upper', 'capital'), want):
                if got[k] != exp.hex().upper():
                    failed += 1
                    print('FAIL: %s %r\n  got  %s\n  want %s' % (kind, w, bytes.fromhex(got[k]), exp))
                k += 1
        assert failed == 0, failed
    print('PASS: text case, %d texts' % (len(WORDS) + 1))


if __name__ == '__main__':
    sys.exit(main())

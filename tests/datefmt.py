#!/usr/bin/env python3
"""The date format a date is drawn in (src/wldatef.pas): WeKan's
resolveDateFormat (models/lib/dateFormatPolicy.js) and the text of a date in
each of its six formats.

    FPC=/path/to/fpc [NODE=/path/to/node] [WEKAN=/path/to/wekan] python3 -I tests/datefmt.py

The cascade - member, board, Admin Panel, YYYY-MM-DD - is compared with
WeKan's own JavaScript for every combination when Node.js is there. The
negative cases: a level that is off is skipped even with a valid format, a
format that is not one of the six is never used, and a value that is no date
is drawn as before.
"""
import itertools
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')
FORMATS = ['YYYY-MM-DD', 'DD-MM-YYYY', 'MM-DD-YYYY', 'YYYY-MM-DD-date-only', 'DD-MM-YYYY-date-only', 'MM-DD-YYYY-date-only']
VALUES = ['MM-DD-YYYY', 'DD-MM-YYYY-date-only', 'invalid', '']
RESOLVE = [(m, mo, b, bo, g, go) for m, b, g in itertools.product(VALUES, repeat=3)
           for mo, bo, go in itertools.product([False, True], repeat=3)]
DATES = [
    ('2026-03-21T12:00:00.000Z', 'YYYY-MM-DD', '2026-03-21 12:00'),
    ('2026-03-21T12:00:00.000Z', 'DD-MM-YYYY', '21-03-2026 12:00'),
    ('2026-03-21T12:00:00.000Z', 'MM-DD-YYYY', '03-21-2026 12:00'),
    ('2026-03-21T12:00:00.000Z', 'YYYY-MM-DD-date-only', '2026-03-21'),
    ('2026-03-21T12:00:00.000Z', 'DD-MM-YYYY-date-only', '21-03-2026'),
    ('2026-03-21T12:00:00.000Z', 'MM-DD-YYYY-date-only', '03-21-2026'),
    ('2026-03-21', 'DD-MM-YYYY', '21-03-2026'),
    # Negative: not a date, drawn as before; an unknown format is YYYY-MM-DD.
    ('tomorrow', 'DD-MM-YYYY', 'tomorrow'),
    ('2026-3-21T12:00', 'DD-MM-YYYY', '2026-3-21 12:00'),
    ('2026-03-21T12:00:00.000Z', 'invalid', '2026-03-21 12:00'),
    ('', 'DD-MM-YYYY', ''),
]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def b(v):
    return 'True' if v else 'False'


def main():
    with tempfile.TemporaryDirectory(prefix='wldatef-', dir=os.environ.get('TMPDIR')) as tmp:
        program = Path(tmp) / 'datefmt.pas'
        lines = ['program datefmt;', '{$mode objfpc}{$H+}', 'uses wldatef;', 'begin']
        for m, mo, bd, bo, g, go in RESOLVE:
            lines.append('  WriteLn(ResolveDateFormat(%s,%s,%s,%s,%s,%s));' % (q(m), b(mo), q(bd), b(bo), q(g), b(go)))
        for value, fmt, _ in DATES:
            lines.append('  WriteLn(FormatShownDate(%s,%s));' % (q(value), q(fmt)))
        lines.append('end.')
        program.write_text('\n'.join(lines) + '\n')
        subprocess.run([FPC, '-Fu' + str(ROOT / 'src'), '-FU' + tmp, '-FE' + tmp, str(program)], check=True, capture_output=True)
        out = subprocess.run([str(Path(tmp) / 'datefmt')], check=True, capture_output=True, text=True).stdout.split('\n')
    resolved, shown = out[:len(RESOLVE)], out[len(RESOLVE):len(RESOLVE) + len(DATES)]
    for (m, mo, bd, bo, g, go), got in zip(RESOLVE, resolved):
        want = m if mo and m in FORMATS else bd if bo and bd in FORMATS else g if go and g in FORMATS else 'YYYY-MM-DD'
        assert got == want, ((m, mo, bd, bo, g, go), got, want)
    for (value, fmt, want), got in zip(DATES, shown):
        assert got == want, (value, fmt, got, want)
    print('PASS: %d cascades and %d dates: member, board, Admin Panel, YYYY-MM-DD, never an unknown format' % (len(RESOLVE), len(DATES)))
    wekan, node = os.environ.get('WEKAN'), os.environ.get('NODE')
    policy = Path(wekan or '') / 'models/lib/dateFormatPolicy.js'
    if wekan and node and policy.exists():
        script = ("const {resolveDateFormat}=require(process.argv[1]);"
                  "console.log(JSON.stringify(JSON.parse(process.argv[2]).map(([m,mo,b,bo,g,go])=>"
                  "resolveDateFormat(m,{hideDateFormat:go,globalDateFormat:g},{dateFormatOverride:bo,dateFormat:b},mo))));")
        js = json.loads(subprocess.run([node, '-e', script, str(policy), json.dumps(RESOLVE)],
                                       check=True, capture_output=True, text=True).stdout)
        assert js == resolved, [(c, a, w) for c, a, w in zip(RESOLVE, resolved, js) if a != w][:5]
        print("PASS: the same %d cascades give WeKan's own resolveDateFormat answers" % len(RESOLVE))


if __name__ == '__main__':
    main()

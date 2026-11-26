#!/usr/bin/env python3
"""When a scheduled rule trigger fires (src/wlsched.pas): WeKan's five-field
cron (models/lib/cronSchedule.js, UTC), the calendar day conditions and the
time slot (server/scheduledRules.js), and which cards a "due" trigger acts on
(models/lib/scheduledDueFilter.js).

    FPC=/path/to/fpc [NODE=/path/to/node] [WEKAN=/path/to/wekan] python3 -I tests/sched.py

The cron answers and the date conditions are compared with WeKan's own
JavaScript when Node.js is there, for every expression and moment below -
the invalid expressions (six fields, out of range, a backwards range, step 0,
names where none are allowed) included: invalid never fires.
"""
import datetime as dt
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

CRONS = ['* * * * *', '30 5 * * 1-5', '0 9 * * MON-FRI', '*/15 * * * *', '0 0 1,15 * *', '0 12 * JAN-MAR *',
         '0 0 * * 7', '0 0 * * 0', '5-10/2 * * * *', '0 0 13 * 5', '0 */2 * * *', '59 23 31 12 *',
         # Negative: not a schedule.
         '* * * *', '* * * * * *', '60 * * * *', '* 24 * * *', '* * 0 * *', '* * * 13 *', '* * * * 8',
         '10-5 * * * *', '*/0 * * * *', 'MON * * * *', '', 'a b c d e', '1-2-3 * * * *']
MOMENTS = ['2026-11-26T05:30:00Z', '2026-11-27T09:00:00Z', '2026-11-29T00:00:00Z', '2026-11-30T00:00:00Z',
           '2026-12-15T00:00:00Z', '2026-02-13T00:00:00Z', '2026-03-13T12:00:00Z', '2026-12-31T23:59:00Z',
           '2026-11-26T05:07:00Z', '2026-11-26T02:00:00Z', '2026-11-26T03:45:00Z']
NOW_MS = 1795000000000
DATES = [('set', 0, NOW_MS - 10), ('set', 0, None), ('soon', 2, NOW_MS + 86400000), ('soon', 2, NOW_MS + 3 * 86400000),
         ('soon', 0, NOW_MS), ('soon', 2, NOW_MS - 1000), ('overdue', 1, NOW_MS - 2 * 86400000),
         ('overdue', 3, NOW_MS - 2 * 86400000), ('overdue', 0, NOW_MS), ('nope', 1, NOW_MS), ('overdue', -1, NOW_MS + 1000)]


def iso_ms(ms):
    return dt.datetime.fromtimestamp(ms / 1000, dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.') + '%03dZ' % (ms % 1000)


def q(s):
    return "'" + s.replace("'", "''") + "'"


def pas_dt(iso):
    d = dt.datetime.strptime(iso, '%Y-%m-%dT%H:%M:%SZ')
    return 'EncodeDateTime(%d,%d,%d,%d,%d,%d,0)' % (d.year, d.month, d.day, d.hour, d.minute, d.second)


def main():
    lines = ['program schedt;', '{$mode objfpc}{$H+}', 'uses SysUtils, DateUtils, wlsched;', 'begin']
    for c in CRONS:
        for m in MOMENTS:
            lines.append("  WriteLn(BoolToStr(CronMatches(%s,%s),'1','0'));" % (q(c), pas_dt(m)))
    for cond, days, at in DATES:
        lines.append("  WriteLn(BoolToStr(MatchesScheduledDate(%s,%s,%s,%d),'1','0'));" %
                     (q(iso_ms(at) if at is not None else ''), q(cond), repr(float(days)), NOW_MS))
    cal = [('once', '2026-11-26', '', ''), ('once', '2026-11-27', '', ''), ('daily', '', '', ''), ('weekday', '', '', ''),
           ('weekly', '', '4', ''), ('weekly', '', '5', ''), ('monthly', '', '', '26'), ('monthly', '', '', '1'), ('yearly', '', '', '')]
    for kind, on, wd, dom in cal:
        lines.append("  WriteLn(BoolToStr(CalendarDue(%s,%s,%s,%s,EncodeDateTime(2026,11,26,9,0,0,0)),'1','0'));" % (q(kind), q(on), q(wd), q(dom)))
    lines.append("  WriteLn(SlotKey(EncodeDateTime(2026,11,26,9,5,0,0)), '|', HourMinute(EncodeDateTime(2026,11,26,9,5,0,0)));")
    lines.append('end.')
    with tempfile.TemporaryDirectory(prefix='wlsched-', dir=os.environ.get('TMPDIR')) as tmp:
        program = Path(tmp) / 'schedt.pas'
        program.write_text('\n'.join(lines) + '\n')
        subprocess.run([FPC, '-Fu' + str(ROOT / 'src'), '-FU' + tmp, '-FE' + tmp, str(program)], check=True, capture_output=True)
        out = subprocess.run([str(Path(tmp) / 'schedt')], check=True, capture_output=True, text=True).stdout.split('\n')
    n = len(CRONS) * len(MOMENTS)
    cron, dates, calendar, slot = out[:n], out[n:n + len(DATES)], out[n + len(DATES):n + len(DATES) + len(cal)], out[n + len(DATES) + len(cal)]
    # 2026-11-26 is a Thursday.
    assert calendar == ['1', '0', '1', '1', '1', '0', '1', '0', '0'], calendar
    assert slot == '2026-11-26 09:05|09:05', slot
    assert cron[CRONS.index('* * * * *') * len(MOMENTS):][:len(MOMENTS)] == ['1'] * len(MOMENTS)
    for i, c in enumerate(CRONS[CRONS.index('* * * *'):]):
        row = cron[(CRONS.index('* * * *') + i) * len(MOMENTS):][:len(MOMENTS)]
        assert row == ['0'] * len(MOMENTS), ('an invalid schedule fired', c)
    print('PASS: %d cron answers, %d date conditions, the calendar days and the slot' % (n, len(DATES)))
    wekan, node = os.environ.get('WEKAN'), os.environ.get('NODE')
    if wekan and node and (Path(wekan) / 'models/lib/cronSchedule.js').exists():
        script = ("const c=require(process.argv[1]),f=require(process.argv[2]);const a=JSON.parse(process.argv[3]);"
                  "const out=[];for(const e of a.crons)for(const m of a.moments){let r=false;try{r=c.isValidCron(e)&&c.cronMatches(e,new Date(m));}catch(x){}out.push(r?'1':'0');}"
                  "for(const [cond,days,at] of a.dates)out.push(f.matchesScheduledDate({dueAt:at===null?undefined:new Date(at).toISOString()},{dueCondition:cond,days},a.now)?'1':'0');"
                  "console.log(JSON.stringify(out));")
        js = json.loads(subprocess.run([node, '-e', script, str(Path(wekan) / 'models/lib/cronSchedule.js'),
                                        str(Path(wekan) / 'models/lib/scheduledDueFilter.js'),
                                        json.dumps({'crons': CRONS, 'moments': MOMENTS, 'dates': DATES, 'now': NOW_MS})],
                                       check=True, capture_output=True, text=True).stdout)
        mine = cron + dates
        diff = [(i, a, b) for i, (a, b) in enumerate(zip(mine, js)) if a != b]
        assert not diff, [(CRONS[i // len(MOMENTS)] if i < n else DATES[i - n], MOMENTS[i % len(MOMENTS)] if i < n else '', a, b) for i, a, b in diff][:8]
        print("PASS: the same %d answers as WeKan's own cronSchedule.js and scheduledDueFilter.js" % len(mine))


if __name__ == '__main__':
    main()

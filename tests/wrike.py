#!/usr/bin/env python3
"""A Wrike workflow and the board it is (src/wlwrike.pas), as plain data.

    FPC=/path/to/fpc python3 -I tests/wrike.py

The groups a status' name alone suggests; GET /workflows' JSON read - the
first workflow that is neither hidden nor Wrike's standard one, its statuses
without the hidden and the repeated ones, Wrike's colors as WeKan's - and the
refusals (not JSON, no workflow, no status); and a board written back as a
workflow, with an Active and a Completed status added when no list is one.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FPC = os.environ.get('FPC', 'fpc')

GROUP_CASES = [('Done', 'Completed'), ('  shipped ', 'Completed'), ("Won't fix", 'Cancelled'), ('On hold', 'Deferred'),
               ('cancelled', 'Cancelled'), ('Active', 'Active'), ('In review', 'Active'), ('', 'Active')]
DELIVERY = {'kind': 'workflows', 'data': [
    {'name': 'Default Workflow', 'standard': True, 'hidden': False, 'customStatuses': [{'name': 'Active', 'group': 'Active'}]},
    {'name': 'Delivery', 'standard': False, 'hidden': False, 'customStatuses': [
        {'name': 'Queued', 'group': 'Active', 'color': 'Blue'},
        {'name': 'Building', 'group': 'Active', 'color': 'Orange'},
        {'name': 'Shipped', 'group': 'Completed', 'color': 'Green'},
        {'name': 'Dropped', 'group': 'Cancelled', 'color': 'Red'},
        {'name': 'Retired', 'group': 'Active', 'color': 'Gray', 'hidden': True},
        {'name': 'Queued', 'group': 'Active'},
        {'name': 'Odd', 'group': 'Nonsense'}]}]}
READ_CASES = [
    (json.dumps(DELIVERY), 'Delivery|Queued:Active:blue,Building:Active:orange,Shipped:Completed:green,Dropped:Cancelled:red,'
                           'Odd:Active:|4'),
    (json.dumps({'name': 'One', 'customStatuses': [{'name': 'Only', 'group': 'Completed'}]}), 'One|Only:Completed:|0'),
    # Negative: not JSON, no workflow, no status to read.
    ('{ not json', '-Wrike workflow is not JSON'),
    ('{"kind": "workflows", "data": []}', '-Wrike workflow JSON has no workflow'),
    (json.dumps({'data': [{'name': 'Empty', 'customStatuses': [{'name': 'Gone', 'hidden': True}]}]}), '-Wrike workflow "Empty" has no status'),
]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    base = Path(os.environ.get('TMPDIR') or tempfile.gettempdir())
    with tempfile.TemporaryDirectory(prefix='wrike.', dir=base) as name:
        tmp = Path(name)
        L = ['program wrikecheck;', '{$mode objfpc}{$H+}', '{$CODEPAGE UTF8}', 'uses SysUtils, Classes, fpjson, jsonparser, wlwrike;',
             'var N, E, S: string; St: TWrikeStatuses; NotRead, i: Integer; Lists: TWrikeLists; C: TStringList; W: TJSONObject;',
             'begin']
        L += ["  WriteLn(WrikeGroupForName(%s));" % q(n) for n, _ in GROUP_CASES]
        for text, _ in READ_CASES:
            L += ["  if ReadWrikeWorkflow(%s, N, St, NotRead, E) then begin S := N + '|';" % q(text),
                  "    for i := 0 to High(St) do begin if i > 0 then S := S + ','; S := S + St[i].Name + ':' + St[i].Group + ':' + St[i].Color; end;",
                  "    WriteLn(S, '|', NotRead); end else WriteLn('-', E);"]
        # A board: two lists, one marked complete by a move rule, none Completed by name.
        L += ["  SetLength(Lists, 3); Lists[0].Title := 'Todo'; Lists[1].Title := 'Ship it'; Lists[1].Color := 'orange';",
              "  Lists[2].Title := 'Todo'; C := TStringList.Create; C.Values['Ship it'] := 'complete';",
              "  W := WrikeWorkflowFromBoard('Board', Lists, C); WriteLn(W.AsJSON); W.Free;",
              "  C.Clear; SetLength(Lists, 1); Lists[0].Title := 'Done';",
              "  W := WrikeWorkflowFromBoard('', Lists, C); WriteLn(W.AsJSON); W.Free; C.Free;", 'end.']
        src = tmp / 'wrikecheck.lpr'
        src.write_text('\n'.join(L) + '\n', encoding='utf-8')
        out = tmp / 'build'
        out.mkdir()
        r = subprocess.run([FPC, '-B', '-Fu' + str(ROOT / 'src'), '-FU' + str(out), '-FE' + str(out), str(src)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert r.returncode == 0, r.stdout
        got = subprocess.run([str(out / 'wrikecheck')], capture_output=True, check=True, text=True).stdout.split('\n')
        failed = 0
        k = 0
        for n, want in GROUP_CASES:
            if got[k] != want:
                failed += 1
                print('FAIL group %r: %s, want %s' % (n, got[k], want))
            k += 1
        for text, want in READ_CASES:
            if not got[k].startswith(want):
                failed += 1
                print('FAIL read %r\n  got  %s\n  want %s' % (text[:60], got[k], want))
            k += 1
        board = json.loads(got[k])
        statuses = board['data'][0]['customStatuses']
        want = [('Todo', 'Active', 'Blue'), ('Ship it', 'Completed', 'Orange')]
        if board['kind'] != 'workflows' or board['data'][0]['name'] != 'Board' or \
                [(s['name'], s['group'], s['color']) for s in statuses] != want:
            failed += 1
            print('FAIL board: %s' % got[k])
        board = json.loads(got[k + 1])
        statuses = board['data'][0]['customStatuses']
        # A board whose only list is Completed gets an Active status first; no
        # title is "WeKan board".
        if board['data'][0]['name'] != 'WeKan board' or [(s['name'], s['group']) for s in statuses] != [('Active', 'Active'), ('Done', 'Completed')]:
            failed += 1
            print('FAIL board without Active: %s' % got[k + 1])
        assert failed == 0, failed
    print('PASS: Wrike workflows, %d cases' % (len(GROUP_CASES) + len(READ_CASES) + 2))


if __name__ == '__main__':
    sys.exit(main())
